import Foundation
import SupervimCore

public protocol PointerReading: AnyObject, Sendable {
    func currentPointer() -> ActuatorPoint?
}

/// Moves accessibility focus to a previously found input.
/// Returning false means the input was not focused. The session then stays in Normal.
public protocol InputFocusing: AnyObject, Sendable {
    func focusInput(path: [Int]) -> Bool
}

/// Task 12 claims `?`. Returning false from `claimHelp`, or a nil handler, gives that key back.
/// `dismissHelp` closes an open sheet on Esc and returns false when the sheet is closed,
/// so Esc keeps its normal meaning. `yieldHelp` hides the sheet when a hint uses the same panel.
public protocol HelpCommandHandling: AnyObject, Sendable {
    func claimHelp() -> Bool
    func dismissHelp(for event: KeyEvent) -> Bool
    func yieldHelp()
}

/// One key after the actuator and the focus request have run.
public struct CommandPerformance: Equatable, Sendable {
    public var delivery: KeyDelivery
    public var mode: SupervimMode
    public var decision: EventDecision?
    public var outcomes: [ActuatorOutcome]
    public var focusedPath: [Int]?
    /// Nil when the key is given back. A swallow always has a reason.
    public var swallowReason: SwallowReason?

    public init(
        delivery: KeyDelivery,
        mode: SupervimMode,
        decision: EventDecision?,
        outcomes: [ActuatorOutcome],
        focusedPath: [Int]?,
        swallowReason: SwallowReason? = nil
    ) {
        self.delivery = delivery
        self.mode = mode
        self.decision = decision
        self.outcomes = outcomes
        self.focusedPath = focusedPath
        self.swallowReason = swallowReason
    }
}

public final class LockedCommandSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: CommandSnapshot

    public init(snapshot: CommandSnapshot) {
        self.snapshot = snapshot
    }

    public func current() -> CommandSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    public func replace(_ snapshot: CommandSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        self.snapshot = snapshot
    }
}

/// Performs scroll and application-shortcut decisions.
///
/// The key path reads `LockedCommandSnapshot` and the pointer. It does not walk
/// the accessibility tree. `gi` focuses the cached first input, then publishes
/// the focus read. Insert starts only when that read is editable.
/// A scroll with no ready target passes the original key through.
/// `yy`, history, and tab shortcuts use the actuator's browser allowlist.
/// Ctrl+] is not posted, and the following key is not posted either.
public final class NormalCommandSession: @unchecked Sendable {
    private let pipeline: FocusPipeline
    private let decider: any KeyDeciding
    private let actuator: ActionActuator
    private let snapshots: LockedCommandSnapshot
    private let pointer: any PointerReading
    private let focuser: any InputFocusing
    private let hints: (any HintOverlayControlling)?
    private let help: (any HelpCommandHandling)?

    public init(
        pipeline: FocusPipeline,
        decider: any KeyDeciding,
        actuator: ActionActuator,
        snapshots: LockedCommandSnapshot,
        pointer: any PointerReading,
        focuser: any InputFocusing,
        hints: (any HintOverlayControlling)? = nil,
        help: (any HelpCommandHandling)? = nil
    ) {
        self.pipeline = pipeline
        self.decider = decider
        self.actuator = actuator
        self.snapshots = snapshots
        self.pointer = pointer
        self.focuser = focuser
        self.hints = hints
        self.help = help
    }

    public func replaceSnapshot(_ snapshot: CommandSnapshot) {
        snapshots.replace(snapshot)
    }

    public func handleKeyDown(_ event: KeyEvent) -> CommandPerformance {
        if let dismissed = dismissedHelp(event) {
            return dismissed
        }
        return finish(pipeline.wiring.handleKeyDown(event), hintKeyCode: nil)
    }

    public func handleSystemRecord(_ record: SystemKeyRecord) -> CommandPerformance {
        if let event = SystemKeyTranslation.keyEvent(from: record), let dismissed = dismissedHelp(event) {
            return dismissed
        }
        let outcome = pipeline.wiring.handleSystemRecord(record)
        guard let decision = outcome.decision else {
            return CommandPerformance(
                delivery: outcome.delivery,
                mode: decider.mode,
                decision: nil,
                outcomes: [],
                focusedPath: nil,
                swallowReason: nil
            )
        }
        return finish(decision, hintKeyCode: record.keyCode)
    }

    private func finish(_ decision: EventDecision, hintKeyCode: UInt16?) -> CommandPerformance {
        let prepared = CommandFollowThrough.prepare(decision)
        let wantsActuation = decision.delivery == .swallow && !prepared.actuatorActions.isEmpty
        let wantsFocus = decision.delivery == .swallow && prepared.requestsFocus
        var outcomes: [ActuatorOutcome] = []
        var reports: [ActuatorReport] = []
        let snapshot = (wantsActuation || wantsFocus) ? snapshots.current() : nil

        if wantsActuation, let snapshot {
            let scrolling = prepared.actuatorActions.contains(where: isScroll)
            let point = scrolling ? pointer.currentPointer() : nil
            let areas = scrolling && snapshot.scrollCatalogReady
                ? ScrollAreaCatalog.retarget(snapshot.scrollAreas, pointer: point, focus: snapshot.focusPoint)
                : []
            let context = ActuationContext(
                bundleIdentifier: pipeline.cache.currentFocus().bundleIdentifier,
                pointer: point,
                scrollAreas: areas
            )
            for action in prepared.actuatorActions {
                let outcome = actuator.perform(action, context: context)
                outcomes.append(outcome)
                reports.append(report(outcome))
            }
        }

        var delivery = CommandFollowThrough.delivery(prepared: prepared, reports: reports)
        let overlayClaimed = claimOverlay(decision, hintKeyCode: hintKeyCode)
        let actuated = reports.contains { $0 == .performed || $0 == .passedThrough }
        var reason = CommandFollowThrough.swallowReason(
            decision,
            actuated: actuated,
            focused: wantsFocus,
            overlayClaimed: overlayClaimed
        )
        if delivery == .swallow, reason == nil {
            delivery = .passThrough
        }
        var mode = decision.mode
        var focusedPath: [Int]?
        if wantsFocus, let snapshot, delivery == .swallow, case .found(let target) = snapshot.firstInput {
            if focuser.focusInput(path: target.path) {
                focusedPath = target.path
                mode = pipeline.scanner.noteFocusChanged().mode
            }
        }
        if overlayClaimed, isHint(decision.overlay) {
            mode = decider.mode
        }
        if delivery == .passThrough, case .hint = decision.mode {
            _ = decider.endHint(.cancelled)
            mode = decider.mode
            reason = nil
        }
        if delivery != .swallow {
            reason = nil
        }

        return CommandPerformance(
            delivery: delivery,
            mode: mode,
            decision: decision,
            outcomes: outcomes,
            focusedPath: focusedPath,
            swallowReason: reason
        )
    }

    private func claimOverlay(_ decision: EventDecision, hintKeyCode: UInt16?) -> Bool {
        switch decision.overlay {
        case .beginHint(let click):
            guard let hints else {
                return false
            }
            help?.yieldHelp()
            _ = hints.enterHint(click)
            return true
        case .hintKey(let event):
            guard let hints else {
                return false
            }
            _ = hints.receiveHintKey(event, keyCode: hintKeyCode)
            return true
        case .endHint:
            guard let hints else {
                return false
            }
            _ = hints.cancelHint()
            return true
        case .showHelp:
            return help?.claimHelp() ?? false
        case nil:
            return false
        }
    }

    private func isHint(_ update: OverlayUpdate?) -> Bool {
        switch update {
        case .beginHint, .hintKey, .endHint:
            return true
        case .showHelp, nil:
            return false
        }
    }

    /// Esc closes help only in Normal. Hint and Insert keep Esc for themselves.
    private func dismissedHelp(_ event: KeyEvent) -> CommandPerformance? {
        guard decider.mode == .normal else {
            return nil
        }
        guard help?.dismissHelp(for: event) == true else {
            return nil
        }
        return CommandPerformance(
            delivery: .swallow,
            mode: decider.mode,
            decision: EventDecision(delivery: .swallow, mode: decider.mode),
            outcomes: [],
            focusedPath: nil,
            swallowReason: .overlay
        )
    }

    private func isScroll(_ action: Action) -> Bool {
        if case .scroll = action {
            return true
        }
        return false
    }

    private func report(_ outcome: ActuatorOutcome) -> ActuatorReport {
        switch outcome {
        case .performed:
            return .performed
        case .passedThrough:
            return .passedThrough
        case .notActuatorWork:
            return .notActuatorWork
        }
    }
}

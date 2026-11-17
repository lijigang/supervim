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

/// One key after the actuator and the focus request have run.
public struct CommandPerformance: Equatable, Sendable {
    public var delivery: KeyDelivery
    public var mode: SupervimMode
    public var decision: EventDecision?
    public var outcomes: [ActuatorOutcome]
    public var focusedPath: [Int]?

    public init(
        delivery: KeyDelivery,
        mode: SupervimMode,
        decision: EventDecision?,
        outcomes: [ActuatorOutcome],
        focusedPath: [Int]?
    ) {
        self.delivery = delivery
        self.mode = mode
        self.decision = decision
        self.outcomes = outcomes
        self.focusedPath = focusedPath
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

    public init(
        pipeline: FocusPipeline,
        decider: any KeyDeciding,
        actuator: ActionActuator,
        snapshots: LockedCommandSnapshot,
        pointer: any PointerReading,
        focuser: any InputFocusing
    ) {
        self.pipeline = pipeline
        self.decider = decider
        self.actuator = actuator
        self.snapshots = snapshots
        self.pointer = pointer
        self.focuser = focuser
    }

    public func handleKeyDown(_ event: KeyEvent) -> CommandPerformance {
        finish(pipeline.wiring.handleKeyDown(event))
    }

    public func handleSystemRecord(_ record: SystemKeyRecord) -> CommandPerformance {
        let outcome = pipeline.wiring.handleSystemRecord(record)
        guard let decision = outcome.decision else {
            return CommandPerformance(
                delivery: outcome.delivery,
                mode: decider.mode,
                decision: nil,
                outcomes: [],
                focusedPath: nil
            )
        }
        return finish(decision)
    }

    private func finish(_ decision: EventDecision) -> CommandPerformance {
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

        let delivery = CommandFollowThrough.delivery(prepared: prepared, reports: reports)
        var mode = decision.mode
        var focusedPath: [Int]?
        if wantsFocus, let snapshot, delivery == .swallow, case .found(let target) = snapshot.firstInput {
            if focuser.focusInput(path: target.path) {
                focusedPath = target.path
                mode = pipeline.scanner.noteFocusChanged().mode
            }
        }

        return CommandPerformance(
            delivery: delivery,
            mode: mode,
            decision: decision,
            outcomes: outcomes,
            focusedPath: focusedPath
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

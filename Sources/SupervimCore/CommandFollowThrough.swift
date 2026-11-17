import Foundation

/// What an actuator reported for one action.
/// The core does not post events. The system session maps its outcome onto this.
public enum ActuatorReport: Equatable, Sendable {
    case performed
    case passedThrough
    case notActuatorWork
}

/// The part of one event-tap decision that task 11 may perform.
public struct PreparedCommand: Equatable, Sendable {
    public var decisionDelivery: KeyDelivery
    public var actuatorActions: [Action]
    public var requestsFocus: Bool

    public init(decisionDelivery: KeyDelivery, actuatorActions: [Action], requestsFocus: Bool) {
        self.decisionDelivery = decisionDelivery
        self.actuatorActions = actuatorActions
        self.requestsFocus = requestsFocus
    }
}

/// Splits an event-tap decision into actuator work and a focus request,
/// then decides whether a missed scroll gives the original key back.
///
/// Scroll, shortcut, and shortcut-sequence actions are actuator work.
/// `focusFirstInput` requests a focus move. It does not enter Insert by itself.
/// Pass-next, hints, help, escape, and manual insert are not actuator work.
///
/// A swallowed key is given back only when every actuator action was a scroll
/// and every report is `passedThrough`. A declined shortcut stays swallowed:
/// the binding was recognized, and replaying one key of `yy` would type a
/// stray character. A key the interpreter already released stays released.
public enum SwallowReason: Equatable, Sendable {
    case actuator
    case focus
    case passNext
    case heldPrefix
    case pause
    case overlay
    case blur
}

public enum CommandFollowThrough {
    public static func prepare(_ decision: EventDecision) -> PreparedCommand {
        var actions: [Action] = []
        var requestsFocus = false
        for action in decision.actions {
            switch action {
            case .scroll, .sendShortcut, .sequence:
                actions.append(action)
            case .focusFirstInput:
                requestsFocus = true
            case .passNextKey, .beginHint, .showHelp, .escape, .enterInsert:
                break
            }
        }
        return PreparedCommand(
            decisionDelivery: decision.delivery,
            actuatorActions: actions,
            requestsFocus: requestsFocus
        )
    }

    public static func delivery(prepared: PreparedCommand, reports: [ActuatorReport]) -> KeyDelivery {
        guard prepared.decisionDelivery == .swallow else {
            return prepared.decisionDelivery
        }
        guard !prepared.actuatorActions.isEmpty,
              prepared.actuatorActions.allSatisfy(isScroll),
              reports.count == prepared.actuatorActions.count,
              reports.allSatisfy({ $0 == .passedThrough })
        else {
            return .swallow
        }
        return .passThrough
    }

    /// `nil` means the key must be given back. Hint and help are `nil` until a
    /// later task claims the overlay. A declined shortcut still counts as
    /// actuator work: the binding was handled by not posting it.
    public static func swallowReason(
        _ decision: EventDecision,
        actuated: Bool,
        focused: Bool,
        overlayClaimed: Bool
    ) -> SwallowReason? {
        _ = focused
        guard decision.delivery == .swallow else {
            return nil
        }
        if decision.actions.contains(where: isPassNext) {
            return .passNext
        }
        if decision.actions.contains(where: isFocus) {
            return .focus
        }
        if decision.modeEffects.contains(.blurFocus) {
            return .blur
        }
        if decision.mode == .paused {
            return .pause
        }
        if decision.overlay != nil {
            return overlayClaimed ? .overlay : nil
        }
        if actuated || decision.actions.contains(where: isActuatorAction) {
            return .actuator
        }
        if decision.actions.isEmpty {
            return .heldPrefix
        }
        return nil
    }

    private static func isScroll(_ action: Action) -> Bool {
        if case .scroll = action {
            return true
        }
        return false
    }

    private static func isPassNext(_ action: Action) -> Bool {
        if case .passNextKey = action {
            return true
        }
        return false
    }

    private static func isFocus(_ action: Action) -> Bool {
        if case .focusFirstInput = action {
            return true
        }
        return false
    }

    private static func isActuatorAction(_ action: Action) -> Bool {
        switch action {
        case .scroll, .sendShortcut, .sequence:
            return true
        case .beginHint, .showHelp, .focusFirstInput, .passNextKey, .escape, .enterInsert:
            return false
        }
    }
}

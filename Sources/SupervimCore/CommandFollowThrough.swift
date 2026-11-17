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

    private static func isScroll(_ action: Action) -> Bool {
        if case .scroll = action {
            return true
        }
        return false
    }
}

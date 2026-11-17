/// Click issued when a hint label is completed.
/// `plain` is `f`. `command` is `F` (Command-click, not a context menu).
public enum HintClick: Equatable, Sendable {
    case plain
    case command
}

public enum SupervimMode: Equatable, Sendable {
    case normal
    case insert
    case hint(HintClick)
    case paused
}

/// What an accessibility scan knows about the focused control.
/// Unknown must not be treated as editable or as a safe place to swallow keys.
public enum FocusEditability: Equatable, Sendable {
    case editable
    case notEditable
    case unknown
}

public enum ForegroundApp: Equatable, Sendable {
    case controlled
    case excluded
}

/// A key that later tasks have already classified.
/// This machine does not parse characters, sequences, or the pause hotkey.
public enum ModeKey: Equatable, Sendable {
    case escape
    case manualInsert
    case hint(HintClick)
    case other
}

public enum ModeInput: Equatable, Sendable {
    case key(ModeKey)
    case focus(FocusEditability)
    case foreground(ForegroundApp)
    /// Menu item and Ctrl+Option+V both send this. The chord is not parsed here.
    case togglePause
    case pause
    case resume
    case hintCompleted
    case hintCancelled
}

public enum ModeEffect: Equatable, Sendable {
    case passKeyThrough
    case swallowKey
    case blurFocus
    case beginHint(HintClick)
    case endHint
}

public struct ModeStep: Equatable, Sendable {
    public var mode: SupervimMode
    public var effects: [ModeEffect]

    public init(mode: SupervimMode, effects: [ModeEffect]) {
        self.mode = mode
        self.effects = effects
    }
}

/// Pure Normal / Insert / Hint / Paused transitions.
/// EventTap, AXScanner, and Overlay drive it later; nothing here touches the system.
public struct ModeMachine: Sendable {
    public private(set) var mode: SupervimMode

    private var focus: FocusEditability
    private var foreground: ForegroundApp
    private var insertCause: InsertCause
    private var resume: ResumeTarget

    private enum InsertCause: Sendable {
        case none
        case automatic
        case manual
    }

    private enum ResumeTarget: Sendable {
        case normal
        case insert(InsertCause)
    }

    public init() {
        mode = .normal
        focus = .unknown
        foreground = .controlled
        insertCause = .none
        resume = .normal
    }

    public mutating func handle(_ input: ModeInput) -> ModeStep {
        switch input {
        case .key(let key):
            return handleKey(key)
        case .focus(let editability):
            return handleFocus(editability)
        case .foreground(let app):
            return handleForeground(app)
        case .togglePause:
            return mode == .paused ? resumeFromPause() : pause()
        case .pause:
            return mode == .paused ? stay() : pause()
        case .resume:
            return mode == .paused ? resumeFromPause() : stay()
        case .hintCompleted, .hintCancelled:
            return endHintIfNeeded()
        }
    }

    private mutating func handleKey(_ key: ModeKey) -> ModeStep {
        if mode == .paused || foreground == .excluded || focus == .unknown {
            return ModeStep(mode: mode, effects: [.passKeyThrough])
        }
        if case .hint(let click) = mode {
            if key == .escape {
                mode = .normal
                insertCause = .none
                return ModeStep(mode: .normal, effects: [.swallowKey, .endHint])
            }
            return ModeStep(mode: .hint(click), effects: [.swallowKey])
        }
        if mode == .insert {
            if key == .escape {
                if focus != .notEditable {
                    focus = .unknown
                }
                mode = .normal
                insertCause = .none
                return ModeStep(mode: .normal, effects: [.swallowKey, .blurFocus])
            }
            return ModeStep(mode: .insert, effects: [.passKeyThrough])
        }
        switch key {
        case .escape, .other:
            return ModeStep(mode: .normal, effects: [.passKeyThrough])
        case .manualInsert:
            mode = .insert
            insertCause = .manual
            return ModeStep(mode: .insert, effects: [.swallowKey])
        case .hint(let click):
            mode = .hint(click)
            insertCause = .none
            return ModeStep(mode: .hint(click), effects: [.swallowKey, .beginHint(click)])
        }
    }

    private mutating func handleFocus(_ editability: FocusEditability) -> ModeStep {
        focus = editability
        if mode == .paused {
            updateResumeForFocus()
            return stay()
        }
        if foreground == .excluded {
            return stay()
        }
        switch editability {
        case .editable:
            return enterAutomaticInsert()
        case .notEditable:
            if case .hint = mode {
                return stay()
            }
            if mode == .insert, insertCause == .manual {
                return stay()
            }
            return becomeNormal()
        case .unknown:
            if case .hint = mode {
                return leaveHint()
            }
            return stay()
        }
    }

    private mutating func handleForeground(_ app: ForegroundApp) -> ModeStep {
        if foreground == app {
            return stay()
        }
        foreground = app
        if app == .excluded {
            if case .hint = mode {
                return leaveHint()
            }
            return stay()
        }
        if mode == .paused {
            return stay()
        }
        switch focus {
        case .editable:
            return enterAutomaticInsert()
        case .notEditable:
            if mode == .insert, insertCause == .manual {
                return stay()
            }
            return becomeNormal()
        case .unknown:
            return stay()
        }
    }

    private mutating func pause() -> ModeStep {
        var effects: [ModeEffect] = []
        if case .hint = mode {
            effects.append(.endHint)
            resume = .normal
        } else if mode == .insert {
            resume = .insert(insertCause)
        } else {
            resume = .normal
        }
        mode = .paused
        return ModeStep(mode: .paused, effects: effects)
    }

    private mutating func resumeFromPause() -> ModeStep {
        switch resume {
        case .normal:
            mode = .normal
            insertCause = .none
        case .insert(let cause):
            mode = .insert
            insertCause = cause
        }
        if foreground == .excluded {
            return stay()
        }
        switch focus {
        case .editable:
            mode = .insert
            insertCause = .automatic
        case .notEditable:
            if mode == .insert, insertCause == .manual {
                break
            }
            mode = .normal
            insertCause = .none
        case .unknown:
            break
        }
        return stay()
    }

    private mutating func updateResumeForFocus() {
        switch focus {
        case .editable:
            resume = .insert(.automatic)
        case .notEditable:
            if case .insert(.manual) = resume {
                return
            }
            resume = .normal
        case .unknown:
            return
        }
    }

    private mutating func endHintIfNeeded() -> ModeStep {
        guard case .hint = mode else {
            return stay()
        }
        return leaveHint()
    }

    private mutating func enterAutomaticInsert() -> ModeStep {
        var effects: [ModeEffect] = []
        if case .hint = mode {
            effects.append(.endHint)
        }
        mode = .insert
        insertCause = .automatic
        return ModeStep(mode: .insert, effects: effects)
    }

    private mutating func becomeNormal() -> ModeStep {
        mode = .normal
        insertCause = .none
        return stay()
    }

    private mutating func leaveHint() -> ModeStep {
        mode = .normal
        insertCause = .none
        return ModeStep(mode: .normal, effects: [.endHint])
    }

    private func stay() -> ModeStep {
        ModeStep(mode: mode, effects: [])
    }
}

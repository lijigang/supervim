/// Direction of a scroll action.
/// `up` and `edge` is the start of the vertical range. `down` and `edge` is the end.
public enum ScrollDirection: Equatable, Sendable {
    case left
    case down
    case up
    case right
}

/// How far a scroll action moves.
/// `points` is Vimium's `scrollStepSize` (60). `fractionOfPage` is a fraction of the
/// visible size; half a page is `1/2`, matching Vimium `scrollPageDown`. `edge` is an
/// absolute end of the range, not a relative distance.
public enum ScrollAmount: Equatable, Sendable {
    case points(Int)
    case fractionOfPage(numerator: Int, denominator: Int)
    case edge
}

/// One synthesized application shortcut.
/// `character` is the unshifted base key. Shift is a modifier, not a different glyph.
public struct KeyCombo: Equatable, Sendable {
    public var character: Character
    public var modifiers: KeyModifiers

    public init(_ character: Character, modifiers: KeyModifiers) {
        self.character = character
        self.modifiers = modifiers
    }
}

/// What a later actuator or event tap should do with one command token.
/// This value does not scroll, click, or post events.
public enum Action: Equatable, Sendable {
    case scroll(direction: ScrollDirection, amount: ScrollAmount)
    case sendShortcut(KeyCombo)
    /// Run each action in order. The copy-URL mapping is two shortcuts and nothing else.
    indirect case sequence([Action])
    case beginHint(HintClick)
    case showHelp
    case focusFirstInput
    case passNextKey
    case escape
    case enterInsert
}

/// What the event tap should do with one parser result.
/// `swallow` keeps a prefix (or a cancelled prefix) out of the focused app.
/// `passThrough` delivers the key. `perform` runs an action.
public enum CommandDisposition: Equatable, Sendable {
    case perform(Action)
    case passThrough
    case swallow
}

/// One row of the default map. Task 12 can read this for the help overlay.
public struct CommandBinding: Equatable, Sendable {
    public var keys: String
    public var command: KeyCommand
    public var action: Action
    public var summary: String
    /// True when the action is not Vimium's command, even if the keys match.
    public var deviatesFromVimium: Bool
    /// Spec application names. Nil means the action is not limited to those names.
    /// Bundle identifiers are not chosen here.
    public var promisedApplicationNames: [String]?

    public init(
        keys: String,
        command: KeyCommand,
        action: Action,
        summary: String,
        deviatesFromVimium: Bool,
        promisedApplicationNames: [String]?
    ) {
        self.keys = keys
        self.command = command
        self.action = action
        self.summary = summary
        self.deviatesFromVimium = deviatesFromVimium
        self.promisedApplicationNames = promisedApplicationNames
    }
}

/// Maps KeyParser command tokens to actions.
///
/// The map is a pure value. It does not know the current mode, and it does not
/// call ModeMachine. EventTap (task 7) decides whether to feed a key to the
/// parser. Actuator (task 11) performs the action.
public struct CommandMap: Sendable {
    /// Vimium's default `scrollStepSize`, in points. `j`/`k`/`h`/`l` all use it.
    public static let scrollStepPoints = 60
    /// Vimium `scrollPageDown` / `scrollPageUp` multiply the visible size by 1/2.
    public static let halfPageNumerator = 1
    public static let halfPageDenominator = 2

    public init() {}

    public func action(for command: KeyCommand) -> Action {
        switch command {
        case .scrollLeft:
            return .scroll(direction: .left, amount: .points(Self.scrollStepPoints))
        case .scrollDown:
            return .scroll(direction: .down, amount: .points(Self.scrollStepPoints))
        case .scrollUp:
            return .scroll(direction: .up, amount: .points(Self.scrollStepPoints))
        case .scrollRight:
            return .scroll(direction: .right, amount: .points(Self.scrollStepPoints))
        case .scrollHalfPageDown:
            return .scroll(direction: .down, amount: Self.halfPage)
        case .scrollHalfPageUp:
            return .scroll(direction: .up, amount: Self.halfPage)
        case .scrollToTop:
            return .scroll(direction: .up, amount: .edge)
        case .scrollToBottom:
            return .scroll(direction: .down, amount: .edge)
        case .focusFirstInput:
            return .focusFirstInput
        case .passNextKey:
            return .passNextKey
        case .historyBack:
            return .sendShortcut(KeyCombo("[", modifiers: .command))
        case .historyForward:
            return .sendShortcut(KeyCombo("]", modifiers: .command))
        case .previousTab:
            return .sendShortcut(KeyCombo("[", modifiers: [.command, .shift]))
        case .nextTab:
            return .sendShortcut(KeyCombo("]", modifiers: [.command, .shift]))
        case .close:
            return .sendShortcut(KeyCombo("w", modifiers: .command))
        case .create:
            return .sendShortcut(KeyCombo("t", modifiers: .command))
        case .reload:
            return .sendShortcut(KeyCombo("r", modifiers: .command))
        case .find:
            return .sendShortcut(KeyCombo("f", modifiers: .command))
        case .copyURL:
            return .sequence([
                .sendShortcut(KeyCombo("l", modifiers: .command)),
                .sendShortcut(KeyCombo("c", modifiers: .command)),
            ])
        case .hint(let click):
            return .beginHint(click)
        case .help:
            return .showHelp
        case .manualInsert:
            return .enterInsert
        case .escape:
            return .escape
        }
    }

    public func disposition(for result: KeyParseResult) -> CommandDisposition {
        switch result {
        case .command(let command):
            return .perform(action(for: command))
        case .passThrough:
            return .passThrough
        case .waitingForPrefix:
            return .swallow
        case .prefixCancelled:
            return .swallow
        }
    }

    public var bindings: [CommandBinding] {
        Self.rows.map { row in
            CommandBinding(
                keys: row.keys,
                command: row.command,
                action: action(for: row.command),
                summary: row.summary,
                deviatesFromVimium: row.deviatesFromVimium,
                promisedApplicationNames: row.promisedApplicationNames
            )
        }
    }

    private static var halfPage: ScrollAmount {
        .fractionOfPage(numerator: halfPageNumerator, denominator: halfPageDenominator)
    }

    private struct Row {
        var keys: String
        var command: KeyCommand
        var summary: String
        var deviatesFromVimium: Bool
        var promisedApplicationNames: [String]?
    }

    private static let rows: [Row] = [
        Row(
            keys: "j",
            command: .scrollDown,
            summary: "Scroll down",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "k",
            command: .scrollUp,
            summary: "Scroll up",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "h",
            command: .scrollLeft,
            summary: "Scroll left",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "l",
            command: .scrollRight,
            summary: "Scroll right",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "d",
            command: .scrollHalfPageDown,
            summary: "Scroll down half a page",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "u",
            command: .scrollHalfPageUp,
            summary: "Scroll up half a page",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "gg",
            command: .scrollToTop,
            summary: "Scroll to the top",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "G",
            command: .scrollToBottom,
            summary: "Scroll to the bottom",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "gi",
            command: .focusFirstInput,
            summary: "Focus the first input",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "Ctrl+]",
            command: .passNextKey,
            summary: "Pass the next key",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "H",
            command: .historyBack,
            summary: "History back",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "L",
            command: .historyForward,
            summary: "History forward",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "J",
            command: .previousTab,
            summary: "Previous tab",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "K",
            command: .nextTab,
            summary: "Next tab",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "x",
            command: .close,
            summary: "Close",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "t",
            command: .create,
            summary: "New",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "r",
            command: .reload,
            summary: "Reload",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "/",
            command: .find,
            summary: "Find with the app shortcut",
            deviatesFromVimium: true,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "yy",
            command: .copyURL,
            summary: "Copy URL",
            deviatesFromVimium: false,
            promisedApplicationNames: ["Safari", "Chromium"]
        ),
        Row(
            keys: "f",
            command: .hint(.plain),
            summary: "Hint",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "F",
            command: .hint(.command),
            summary: "Command-click hint",
            deviatesFromVimium: true,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "?",
            command: .help,
            summary: "Show help",
            deviatesFromVimium: true,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "i",
            command: .manualInsert,
            summary: "Insert",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
        Row(
            keys: "Esc",
            command: .escape,
            summary: "Escape",
            deviatesFromVimium: false,
            promisedApplicationNames: nil
        ),
    ]
}

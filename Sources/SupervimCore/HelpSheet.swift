import Foundation

public struct HelpEntry: Equatable, Sendable {
    public var keys: String
    public var summary: String
    public var actionText: String
    public var deviatesFromVimium: Bool
    public var promisedApplicationNames: [String]?
    public var line: String

    public init(
        keys: String,
        summary: String,
        actionText: String,
        deviatesFromVimium: Bool,
        promisedApplicationNames: [String]?,
        line: String
    ) {
        self.keys = keys
        self.summary = summary
        self.actionText = actionText
        self.deviatesFromVimium = deviatesFromVimium
        self.promisedApplicationNames = promisedApplicationNames
        self.line = line
    }
}

/// Rows the help overlay can draw. The text is generated from command bindings.
/// A row that differs from Vimium includes `differs from Vimium`.
/// `/` names the app shortcut, `Command+F`.
public struct HelpPage: Equatable, Sendable {
    public var entries: [HelpEntry]
    public var text: String

    public init(bindings: [CommandBinding]) {
        let entries = bindings.map(Self.entry(for:))
        self.entries = entries
        self.text = entries.map(\.line).joined(separator: "\n")
    }

    private static func entry(for binding: CommandBinding) -> HelpEntry {
        let actionText = HelpActionText.describe(binding.action)
        var parts = [binding.keys, binding.summary]
        if !actionText.isEmpty {
            parts.append(actionText)
        }
        if binding.deviatesFromVimium {
            parts.append("differs from Vimium")
        }
        if let names = binding.promisedApplicationNames, !names.isEmpty {
            parts.append(names.joined(separator: ", "))
        }
        return HelpEntry(
            keys: binding.keys,
            summary: binding.summary,
            actionText: actionText,
            deviatesFromVimium: binding.deviatesFromVimium,
            promisedApplicationNames: binding.promisedApplicationNames,
            line: parts.joined(separator: "  ")
        )
    }
}

public enum HelpSheetChange: Equatable, Sendable {
    case shown(HelpPage)
    case hidden
    case unchanged
}

/// Opens on `?` and closes on the next `?` or Esc.
/// Other keys leave the sheet as it is. This value does not draw or log the key.
public struct HelpSheet: Equatable, Sendable {
    public private(set) var isOpen: Bool
    private let page: HelpPage

    public init(map: CommandMap = CommandMap()) {
        self.init(bindings: map.bindings)
    }

    public init(bindings: [CommandBinding]) {
        self.page = HelpPage(bindings: bindings)
        self.isOpen = false
    }

    public mutating func show() -> HelpSheetChange {
        guard !isOpen else {
            return .unchanged
        }
        isOpen = true
        return .shown(page)
    }

    public mutating func hide() -> HelpSheetChange {
        guard isOpen else {
            return .unchanged
        }
        isOpen = false
        return .hidden
    }

    public mutating func toggle() -> HelpSheetChange {
        if isOpen {
            return hide()
        }
        return show()
    }

    public mutating func handle(_ event: KeyEvent) -> HelpSheetChange {
        if Self.isHelpKey(event) {
            return toggle()
        }
        if Self.isDismissKey(event) {
            return hide()
        }
        return .unchanged
    }

    public static func isHelpKey(_ event: KeyEvent) -> Bool {
        guard event.modifiers.intersection([.control, .option, .command]).isEmpty else {
            return false
        }
        if case .character("?") = event.identity {
            return true
        }
        return false
    }

    public static func isDismissKey(_ event: KeyEvent) -> Bool {
        guard event.modifiers.intersection([.control, .option, .command]).isEmpty else {
            return false
        }
        switch event.identity {
        case .escape:
            return true
        case .character("\u{1B}"):
            return true
        case .character, .unnamed:
            return false
        }
    }
}

enum HelpActionText {
    static func describe(_ action: Action) -> String {
        switch action {
        case .scroll(let direction, let amount):
            return scroll(direction, amount)
        case .sendShortcut(let combo):
            return shortcut(combo)
        case .sequence(let actions):
            return actions.map(describe).filter { !$0.isEmpty }.joined(separator: ", ")
        case .beginHint(let click):
            return click == .command ? "Command-click" : "hint"
        case .showHelp:
            return "show help"
        case .focusFirstInput:
            return "focus the first input"
        case .passNextKey:
            return "pass the next key"
        case .escape:
            return "escape"
        case .enterInsert:
            return "enter insert"
        }
    }

    private static func scroll(_ direction: ScrollDirection, _ amount: ScrollAmount) -> String {
        switch amount {
        case .points(let points):
            return "scroll \(directionName(direction)) \(points) points"
        case .fractionOfPage(let numerator, let denominator):
            if numerator == 1, denominator == 2 {
                return "scroll \(directionName(direction)) half a page"
            }
            return "scroll \(directionName(direction)) \(numerator)/\(denominator) of a page"
        case .edge:
            switch direction {
            case .up:
                return "scroll to the top"
            case .down:
                return "scroll to the bottom"
            case .left:
                return "scroll to the left edge"
            case .right:
                return "scroll to the right edge"
            }
        }
    }

    private static func directionName(_ direction: ScrollDirection) -> String {
        switch direction {
        case .left:
            return "left"
        case .down:
            return "down"
        case .up:
            return "up"
        case .right:
            return "right"
        }
    }

    private static func shortcut(_ combo: KeyCombo) -> String {
        var parts: [String] = []
        if combo.modifiers.contains(.command) {
            parts.append("Command")
        }
        if combo.modifiers.contains(.shift) {
            parts.append("Shift")
        }
        if combo.modifiers.contains(.option) {
            parts.append("Option")
        }
        if combo.modifiers.contains(.control) {
            parts.append("Control")
        }
        parts.append(display(combo.character))
        return parts.joined(separator: "+")
    }

    private static func display(_ character: Character) -> String {
        if character.isLetter {
            return String(character).uppercased()
        }
        return String(character)
    }
}

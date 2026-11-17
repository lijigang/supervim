/// Monotonic milliseconds supplied by the caller.
/// The parser does not read `Date` or the wall clock.
public protocol KeyTimeSource: Sendable {
    func nowMilliseconds() -> Int64
}

/// Clock the tests advance explicitly. A later event tap can supply another source.
public final class ManualKeyClock: KeyTimeSource, @unchecked Sendable {
    private var milliseconds: Int64

    public init(milliseconds: Int64 = 0) {
        self.milliseconds = milliseconds
    }

    public func nowMilliseconds() -> Int64 {
        milliseconds
    }

    public func advance(by milliseconds: Int64) {
        self.milliseconds += milliseconds
    }
}

public struct KeyModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let command = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
}

public enum KeyIdentity: Equatable, Sendable {
    case character(Character)
    case escape
    /// Arrows, function keys, and other keys that have no command character.
    case unnamed
}

public struct KeyEvent: Equatable, Sendable {
    public var identity: KeyIdentity
    public var modifiers: KeyModifiers

    public init(identity: KeyIdentity, modifiers: KeyModifiers = []) {
        self.identity = identity
        self.modifiers = modifiers
    }

    public init(_ character: Character, modifiers: KeyModifiers = []) {
        self.identity = .character(character)
        self.modifiers = modifiers
    }
}

/// Command token for a completed binding.
/// Names that overlap ModeMachine use the same words: `manualInsert`, `hint`, `escape`.
/// This parser does not know the current mode and does not run the command.
public enum KeyCommand: Equatable, Sendable {
    case escape
    case manualInsert
    case hint(HintClick)

    case scrollLeft
    case scrollDown
    case scrollUp
    case scrollRight
    case scrollHalfPageDown
    case scrollHalfPageUp
    case scrollToTop
    case scrollToBottom

    case historyBack
    case historyForward
    case previousTab
    case nextTab
    case close
    case create
    case reload
    case find
    case copyURL
    case focusFirstInput
    case help

    case passNextKey
}

public enum KeyParseResult: Equatable, Sendable {
    case command(KeyCommand)
    /// Not a command. A later layer should let the focused app receive the key.
    case passThrough
    /// A prefix is held. That key must not be delivered, and it is not a command.
    case waitingForPrefix
    /// A held prefix was dropped. It is not a command and is not passed through.
    case prefixCancelled
}

public struct KeyParseStep: Equatable, Sendable {
    public var results: [KeyParseResult]

    public init(results: [KeyParseResult]) {
        self.results = results
    }
}

/// Maps a key stream to command tokens.
///
/// The parser is mode-agnostic. ModeMachine and a later event tap decide whether
/// to feed a key in. Ctrl+Option+V is not a binding here; pause arrives as
/// `togglePause` from the menu or hotkey.
///
/// `g` and `y` wait for one more key. `gg`, `gi`, and `yy` are the only
/// completions. A second key that does not complete the pair cancels the prefix
/// and is parsed on its own. A prefix that times out is swallowed: `g` alone is
/// not a command and is not replayed.
public struct KeyParser<Clock: KeyTimeSource>: Sendable {
    public let prefixTimeoutMilliseconds: Int64

    private let clock: Clock
    private var pending: PendingPrefix?
    private var passNextArmed: Bool

    public init(clock: Clock, prefixTimeoutMilliseconds: Int64 = 1000) {
        self.clock = clock
        self.prefixTimeoutMilliseconds = prefixTimeoutMilliseconds
        pending = nil
        passNextArmed = false
    }

    public mutating func handle(_ event: KeyEvent) -> KeyParseStep {
        if passNextArmed {
            passNextArmed = false
            return KeyParseStep(results: [.passThrough])
        }

        var cancelled = false
        if let pending, isExpired(pending) {
            self.pending = nil
            cancelled = true
        }

        if let pending {
            if let command = completion(pending.kind, event) {
                self.pending = nil
                return step(cancelled: cancelled, fresh: [.command(command)])
            }
            self.pending = nil
            cancelled = true
        }

        return step(cancelled: cancelled, fresh: freshResults(for: event))
    }

    /// Drops a prefix once the timeout has elapsed and no second key arrived.
    /// Returns nil when nothing was waiting or the deadline has not been reached.
    public mutating func expirePendingPrefix() -> KeyParseResult? {
        guard let pending, isExpired(pending) else {
            return nil
        }
        self.pending = nil
        return .prefixCancelled
    }

    /// Drops a held prefix and a pass-next arm without replaying either.
    /// The event tap calls this when it stops feeding keys to the parser.
    /// Returns `.prefixCancelled` when a prefix was waiting.
    public mutating func suspendParsing() -> KeyParseResult? {
        let cancelled: KeyParseResult? = pending == nil ? nil : .prefixCancelled
        pending = nil
        passNextArmed = false
        return cancelled
    }

    private func isExpired(_ pending: PendingPrefix) -> Bool {
        clock.nowMilliseconds() - pending.startedAt >= prefixTimeoutMilliseconds
    }

    private func step(cancelled: Bool, fresh: [KeyParseResult]) -> KeyParseStep {
        if cancelled {
            return KeyParseStep(results: [.prefixCancelled] + fresh)
        }
        return KeyParseStep(results: fresh)
    }

    private mutating func freshResults(for event: KeyEvent) -> [KeyParseResult] {
        if isEscape(event) {
            return [.command(.escape)]
        }
        if isPassNextChord(event) {
            passNextArmed = true
            return [.command(.passNextKey)]
        }
        guard allowsPlainBinding(event.modifiers) else {
            return [.passThrough]
        }
        guard case .character(let character) = event.identity else {
            return [.passThrough]
        }
        if let command = singleKeyCommand(character) {
            return [.command(command)]
        }
        if let kind = prefixKind(character) {
            pending = PendingPrefix(kind: kind, startedAt: clock.nowMilliseconds())
            return [.waitingForPrefix]
        }
        return [.passThrough]
    }

    private func allowsPlainBinding(_ modifiers: KeyModifiers) -> Bool {
        modifiers.intersection([.control, .option, .command]).isEmpty
    }

    private func isEscape(_ event: KeyEvent) -> Bool {
        guard allowsPlainBinding(event.modifiers) else {
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

    private func isPassNextChord(_ event: KeyEvent) -> Bool {
        guard event.modifiers.intersection([.option, .command, .shift]).isEmpty else {
            return false
        }
        switch event.identity {
        case .character("]"):
            return event.modifiers == .control
        case .character("\u{1D}"):
            return event.modifiers.subtracting(.control).isEmpty
        case .escape, .unnamed, .character:
            return false
        }
    }

    private func singleKeyCommand(_ character: Character) -> KeyCommand? {
        switch character {
        case "f": return .hint(.plain)
        case "F": return .hint(.command)
        case "i": return .manualInsert
        case "j": return .scrollDown
        case "k": return .scrollUp
        case "h": return .scrollLeft
        case "l": return .scrollRight
        case "d": return .scrollHalfPageDown
        case "u": return .scrollHalfPageUp
        case "G": return .scrollToBottom
        case "H": return .historyBack
        case "L": return .historyForward
        case "J": return .previousTab
        case "K": return .nextTab
        case "x": return .close
        case "t": return .create
        case "r": return .reload
        case "/": return .find
        case "?": return .help
        default: return nil
        }
    }

    private func prefixKind(_ character: Character) -> PrefixKind? {
        switch character {
        case "g": return .g
        case "y": return .y
        default: return nil
        }
    }

    /// A completing key must be the plain character. Modified keys fail the pair
    /// and are parsed again from the root, so Ctrl+] during `g` still arms pass-next.
    private func completion(_ kind: PrefixKind, _ event: KeyEvent) -> KeyCommand? {
        guard allowsPlainBinding(event.modifiers) else {
            return nil
        }
        guard case .character(let character) = event.identity else {
            return nil
        }
        switch (kind, character) {
        case (.g, "g"): return .scrollToTop
        case (.g, "i"): return .focusFirstInput
        case (.y, "y"): return .copyURL
        default: return nil
        }
    }
}

extension KeyParser {
    private struct PendingPrefix: Sendable {
        var kind: PrefixKind
        var startedAt: Int64
    }

    private enum PrefixKind: Sendable {
        case g
        case y
    }
}

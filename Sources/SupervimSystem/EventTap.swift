import Foundation
import SupervimCore

public protocol KeyDeciding: AnyObject, Sendable {
    func handleKeyDown(_ event: KeyEvent, cache: CachedFocus) -> EventDecision
    func updateCache(_ cache: CachedFocus) -> EventDecision
    var mode: SupervimMode { get }
}

extension EventInterpreter: KeyDeciding {}

public protocol FocusCacheReading: AnyObject, Sendable {
    func currentFocus() -> CachedFocus
}

/// Accessibility walk. The key hook must not call this.
/// `refreshFocus()` is the out-of-hook seam task 8 can fill in.
public protocol AccessibilityScanning: AnyObject, Sendable {
    func scanFocus() -> CachedFocus
}

public protocol EventTapInstalling: AnyObject, Sendable {
    func install() throws
    func uninstall()
}

public enum SystemEventKind: Equatable, Sendable {
    case keyDown
    case keyUp
    case flagsChanged
    case other
}

/// Raw bits copied from CGEventFlags. The macOS test checks them against that type.
public enum SystemModifierMask {
    public static let shift: UInt64 = 0x00020000
    public static let control: UInt64 = 0x00040000
    public static let option: UInt64 = 0x00080000
    public static let command: UInt64 = 0x00100000
}

public struct SystemKeyRecord: Equatable, Sendable {
    public var kind: SystemEventKind
    public var keyCode: UInt16
    public var modifierFlags: UInt64
    public var unicode: String
    public var sourceUserData: Int64

    public init(
        kind: SystemEventKind,
        keyCode: UInt16,
        modifierFlags: UInt64,
        unicode: String,
        sourceUserData: Int64 = 0
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.unicode = unicode
        self.sourceUserData = sourceUserData
    }
}

public struct SystemKeyOutcome: Equatable, Sendable {
    public var delivery: KeyDelivery
    public var decision: EventDecision?

    public init(delivery: KeyDelivery, decision: EventDecision?) {
        self.delivery = delivery
        self.decision = decision
    }
}

public enum SystemKeyTranslation {
    /// US ANSI virtual key to the unshifted character.
    /// Used when Control, Option, or Command would replace the typed glyph.
    /// Plain keys keep the unicode string so the active layout still works.
    private static let unshifted: [UInt16: Character] = [
        0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g",
        0x06: "z", 0x07: "x", 0x08: "c", 0x09: "v", 0x0B: "b", 0x0C: "q",
        0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y", 0x11: "t",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
        0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
        0x1E: "]", 0x1F: "o", 0x20: "u", 0x21: "[", 0x22: "i", 0x23: "p",
        0x25: "l", 0x26: "j", 0x27: "'", 0x28: "k", 0x29: ";", 0x2A: "\\",
        0x2B: ",", 0x2C: "/", 0x2D: "n", 0x2E: "m", 0x2F: ".",
        0x31: " ", 0x32: "`",
    ]

    private static let escapeKeyCode: UInt16 = 0x35

    public static func virtualKeyCode(forUnshifted character: Character) -> UInt16? {
        for (code, glyph) in unshifted where glyph == character {
            return code
        }
        return nil
    }

    public static func keyEvent(from record: SystemKeyRecord) -> KeyEvent? {
        guard record.kind == .keyDown else {
            return nil
        }
        let modifiers = modifiers(from: record.modifierFlags)
        if record.keyCode == escapeKeyCode {
            return KeyEvent(identity: .escape, modifiers: modifiers)
        }
        if distortsUnicode(modifiers) {
            if let character = unshifted[record.keyCode] {
                return KeyEvent(character, modifiers: modifiers)
            }
            if let character = plainCharacter(record.unicode) {
                return KeyEvent(character, modifiers: modifiers)
            }
            return KeyEvent(identity: .unnamed, modifiers: modifiers)
        }
        if record.unicode == "\u{1B}" {
            return KeyEvent(identity: .escape, modifiers: modifiers)
        }
        if let character = plainCharacter(record.unicode) {
            return KeyEvent(character, modifiers: modifiers)
        }
        if let character = unshifted[record.keyCode] {
            return KeyEvent(character, modifiers: modifiers)
        }
        return KeyEvent(identity: .unnamed, modifiers: modifiers)
    }

    private static func modifiers(from flags: UInt64) -> KeyModifiers {
        var modifiers = KeyModifiers()
        if flags & SystemModifierMask.shift != 0 {
            modifiers.insert(.shift)
        }
        if flags & SystemModifierMask.control != 0 {
            modifiers.insert(.control)
        }
        if flags & SystemModifierMask.option != 0 {
            modifiers.insert(.option)
        }
        if flags & SystemModifierMask.command != 0 {
            modifiers.insert(.command)
        }
        return modifiers
    }

    private static func distortsUnicode(_ modifiers: KeyModifiers) -> Bool {
        !modifiers.intersection([.control, .option, .command]).isEmpty
    }

    private static func plainCharacter(_ unicode: String) -> Character? {
        guard unicode.count == 1, let character = unicode.first else {
            return nil
        }
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return nil
        }
        if scalar.value < 0x20 || scalar.value == 0x7F {
            return nil
        }
        return character
    }
}

public final class SystemKeyClock: KeyTimeSource, @unchecked Sendable {
    public init() {}

    public func nowMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }
}

/// Reads the cached focus, then asks the decider. Does not walk accessibility.
public final class EventTapWiring: @unchecked Sendable {
    private let decider: any KeyDeciding
    private let cache: any FocusCacheReading
    private let scanner: any AccessibilityScanning
    private let lock = NSLock()

    public init(
        decider: any KeyDeciding,
        cache: any FocusCacheReading,
        scanner: any AccessibilityScanning
    ) {
        self.decider = decider
        self.cache = cache
        self.scanner = scanner
    }

    public func handleKeyDown(_ event: KeyEvent) -> EventDecision {
        lock.lock()
        defer { lock.unlock() }
        return decide(event)
    }

    public func handleSystemRecord(_ record: SystemKeyRecord) -> SystemKeyOutcome {
        lock.lock()
        defer { lock.unlock() }
        if record.sourceUserData == SynthesizedEventMark.userData {
            return SystemKeyOutcome(delivery: .passThrough, decision: nil)
        }
        guard let event = SystemKeyTranslation.keyEvent(from: record) else {
            return SystemKeyOutcome(delivery: .passThrough, decision: nil)
        }
        let decision = decide(event)
        return SystemKeyOutcome(delivery: decision.delivery, decision: decision)
    }

    public func publishCachedFocus() -> EventDecision {
        lock.lock()
        defer { lock.unlock() }
        return decider.updateCache(cache.currentFocus())
    }

    /// Outside the key hook. Task 8 supplies the real walk.
    public func refreshFocus() -> CachedFocus {
        scanner.scanFocus()
    }

    private func decide(_ event: KeyEvent) -> EventDecision {
        decider.handleKeyDown(event, cache: cache.currentFocus())
    }
}

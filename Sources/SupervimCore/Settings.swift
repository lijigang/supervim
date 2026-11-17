import Foundation

/// Global pause chord stored in settings.
///
/// The character is the unshifted base key, matching `KeyCombo`. Shift is a modifier,
/// not a different letter. The default is Ctrl+Option+V, which is `v` plus control and option.
public struct PauseShortcut: Equatable, Sendable {
    public var key: Character
    public var modifiers: KeyModifiers

    public init(key: Character, modifiers: KeyModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let `default` = PauseShortcut(key: "v", modifiers: [.control, .option])

    /// Exact match. An extra or missing modifier does not match.
    public func matches(key: Character, modifiers: KeyModifiers) -> Bool {
        self.key == key && self.modifiers == modifiers
    }

    /// Exact match against one key event. Escape and unnamed keys do not match.
    public func matches(_ event: KeyEvent) -> Bool {
        guard case .character(let character) = event.identity else {
            return false
        }
        return matches(key: character, modifiers: event.modifiers)
    }
}

/// Persisted user settings.
///
/// The value does not read or write the disk, register a login item, or record keystrokes.
/// `launchAtLogin` is the saved preference. `LoginItemRegistration` applies that flag.
/// `isPaused` is the saved pause flag. Task 13 feeds it to ModeMachine.
/// `keySequenceTimeoutMilliseconds` is the prefix timeout task 7 should pass to KeyParser.
/// The default is 1000, the same value KeyParser uses when no setting is supplied.
public struct Settings: Equatable, Sendable {
    public static let schemaVersion = 1

    /// Spec names Terminal, iTerm, and Emacs. The spec does not approve bundle identifiers.
    /// These three are an unapproved choice:
    /// Terminal `com.apple.Terminal`, iTerm2 `com.googlecode.iterm2`, GNU Emacs `org.gnu.Emacs`.
    public static let defaultExcludedBundleIdentifiers = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "org.gnu.Emacs",
    ]

    public static let defaultKeySequenceTimeoutMilliseconds = 1000
    public static let minimumKeySequenceTimeoutMilliseconds = 1
    public static let maximumKeySequenceTimeoutMilliseconds = 60_000

    /// Apps whose accessibility tree is not enough for `f`. Vision runs for
    /// these bundle ids even when the tree has some hits. An empty saved list
    /// disables that extra pass. A missing key keeps this default.
    /// WeChat for Mac is `com.tencent.xinWeChat`. That choice is not in the
    /// original spec; the accessibility tree of that app is empty.
    public static let defaultVisionBundleIdentifiers = [
        "com.tencent.xinWeChat",
    ]

    public var isPaused: Bool
    public var excludedBundleIdentifiers: [String]
    public var launchAtLogin: Bool
    public var keySequenceTimeoutMilliseconds: Int
    public var pauseShortcut: PauseShortcut
    public var visionBundleIdentifiers: [String]

    public init(
        isPaused: Bool,
        excludedBundleIdentifiers: [String],
        launchAtLogin: Bool,
        keySequenceTimeoutMilliseconds: Int,
        pauseShortcut: PauseShortcut,
        visionBundleIdentifiers: [String] = Settings.defaultVisionBundleIdentifiers
    ) {
        self.isPaused = isPaused
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
        self.launchAtLogin = launchAtLogin
        self.keySequenceTimeoutMilliseconds = keySequenceTimeoutMilliseconds
        self.pauseShortcut = pauseShortcut
        self.visionBundleIdentifiers = visionBundleIdentifiers
    }

    public static let defaults = Settings(
        isPaused: false,
        excludedBundleIdentifiers: defaultExcludedBundleIdentifiers,
        launchAtLogin: false,
        keySequenceTimeoutMilliseconds: defaultKeySequenceTimeoutMilliseconds,
        pauseShortcut: .default,
        visionBundleIdentifiers: defaultVisionBundleIdentifiers
    )

    /// Whether Supervim must leave this frontmost app alone.
    ///
    /// Comparison is case-sensitive after trimming whitespace on both sides.
    /// A blank identifier is excluded: the frontmost app could not be named, and
    /// dropping its keys is worse than missing a shortcut. Callers with a missing
    /// identifier should pass an empty string.
    public func isExcluded(bundleIdentifier: String) -> Bool {
        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        return excludedBundleIdentifiers.contains { stored in
            stored.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }
    }
}

public enum SettingsError: Error, Equatable, Sendable {
    case unreadableDocument
    case notADictionary
    case unsupportedSchemaVersion(Int)
    case invalidSchemaVersion
    case unknownField(String)
    case invalidBoolean(String)
    case invalidInteger(String)
    case invalidStringArray(String)
    case invalidShortcut
    case blankBundleIdentifier
    case invalidBundleIdentifier(String)
    case duplicateBundleIdentifier(String)
    case unrecognizedExcludedApplication(String)
    case timeoutOutOfRange(Int)
    case invalidPauseKey
    case pauseShortcutNeedsANonShiftModifier
    case unknownPauseModifier(String)
    case duplicatePauseModifier(String)
}

/// Bytes of one property-list settings document. Nil means nothing has been saved.
public protocol SettingsStore: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

/// Store that keeps the document in memory. Tests and later previews use it.
/// It does not open the preference database.
public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private var data: Data?

    public init(data: Data? = nil) {
        self.data = data
    }

    public func read() throws -> Data? {
        data
    }

    public func write(_ data: Data) throws {
        self.data = data
    }
}

/// Loads and saves settings through a store.
///
/// A missing document stays missing and returns defaults.
/// A version-1 document is not rewritten when a key is absent; the default is applied in memory.
/// A legacy or version-0 document is rewritten as version 1 after a successful load.
/// A future schema version is rejected and left on disk.
public struct SettingsRepository: Sendable {
    private let store: any SettingsStore

    public init(store: any SettingsStore) {
        self.store = store
    }

    public func load() throws -> Settings {
        let decoded = try SettingsCodec.decode(try store.read())
        if decoded.persistsMigration {
            try store.write(try SettingsCodec.encode(decoded.settings))
        }
        return decoded.settings
    }

    public func save(_ settings: Settings) throws {
        try store.write(try SettingsCodec.encode(settings))
    }
}

private struct DecodedSettings {
    var settings: Settings
    var persistsMigration: Bool
}

private enum SettingsCodec {
    private static let versionOneKeys: Set<String> = [
        "schemaVersion",
        "paused",
        "excludedBundleIdentifiers",
        "launchAtLogin",
        "keySequenceTimeoutMilliseconds",
        "pauseShortcut",
        "visionBundleIdentifiers",
    ]

    private static let legacyKeys: Set<String> = [
        "schemaVersion",
        "paused",
        "excludedApplications",
        "launchAtLogin",
        "keySequenceTimeoutMilliseconds",
        "pauseHotkey",
    ]

    /// Application names the spec used before bundle identifiers existed.
    /// Only the legacy document accepts these words. Version 1 does not.
    private static let legacyApplicationNames = [
        "terminal": "com.apple.Terminal",
        "iterm": "com.googlecode.iterm2",
        "iterm2": "com.googlecode.iterm2",
        "emacs": "org.gnu.Emacs",
    ]

    static func decode(_ data: Data?) throws -> DecodedSettings {
        guard let data else {
            return DecodedSettings(settings: .defaults, persistsMigration: false)
        }
        let object = try propertyList(data)
        guard let document = dictionary(from: object) else {
            throw SettingsError.notADictionary
        }

        let version = try schemaVersion(in: document)
        if version == Settings.schemaVersion {
            return DecodedSettings(
                settings: try decodeVersionOne(document),
                persistsMigration: false
            )
        }
        return DecodedSettings(
            settings: try decodeLegacy(document),
            persistsMigration: true
        )
    }

    static func encode(_ settings: Settings) throws -> Data {
        let normalized = try normalized(settings)
        let shortcut: [String: Any] = [
            "key": String(normalized.pauseShortcut.key),
            "modifiers": modifierNames(normalized.pauseShortcut.modifiers),
        ]
        let document: [String: Any] = [
            "schemaVersion": Settings.schemaVersion,
            "paused": normalized.isPaused,
            "excludedBundleIdentifiers": normalized.excludedBundleIdentifiers,
            "launchAtLogin": normalized.launchAtLogin,
            "keySequenceTimeoutMilliseconds": normalized.keySequenceTimeoutMilliseconds,
            "pauseShortcut": shortcut,
            "visionBundleIdentifiers": normalized.visionBundleIdentifiers,
        ]
        return try PropertyListSerialization.data(fromPropertyList: document, format: .xml, options: 0)
    }

    private static func decodeVersionOne(_ document: [String: Any]) throws -> Settings {
        try rejectUnknownFields(in: document, allowed: versionOneKeys)
        return Settings(
            isPaused: try bool(in: document, key: "paused", default: false),
            excludedBundleIdentifiers: try bundleIdentifiers(in: document, legacyNames: false),
            launchAtLogin: try bool(in: document, key: "launchAtLogin", default: false),
            keySequenceTimeoutMilliseconds: try timeout(in: document),
            pauseShortcut: try versionOneShortcut(in: document),
            visionBundleIdentifiers: try visionBundles(in: document)
        )
    }

    private static func decodeLegacy(_ document: [String: Any]) throws -> Settings {
        try rejectUnknownFields(in: document, allowed: legacyKeys)
        return Settings(
            isPaused: try bool(in: document, key: "paused", default: false),
            excludedBundleIdentifiers: try bundleIdentifiers(in: document, legacyNames: true),
            launchAtLogin: try bool(in: document, key: "launchAtLogin", default: false),
            keySequenceTimeoutMilliseconds: try timeout(in: document),
            pauseShortcut: try legacyShortcut(in: document),
            visionBundleIdentifiers: Settings.defaultVisionBundleIdentifiers
        )
    }

    private static func normalized(_ settings: Settings) throws -> Settings {
        Settings(
            isPaused: settings.isPaused,
            excludedBundleIdentifiers: try canonicalBundleIdentifiers(
                settings.excludedBundleIdentifiers,
                legacyNames: false
            ),
            launchAtLogin: settings.launchAtLogin,
            keySequenceTimeoutMilliseconds: try validatedTimeout(settings.keySequenceTimeoutMilliseconds),
            pauseShortcut: try validatedShortcut(settings.pauseShortcut),
            visionBundleIdentifiers: try canonicalBundleIdentifiers(
                settings.visionBundleIdentifiers,
                legacyNames: false
            )
        )
    }

    private static func schemaVersion(in document: [String: Any]) throws -> Int? {
        guard document.keys.contains("schemaVersion") else {
            return nil
        }
        guard let version = strictInt(document["schemaVersion"] as Any) else {
            throw SettingsError.invalidSchemaVersion
        }
        if version != 0 && version != Settings.schemaVersion {
            throw SettingsError.unsupportedSchemaVersion(version)
        }
        return version
    }

    private static func rejectUnknownFields(in document: [String: Any], allowed: Set<String>) throws {
        let unknown = document.keys.filter { !allowed.contains($0) }.sorted()
        if let field = unknown.first {
            throw SettingsError.unknownField(field)
        }
    }

    private static func bool(in document: [String: Any], key: String, default defaultValue: Bool) throws -> Bool {
        guard let raw = document[key] else {
            return defaultValue
        }
        guard let value = strictBool(raw) else {
            throw SettingsError.invalidBoolean(key)
        }
        return value
    }

    private static func timeout(in document: [String: Any]) throws -> Int {
        guard let raw = document["keySequenceTimeoutMilliseconds"] else {
            return Settings.defaultKeySequenceTimeoutMilliseconds
        }
        guard let value = strictInt(raw) else {
            throw SettingsError.invalidInteger("keySequenceTimeoutMilliseconds")
        }
        return try validatedTimeout(value)
    }

    private static func validatedTimeout(_ value: Int) throws -> Int {
        if value < Settings.minimumKeySequenceTimeoutMilliseconds
            || value > Settings.maximumKeySequenceTimeoutMilliseconds {
            throw SettingsError.timeoutOutOfRange(value)
        }
        return value
    }

    private static func visionBundles(in document: [String: Any]) throws -> [String] {
        guard let raw = document["visionBundleIdentifiers"] else {
            return Settings.defaultVisionBundleIdentifiers
        }
        guard let items = stringArray(from: raw) else {
            throw SettingsError.invalidStringArray("visionBundleIdentifiers")
        }
        return try canonicalBundleIdentifiers(items, legacyNames: false)
    }

    private static func bundleIdentifiers(in document: [String: Any], legacyNames: Bool) throws -> [String] {
        let key = legacyNames ? "excludedApplications" : "excludedBundleIdentifiers"
        guard let raw = document[key] else {
            return Settings.defaultExcludedBundleIdentifiers
        }
        guard let items = stringArray(from: raw) else {
            throw SettingsError.invalidStringArray(key)
        }
        return try canonicalBundleIdentifiers(items, legacyNames: legacyNames)
    }

    private static func canonicalBundleIdentifiers(_ items: [String], legacyNames: Bool) throws -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for raw in items {
            let identifier = try canonicalBundleIdentifier(raw, legacyNames: legacyNames)
            if seen.contains(identifier) {
                if legacyNames {
                    continue
                }
                throw SettingsError.duplicateBundleIdentifier(identifier)
            }
            seen.insert(identifier)
            result.append(identifier)
        }
        return result
    }

    private static func canonicalBundleIdentifier(_ raw: String, legacyNames: Bool) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw SettingsError.blankBundleIdentifier
        }
        if legacyNames && !trimmed.contains(".") {
            guard let mapped = legacyApplicationNames[trimmed.lowercased()] else {
                throw SettingsError.unrecognizedExcludedApplication(trimmed)
            }
            return mapped
        }
        guard isValidBundleIdentifier(trimmed) else {
            throw SettingsError.invalidBundleIdentifier(trimmed)
        }
        return trimmed
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            return false
        }
        for part in parts {
            guard isValidBundleComponent(part) else {
                return false
            }
        }
        return true
    }

    private static func isValidBundleComponent(_ part: Substring) -> Bool {
        let scalars = Array(part.unicodeScalars)
        guard let first = scalars.first, let last = scalars.last else {
            return false
        }
        guard isASCIIAlphanumeric(first), isASCIIAlphanumeric(last) else {
            return false
        }
        for scalar in scalars {
            if isASCIIAlphanumeric(scalar) || scalar == "-" {
                continue
            }
            return false
        }
        return true
    }

    private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        (scalar >= "a" && scalar <= "z")
            || (scalar >= "A" && scalar <= "Z")
            || (scalar >= "0" && scalar <= "9")
    }

    private static func versionOneShortcut(in document: [String: Any]) throws -> PauseShortcut {
        guard let raw = document["pauseShortcut"] else {
            return .default
        }
        guard let shortcut = dictionary(from: raw),
              let key = shortcut["key"] as? String,
              let modifiersRaw = shortcut["modifiers"],
              let modifiers = stringArray(from: modifiersRaw) else {
            throw SettingsError.invalidShortcut
        }
        return try makeShortcut(key: key, modifierNames: modifiers)
    }

    private static func legacyShortcut(in document: [String: Any]) throws -> PauseShortcut {
        guard let raw = document["pauseHotkey"] else {
            return .default
        }
        guard let text = raw as? String else {
            throw SettingsError.invalidShortcut
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized == "ctrl+option+v" || normalized == "control+option+v" else {
            throw SettingsError.invalidShortcut
        }
        return .default
    }

    private static func validatedShortcut(_ shortcut: PauseShortcut) throws -> PauseShortcut {
        let scalars = Array(String(shortcut.key).unicodeScalars)
        guard scalars.count == 1, let scalar = scalars.first, isAcceptablePauseKey(scalar) else {
            throw SettingsError.invalidPauseKey
        }
        try requireNonShiftModifier(shortcut.modifiers)
        return shortcut
    }

    private static func makeShortcut(key: String, modifierNames: [String]) throws -> PauseShortcut {
        let scalars = Array(key.unicodeScalars)
        guard scalars.count == 1, let scalar = scalars.first, isAcceptablePauseKey(scalar) else {
            throw SettingsError.invalidPauseKey
        }
        let modifiers = try modifiers(from: modifierNames)
        return PauseShortcut(key: Character(scalar), modifiers: modifiers)
    }

    private static func isAcceptablePauseKey(_ scalar: Unicode.Scalar) -> Bool {
        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return false
        }
        if CharacterSet.controlCharacters.contains(scalar) {
            return false
        }
        return true
    }

    private static func modifiers(from names: [String]) throws -> KeyModifiers {
        var modifiers = KeyModifiers()
        var seen = Set<String>()
        for name in names {
            if seen.contains(name) {
                throw SettingsError.duplicatePauseModifier(name)
            }
            seen.insert(name)
            switch name {
            case "control":
                modifiers.insert(.control)
            case "option":
                modifiers.insert(.option)
            case "command":
                modifiers.insert(.command)
            case "shift":
                modifiers.insert(.shift)
            default:
                throw SettingsError.unknownPauseModifier(name)
            }
        }
        try requireNonShiftModifier(modifiers)
        return modifiers
    }

    private static func requireNonShiftModifier(_ modifiers: KeyModifiers) throws {
        let binding: KeyModifiers = [.control, .option, .command]
        if modifiers.intersection(binding).isEmpty {
            throw SettingsError.pauseShortcutNeedsANonShiftModifier
        }
    }

    private static func modifierNames(_ modifiers: KeyModifiers) -> [String] {
        var names: [String] = []
        if modifiers.contains(.control) {
            names.append("control")
        }
        if modifiers.contains(.option) {
            names.append("option")
        }
        if modifiers.contains(.command) {
            names.append("command")
        }
        if modifiers.contains(.shift) {
            names.append("shift")
        }
        return names
    }

    private static func propertyList(_ data: Data) throws -> Any {
        do {
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw SettingsError.unreadableDocument
        }
    }

    private static func dictionary(from value: Any) -> [String: Any]? {
        guard let dictionary = value as? NSDictionary else {
            return nil
        }
        var result: [String: Any] = [:]
        for case let (key as String, nested) in dictionary {
            result[key] = nested
        }
        return result
    }

    private static func stringArray(from value: Any) -> [String]? {
        value as? [String]
    }

    /// Property-list booleans are numeric on both Linux and Apple, and so are integers.
    /// The object type distinguishes `<true/>` from `<integer>1</integer>`.
    private static func strictBool(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber else {
            return nil
        }
        switch String(cString: number.objCType) {
        case "c", "C", "B":
            return number.boolValue
        default:
            return nil
        }
    }

    private static func strictInt(_ value: Any) -> Int? {
        guard let number = value as? NSNumber else {
            return nil
        }
        switch String(cString: number.objCType) {
        case "c", "C", "B", "d", "f":
            return nil
        default:
            return number.intValue
        }
    }
}

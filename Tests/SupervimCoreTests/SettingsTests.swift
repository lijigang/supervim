import XCTest
@testable import SupervimCore

/// Persisted settings: defaults, validation, legacy migration, and the exclusion helper.
/// The in-memory store stands in for UserDefaults. Nothing here touches a login item.
final class SettingsTests: XCTestCase {
    func testDefaultsMatchTheApprovedInitialState() {
        let settings = Settings.defaults
        XCTAssertEqual(Settings.schemaVersion, 1)
        XCTAssertFalse(settings.isPaused)
        XCTAssertEqual(settings.excludedBundleIdentifiers, [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "org.gnu.Emacs",
        ])
        XCTAssertEqual(
            Settings.defaultExcludedBundleIdentifiers,
            settings.excludedBundleIdentifiers
        )
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.keySequenceTimeoutMilliseconds, 1000)
        XCTAssertEqual(Settings.minimumKeySequenceTimeoutMilliseconds, 1)
        XCTAssertEqual(Settings.maximumKeySequenceTimeoutMilliseconds, 60_000)
        XCTAssertEqual(settings.pauseShortcut, .default)
    }

    func testDefaultTimeoutMatchesTheKeyParser() {
        let parser = KeyParser(clock: ManualKeyClock())
        XCTAssertEqual(
            Int64(Settings.defaults.keySequenceTimeoutMilliseconds),
            parser.prefixTimeoutMilliseconds
        )
        XCTAssertEqual(parser.prefixTimeoutMilliseconds, 1000)
    }

    func testDefaultsExcludeTheThreeNamedAppsByBundleIdentifier() {
        let settings = Settings.defaults
        XCTAssertTrue(settings.isExcluded(bundleIdentifier: "com.apple.Terminal"))
        XCTAssertTrue(settings.isExcluded(bundleIdentifier: "com.googlecode.iterm2"))
        XCTAssertTrue(settings.isExcluded(bundleIdentifier: "org.gnu.Emacs"))
        XCTAssertFalse(settings.isExcluded(bundleIdentifier: "com.apple.Safari"))
        XCTAssertFalse(settings.isExcluded(bundleIdentifier: "com.google.Chrome"))
        XCTAssertFalse(settings.isExcluded(bundleIdentifier: "org.gnu.Aquamacs"))
        XCTAssertFalse(settings.isExcluded(bundleIdentifier: "com.apple.terminal"))
        XCTAssertFalse(settings.isExcluded(bundleIdentifier: "Terminal"))
    }

    func testExclusionTrimsTheQueryAndTreatsABlankIdentifierAsExcluded() {
        let settings = Settings.defaults
        XCTAssertTrue(settings.isExcluded(bundleIdentifier: " \n\tcom.apple.Terminal\t "))
        XCTAssertTrue(settings.isExcluded(bundleIdentifier: ""))
        XCTAssertTrue(settings.isExcluded(bundleIdentifier: " \n\t "))
        XCTAssertFalse(settings.isExcluded(bundleIdentifier: " com.apple.terminal "))
    }

    func testExclusionFollowsTheStoredList() {
        let settings = Settings(
            isPaused: false,
            excludedBundleIdentifiers: [" com.apple.Safari "],
            launchAtLogin: false,
            keySequenceTimeoutMilliseconds: 1000,
            pauseShortcut: .default
        )
        XCTAssertTrue(settings.isExcluded(bundleIdentifier: "com.apple.Safari"))
        XCTAssertFalse(settings.isExcluded(bundleIdentifier: "com.apple.Terminal"))
        XCTAssertTrue(settings.isExcluded(bundleIdentifier: ""))
    }

    func testPauseShortcutDefaultIsControlOptionVAndMatchesExactly() {
        XCTAssertEqual(PauseShortcut.default.key, "v")
        XCTAssertEqual(PauseShortcut.default.modifiers, [.control, .option])

        let shortcut = PauseShortcut.default
        XCTAssertTrue(shortcut.matches(key: "v", modifiers: [.control, .option]))
        XCTAssertTrue(shortcut.matches(key: "v", modifiers: [.option, .control]))
        XCTAssertFalse(shortcut.matches(key: "V", modifiers: [.control, .option]))
        XCTAssertFalse(shortcut.matches(key: "v", modifiers: [.control, .option, .shift]))
        XCTAssertFalse(shortcut.matches(key: "v", modifiers: [.control]))
        XCTAssertFalse(shortcut.matches(key: "v", modifiers: [.command, .option]))
        XCTAssertTrue(shortcut.matches(KeyEvent("v", modifiers: [.control, .option])))
        XCTAssertFalse(shortcut.matches(KeyEvent("v", modifiers: [.control, .option, .command])))
        XCTAssertFalse(shortcut.matches(KeyEvent(identity: .escape, modifiers: [.control, .option])))
        XCTAssertFalse(shortcut.matches(KeyEvent(identity: .unnamed, modifiers: [.control, .option])))
    }

    func testFreshStoreLoadsDefaultsWithoutWriting() throws {
        let store = InMemorySettingsStore()
        let loaded = try SettingsRepository(store: store).load()
        XCTAssertEqual(loaded, Settings.defaults)
        XCTAssertNil(try store.read())
    }

    func testSaveThenLoadRoundTripsEveryField() throws {
        let store = InMemorySettingsStore()
        let repository = SettingsRepository(store: store)
        let edited = Settings(
            isPaused: true,
            excludedBundleIdentifiers: ["com.apple.Safari", "org.gnu.Emacs"],
            launchAtLogin: true,
            keySequenceTimeoutMilliseconds: 2500,
            pauseShortcut: PauseShortcut(key: "k", modifiers: [.command, .shift])
        )
        try repository.save(edited)
        XCTAssertEqual(try repository.load(), edited)
        XCTAssertEqual(try SettingsRepository(store: store).load(), edited)
    }

    func testSavedDocumentIsSchemaVersionOneWithOnlyTheKnownFields() throws {
        let store = InMemorySettingsStore()
        let edited = Settings(
            isPaused: true,
            excludedBundleIdentifiers: ["a.b"],
            launchAtLogin: true,
            keySequenceTimeoutMilliseconds: 1,
            pauseShortcut: PauseShortcut(key: "/", modifiers: [.option])
        )
        try SettingsRepository(store: store).save(edited)
        let document = try dictionary(from: try XCTUnwrap(store.read()))
        XCTAssertEqual(Set(document.keys), SettingsTests.versionOneKeys)
        XCTAssertEqual(intValue(document["schemaVersion"]), 1)
        XCTAssertEqual(boolValue(document["paused"]), true)
        XCTAssertEqual(stringArray(document["excludedBundleIdentifiers"]), ["a.b"])
        XCTAssertEqual(boolValue(document["launchAtLogin"]), true)
        XCTAssertEqual(intValue(document["keySequenceTimeoutMilliseconds"]), 1)
        let shortcut = try XCTUnwrap(dictionaryValue(document["pauseShortcut"]))
        XCTAssertEqual(Set(shortcut.keys), ["key", "modifiers"])
        XCTAssertEqual(shortcut["key"] as? String, "/")
        XCTAssertEqual(stringArray(shortcut["modifiers"]), ["option"])
    }

    func testValueCopiesDoNotShareLaterEdits() {
        let original = Settings.defaults
        var copy = original
        copy.isPaused = true
        copy.excludedBundleIdentifiers = ["com.apple.Safari"]
        copy.launchAtLogin = true
        copy.keySequenceTimeoutMilliseconds = 50
        copy.pauseShortcut = PauseShortcut(key: "k", modifiers: [.command])
        XCTAssertEqual(original, Settings.defaults)
        XCTAssertNotEqual(copy, original)
    }

    func testTwoStoresDoNotShareDocuments() throws {
        let first = InMemorySettingsStore()
        let second = InMemorySettingsStore()
        var edited = Settings.defaults
        edited.isPaused = true
        edited.launchAtLogin = true
        try SettingsRepository(store: first).save(edited)
        XCTAssertEqual(try SettingsRepository(store: second).load(), Settings.defaults)
        XCTAssertNil(try second.read())
        XCTAssertNotNil(try first.read())
    }

    func testEmptyExclusionListIsStoredEmpty() throws {
        let store = InMemorySettingsStore()
        var edited = Settings.defaults
        edited.excludedBundleIdentifiers = []
        try SettingsRepository(store: store).save(edited)
        let loaded = try SettingsRepository(store: store).load()
        XCTAssertEqual(loaded.excludedBundleIdentifiers, [])
        XCTAssertFalse(loaded.isExcluded(bundleIdentifier: "com.apple.Terminal"))
        XCTAssertTrue(loaded.isExcluded(bundleIdentifier: " "))
    }

    func testMissingExclusionKeyUsesDefaultsAndDoesNotRewriteTheDocument() throws {
        let body = versionOneBody(omitting: "excludedBundleIdentifiers", paused: true, timeout: 60_000)
        let data = xmlPlist(body)
        let store = InMemorySettingsStore(data: data)
        let loaded = try SettingsRepository(store: store).load()
        XCTAssertEqual(loaded.excludedBundleIdentifiers, Settings.defaultExcludedBundleIdentifiers)
        XCTAssertTrue(loaded.isPaused)
        XCTAssertEqual(loaded.keySequenceTimeoutMilliseconds, 60_000)
        XCTAssertFalse(loaded.launchAtLogin)
        XCTAssertEqual(loaded.pauseShortcut, .default)
        XCTAssertEqual(try store.read(), data)
    }

    func testExplicitEmptyExclusionListInVersionOneStaysEmpty() throws {
        let data = try plist([
            "schemaVersion": 1,
            "paused": false,
            "excludedBundleIdentifiers": [String](),
            "launchAtLogin": false,
            "keySequenceTimeoutMilliseconds": 1000,
            "pauseShortcut": shortcutDictionary(.default),
        ])
        let store = InMemorySettingsStore(data: data)
        let loaded = try SettingsRepository(store: store).load()
        XCTAssertEqual(loaded.excludedBundleIdentifiers, [])
        XCTAssertEqual(try store.read(), data)
    }

    func testLegacyApplicationNamesMigrateToBundleIdentifiersAndArePersisted() throws {
        let original = try plist([
            "excludedApplications": ["Terminal", " iTerm2 ", "emacs"],
            "pauseHotkey": " ctrl+option+v ",
            "paused": true,
            "launchAtLogin": true,
            "keySequenceTimeoutMilliseconds": 1500,
        ])
        let store = InMemorySettingsStore(data: original)
        let repository = SettingsRepository(store: store)
        let loaded = try repository.load()
        XCTAssertEqual(loaded.excludedBundleIdentifiers, [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "org.gnu.Emacs",
        ])
        XCTAssertTrue(loaded.isPaused)
        XCTAssertTrue(loaded.launchAtLogin)
        XCTAssertEqual(loaded.keySequenceTimeoutMilliseconds, 1500)
        XCTAssertEqual(loaded.pauseShortcut, .default)
        XCTAssertNotEqual(try store.read(), original)

        let migrated = try XCTUnwrap(store.read())
        let document = try dictionary(from: migrated)
        XCTAssertEqual(Set(document.keys), SettingsTests.versionOneKeys)
        XCTAssertEqual(intValue(document["schemaVersion"]), 1)
        XCTAssertEqual(stringArray(document["excludedBundleIdentifiers"]), loaded.excludedBundleIdentifiers)
        XCTAssertNil(document["excludedApplications"])
        XCTAssertNil(document["pauseHotkey"])
        let shortcut = try XCTUnwrap(dictionaryValue(document["pauseShortcut"]))
        XCTAssertEqual(stringArray(shortcut["modifiers"]), ["control", "option"])

        let again = try repository.load()
        XCTAssertEqual(again, loaded)
        XCTAssertEqual(try store.read(), migrated)
    }

    func testLegacyMigrationAcceptsKnownSpellingsAndCollapsesAliasesInOrder() throws {
        let data = try plist([
            "schemaVersion": 0,
            "excludedApplications": [
                "Emacs",
                "com.apple.Safari",
                "TERMINAL",
                "emacs",
                "org.gnu.Emacs",
                "iTerm",
                "iterm2",
                "COM.APPLE.TERMINAL",
            ],
            "pauseHotkey": "CONTROL+OPTION+V",
        ])
        let store = InMemorySettingsStore(data: data)
        let loaded = try SettingsRepository(store: store).load()
        XCTAssertEqual(loaded.excludedBundleIdentifiers, [
            "org.gnu.Emacs",
            "com.apple.Safari",
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "COM.APPLE.TERMINAL",
        ])
        XCTAssertEqual(loaded.pauseShortcut, .default)
        XCTAssertFalse(loaded.isPaused)
        XCTAssertFalse(loaded.launchAtLogin)
        XCTAssertEqual(loaded.keySequenceTimeoutMilliseconds, 1000)
    }

    func testLegacyEmptyExclusionListDoesNotGrowTheDefaults() throws {
        let data = try plist([
            "excludedApplications": [String](),
            "pauseHotkey": "control+option+v",
        ])
        let loaded = try loadSettings(data)
        XCTAssertEqual(loaded.excludedBundleIdentifiers, [])
    }

    func testLegacyMissingFieldsUseDefaults() throws {
        let loaded = try loadSettings(try plist(["pauseHotkey": "ctrl+option+v"]))
        XCTAssertEqual(loaded.excludedBundleIdentifiers, Settings.defaultExcludedBundleIdentifiers)
        XCTAssertEqual(loaded.pauseShortcut, .default)
        XCTAssertFalse(loaded.isPaused)
        XCTAssertFalse(loaded.launchAtLogin)
        XCTAssertEqual(loaded.keySequenceTimeoutMilliseconds, 1000)
    }

    func testLegacyRejectsUnknownApplicationsWithoutWriting() throws {
        let data = try plist(["excludedApplications": ["Terminal", "Vim"]])
        assertRejected(data, .unrecognizedExcludedApplication("Vim"))
    }

    func testLegacyRejectsABlankNameAndAReversedHotkeyWithoutWriting() throws {
        assertRejected(
            try plist(["excludedApplications": [" "]]),
            .blankBundleIdentifier
        )
        assertRejected(
            try plist(["pauseHotkey": "option+ctrl+v"]),
            .invalidShortcut
        )
        assertRejected(
            try plist(["pauseHotkey": "ctrl+alt+v"]),
            .invalidShortcut
        )
        assertRejected(
            try plist(["pauseHotkey": 1]),
            .invalidShortcut
        )
    }

    func testVersionZeroWithoutOtherFieldsMigratesToTheDefaults() throws {
        let data = try plist(["schemaVersion": 0])
        let store = InMemorySettingsStore(data: data)
        let loaded = try SettingsRepository(store: store).load()
        XCTAssertEqual(loaded, Settings.defaults)
        let document = try dictionary(from: try XCTUnwrap(store.read()))
        XCTAssertEqual(intValue(document["schemaVersion"]), 1)
        XCTAssertEqual(
            stringArray(document["excludedBundleIdentifiers"]),
            Settings.defaultExcludedBundleIdentifiers
        )
    }

    func testFutureSchemaIsLeftUntouched() throws {
        let data = try plist([
            "schemaVersion": 2,
            "paused": true,
            "excludedBundleIdentifiers": ["com.apple.Terminal"],
        ])
        assertRejected(data, .unsupportedSchemaVersion(2))
        assertRejected(try plist(["schemaVersion": -1]), .unsupportedSchemaVersion(-1))
    }

    func testSchemaVersionMustBeAnInteger() {
        assertRejected(xmlPlist("<key>schemaVersion</key><string>1</string>"), .invalidSchemaVersion)
        assertRejected(xmlPlist("<key>schemaVersion</key><true/>"), .invalidSchemaVersion)
        assertRejected(xmlPlist("<key>schemaVersion</key><real>1.0</real>"), .invalidSchemaVersion)
    }

    func testUnreadableOrNonDictionaryDocumentsAreRejected() {
        assertRejected(Data("not a plist".utf8), .unreadableDocument)
        assertRejected(Data(), .unreadableDocument)
        let array = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array><string>Terminal</string></array>
        </plist>
        """
        assertRejected(Data(array.utf8), .notADictionary)
    }

    func testBooleansRejectIntegersAndStrings() {
        assertRejected(
            xmlPlist("<key>schemaVersion</key><integer>1</integer><key>paused</key><integer>1</integer>"),
            .invalidBoolean("paused")
        )
        assertRejected(
            xmlPlist("<key>schemaVersion</key><integer>1</integer><key>launchAtLogin</key><string>true</string>"),
            .invalidBoolean("launchAtLogin")
        )
    }

    func testTimeoutRejectsNonIntegersAndOutOfRangeValues() throws {
        assertRejected(
            xmlPlist("<key>schemaVersion</key><integer>1</integer><key>keySequenceTimeoutMilliseconds</key><string>1000</string>"),
            .invalidInteger("keySequenceTimeoutMilliseconds")
        )
        assertRejected(
            xmlPlist("<key>schemaVersion</key><integer>1</integer><key>keySequenceTimeoutMilliseconds</key><true/>"),
            .invalidInteger("keySequenceTimeoutMilliseconds")
        )
        assertRejected(
            xmlPlist("<key>schemaVersion</key><integer>1</integer><key>keySequenceTimeoutMilliseconds</key><real>1000</real>"),
            .invalidInteger("keySequenceTimeoutMilliseconds")
        )
        for value in [0, -5, 60_001] {
            let data = try plist([
                "schemaVersion": 1,
                "keySequenceTimeoutMilliseconds": value,
            ])
            assertRejected(data, .timeoutOutOfRange(value))
        }
        let lower = try loadSettings(try plist(["schemaVersion": 1, "keySequenceTimeoutMilliseconds": 1]))
        let upper = try loadSettings(try plist(["schemaVersion": 1, "keySequenceTimeoutMilliseconds": 60_000]))
        XCTAssertEqual(lower.keySequenceTimeoutMilliseconds, 1)
        XCTAssertEqual(upper.keySequenceTimeoutMilliseconds, 60_000)
    }

    func testVersionOneRejectsBadExclusionEntries() throws {
        let cases: [([String], SettingsError)] = [
            ([""], .blankBundleIdentifier),
            ([" \n "], .blankBundleIdentifier),
            (["Terminal"], .invalidBundleIdentifier("Terminal")),
            (["com..apple"], .invalidBundleIdentifier("com..apple")),
            (["com.apple."], .invalidBundleIdentifier("com.apple.")),
            ([".com.apple"], .invalidBundleIdentifier(".com.apple")),
            (["com.apple.term_inal"], .invalidBundleIdentifier("com.apple.term_inal")),
            (["com.apple.Terminal Browser"], .invalidBundleIdentifier("com.apple.Terminal Browser")),
            (["-com.apple"], .invalidBundleIdentifier("-com.apple")),
            (["com.apple.Terminal!"], .invalidBundleIdentifier("com.apple.Terminal!")),
            (["com.apple.Terminal", " com.apple.Terminal "], .duplicateBundleIdentifier("com.apple.Terminal")),
        ]
        for (ids, expected) in cases {
            let data = try plist(["schemaVersion": 1, "excludedBundleIdentifiers": ids])
            assertRejected(data, expected)
        }
        assertRejected(
            xmlPlist("<key>schemaVersion</key><integer>1</integer><key>excludedBundleIdentifiers</key><string>com.apple.Terminal</string>"),
            .invalidStringArray("excludedBundleIdentifiers")
        )
        assertRejected(
            xmlPlist("<key>schemaVersion</key><integer>1</integer><key>excludedBundleIdentifiers</key><array><integer>1</integer></array>"),
            .invalidStringArray("excludedBundleIdentifiers")
        )
        let hyphenated = try loadSettings(try plist([
            "schemaVersion": 1,
            "excludedBundleIdentifiers": ["com.apple.term-inal", "a.b"],
        ]))
        XCTAssertEqual(hyphenated.excludedBundleIdentifiers, ["com.apple.term-inal", "a.b"])
    }

    func testSaveNormalizesWhitespaceAndRejectsInvalidValuesWithoutReplacingTheStore() throws {
        let store = InMemorySettingsStore()
        try SettingsRepository(store: store).save(Settings.defaults)
        let original = try XCTUnwrap(store.read())

        var spaced = Settings.defaults
        spaced.excludedBundleIdentifiers = [" com.apple.Safari ", "org.gnu.Emacs"]
        try SettingsRepository(store: store).save(spaced)
        let loaded = try SettingsRepository(store: store).load()
        XCTAssertEqual(loaded.excludedBundleIdentifiers, ["com.apple.Safari", "org.gnu.Emacs"])

        let preserved = try XCTUnwrap(store.read())
        var duplicate = loaded
        duplicate.excludedBundleIdentifiers = ["com.apple.Safari", "com.apple.Safari"]
        assertSaveRejected(store, duplicate, .duplicateBundleIdentifier("com.apple.Safari"))
        XCTAssertEqual(try store.read(), preserved)

        var blank = loaded
        blank.excludedBundleIdentifiers = [" "]
        assertSaveRejected(store, blank, .blankBundleIdentifier)

        var unnamed = loaded
        unnamed.excludedBundleIdentifiers = ["Emacs"]
        assertSaveRejected(store, unnamed, .invalidBundleIdentifier("Emacs"))

        var timeout = loaded
        timeout.keySequenceTimeoutMilliseconds = 0
        assertSaveRejected(store, timeout, .timeoutOutOfRange(0))

        var shiftOnly = loaded
        shiftOnly.pauseShortcut = PauseShortcut(key: "v", modifiers: [.shift])
        assertSaveRejected(store, shiftOnly, .pauseShortcutNeedsANonShiftModifier)

        var bare = loaded
        bare.pauseShortcut = PauseShortcut(key: "v", modifiers: [])
        assertSaveRejected(store, bare, .pauseShortcutNeedsANonShiftModifier)

        var newline = loaded
        newline.pauseShortcut = PauseShortcut(key: "\n", modifiers: [.control])
        assertSaveRejected(store, newline, .invalidPauseKey)

        var spaceKey = loaded
        spaceKey.pauseShortcut = PauseShortcut(key: " ", modifiers: [.control])
        assertSaveRejected(store, spaceKey, .invalidPauseKey)

        var deleteKey = loaded
        deleteKey.pauseShortcut = PauseShortcut(key: "\u{7F}", modifiers: [.control])
        assertSaveRejected(store, deleteKey, .invalidPauseKey)

        let combining = try XCTUnwrap(String("e\u{0301}").first)
        var grapheme = loaded
        grapheme.pauseShortcut = PauseShortcut(key: combining, modifiers: [.control])
        assertSaveRejected(store, grapheme, .invalidPauseKey)

        XCTAssertNotEqual(original, preserved)
        XCTAssertEqual(try store.read(), preserved)
        XCTAssertEqual(try SettingsRepository(store: store).load(), loaded)
    }

    func testPauseShortcutRoundTripsCanonicalModifiers() throws {
        let data = try plist([
            "schemaVersion": 1,
            "pauseShortcut": [
                "key": "k",
                "modifiers": ["shift", "command", "control", "option"],
            ],
        ])
        let loaded = try loadSettings(data)
        XCTAssertEqual(
            loaded.pauseShortcut,
            PauseShortcut(key: "k", modifiers: [.control, .option, .command, .shift])
        )
        let accented = try loadSettings(try plist([
            "schemaVersion": 1,
            "pauseShortcut": [
                "key": "é",
                "modifiers": ["control"],
            ],
        ]))
        XCTAssertEqual(accented.pauseShortcut, PauseShortcut(key: "é", modifiers: [.control]))
        XCTAssertTrue(accented.pauseShortcut.matches(key: "é", modifiers: [.control]))
    }

    func testPauseShortcutStructureIsValidated() throws {
        assertRejected(try plist(["schemaVersion": 1, "pauseShortcut": "ctrl+option+v"]), .invalidShortcut)
        assertRejected(try plist([
            "schemaVersion": 1,
            "pauseShortcut": ["modifiers": ["control", "option"]],
        ]), .invalidShortcut)
        assertRejected(try plist([
            "schemaVersion": 1,
            "pauseShortcut": ["key": "v"],
        ]), .invalidShortcut)
        assertRejected(try plist([
            "schemaVersion": 1,
            "pauseShortcut": ["key": "v", "modifiers": "control"],
        ]), .invalidShortcut)
        assertRejected(try plist([
            "schemaVersion": 1,
            "pauseShortcut": ["key": "", "modifiers": ["control"]],
        ]), .invalidPauseKey)
        assertRejected(try plist([
            "schemaVersion": 1,
            "pauseShortcut": ["key": "vv", "modifiers": ["control"]],
        ]), .invalidPauseKey)
        assertRejected(try plist([
            "schemaVersion": 1,
            "pauseShortcut": ["key": " ", "modifiers": ["control"]],
        ]), .invalidPauseKey)
        assertRejected(try plist([
            "schemaVersion": 1,
            "pauseShortcut": ["key": "v", "modifiers": [String]()],
        ]), .pauseShortcutNeedsANonShiftModifier)
        assertRejected(try plist([
            "schemaVersion": 1,
            "pauseShortcut": ["key": "v", "modifiers": ["shift"]],
        ]), .pauseShortcutNeedsANonShiftModifier)
        assertRejected(try plist([
            "schemaVersion": 1,
            "pauseShortcut": ["key": "v", "modifiers": ["alt"]],
        ]), .unknownPauseModifier("alt"))
        assertRejected(try plist([
            "schemaVersion": 1,
            "pauseShortcut": ["key": "v", "modifiers": ["ctrl"]],
        ]), .unknownPauseModifier("ctrl"))
        assertRejected(try plist([
            "schemaVersion": 1,
            "pauseShortcut": ["key": "v", "modifiers": ["control", "control"]],
        ]), .duplicatePauseModifier("control"))
        assertRejected(
            xmlPlist("""
            <key>schemaVersion</key><integer>1</integer>
            <key>pauseShortcut</key>
            <dict>
            <key>key</key><string>v</string>
            <key>modifiers</key><array><integer>1</integer></array>
            </dict>
            """),
            .invalidShortcut
        )
        assertRejected(try plist([
            "schemaVersion": 1,
            "pauseShortcut": ["key": 1, "modifiers": ["control"]],
        ]), .invalidShortcut)
    }

    func testUnknownAndLegacyFieldsAreRejectedOnTheirOppositeSchemas() throws {
        assertRejected(
            try plist(["schemaVersion": 1, "scrollStepSize": 60]),
            .unknownField("scrollStepSize")
        )
        assertRejected(
            try plist(["schemaVersion": 1, "excludedApplications": ["Terminal"]]),
            .unknownField("excludedApplications")
        )
        assertRejected(
            try plist(["schemaVersion": 1, "pauseHotkey": "ctrl+option+v"]),
            .unknownField("pauseHotkey")
        )
        assertRejected(
            try plist([
                "excludedApplications": ["Terminal"],
                "excludedBundleIdentifiers": ["com.apple.Terminal"],
            ]),
            .unknownField("excludedBundleIdentifiers")
        )
        assertRejected(
            try plist(["pauseShortcut": shortcutDictionary(.default)]),
            .unknownField("pauseShortcut")
        )
    }

    func testReadFailureDoesNotWrite() throws {
        let original = try plist(["schemaVersion": 1, "paused": true])
        let store = ThrowingSettingsStore()
        store.readError = .readFailed
        store.data = original
        XCTAssertThrowsError(try SettingsRepository(store: store).load()) { error in
            XCTAssertEqual(error as? ThrowingSettingsStore.Failure, .readFailed)
        }
        XCTAssertEqual(store.writeCount, 0)
        XCTAssertEqual(store.data, original)
    }

    func testWriteFailureLeavesThePreviousDocument() throws {
        let store = ThrowingSettingsStore()
        let repository = SettingsRepository(store: store)
        try repository.save(Settings.defaults)
        let original = try XCTUnwrap(store.data)
        store.writeError = .writeFailed
        var edited = Settings.defaults
        edited.isPaused = true
        XCTAssertThrowsError(try repository.save(edited)) { error in
            XCTAssertEqual(error as? ThrowingSettingsStore.Failure, .writeFailed)
        }
        XCTAssertEqual(store.data, original)
        store.writeError = nil
        XCTAssertEqual(try repository.load(), Settings.defaults)
    }

    func testMigrationWriteFailureLeavesTheLegacyDocument() throws {
        let legacy = try plist(["excludedApplications": ["Emacs"]])
        let store = ThrowingSettingsStore()
        store.data = legacy
        store.writeError = .writeFailed
        XCTAssertThrowsError(try SettingsRepository(store: store).load()) { error in
            XCTAssertEqual(error as? ThrowingSettingsStore.Failure, .writeFailed)
        }
        XCTAssertEqual(store.data, legacy)
    }

    func testInMemoryStoreStartsEmptyAndReplacesBytes() throws {
        let store = InMemorySettingsStore()
        XCTAssertNil(try store.read())
        let first = Data("one".utf8)
        let second = Data("two".utf8)
        try store.write(first)
        XCTAssertEqual(try store.read(), first)
        try store.write(second)
        XCTAssertEqual(try store.read(), second)
    }

    func testSettingsSourcesDoNotTouchTheNetworkLoginItemsOrUserDefaults() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimCore/Settings.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        for token in SettingsTests.forbiddenRuntimeTokens + ["UserDefaults"] {
            XCTAssertFalse(text.contains(token), token)
        }
    }

    private static let versionOneKeys: Set<String> = [
        "schemaVersion",
        "paused",
        "excludedBundleIdentifiers",
        "launchAtLogin",
        "keySequenceTimeoutMilliseconds",
        "pauseShortcut",
    ]

    private static let forbiddenRuntimeTokens = [
        "URLSession",
        "URLRequest",
        "import Network",
        "NWConnection",
        "os_log",
        "Logger(",
        "NSLog",
        "print(",
        "SMAppService",
        "SMLoginItemSetEnabled",
        "LSSharedFileList",
        "CGEvent",
        "NSWorkspace",
        "Process(",
    ]
}

private final class ThrowingSettingsStore: SettingsStore, @unchecked Sendable {
    enum Failure: Error, Equatable {
        case readFailed
        case writeFailed
    }

    var data: Data?
    var readError: Failure?
    var writeError: Failure?
    private(set) var writeCount = 0

    func read() throws -> Data? {
        if let readError { throw readError }
        return data
    }

    func write(_ data: Data) throws {
        writeCount += 1
        if let writeError { throw writeError }
        self.data = data
    }
}

private func loadSettings(_ data: Data) throws -> Settings {
    try SettingsRepository(store: InMemorySettingsStore(data: data)).load()
}

private func assertRejected(
    _ data: Data,
    _ expected: SettingsError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let store = InMemorySettingsStore(data: data)
    XCTAssertThrowsError(try SettingsRepository(store: store).load(), file: file, line: line) { error in
        XCTAssertEqual(error as? SettingsError, expected, file: file, line: line)
    }
    XCTAssertEqual(try store.read(), data, file: file, line: line)
}

private func assertSaveRejected(
    _ store: InMemorySettingsStore,
    _ settings: Settings,
    _ expected: SettingsError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(try SettingsRepository(store: store).save(settings), file: file, line: line) { error in
        XCTAssertEqual(error as? SettingsError, expected, file: file, line: line)
    }
}

private func shortcutDictionary(_ shortcut: PauseShortcut) -> [String: Any] {
    ["key": String(shortcut.key), "modifiers": ["control", "option"]]
}

private func plist(_ value: Any) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
}

private func dictionary(from data: Data) throws -> [String: Any] {
    let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    return try XCTUnwrap(dictionaryValue(object))
}

private func dictionaryValue(_ value: Any?) -> [String: Any]? {
    guard let value else { return nil }
    if let dict = value as? [String: Any] { return dict }
    guard let dict = value as? NSDictionary else { return nil }
    var result: [String: Any] = [:]
    for case let (key as String, nested) in dict {
        result[key] = nested
    }
    return result
}

private func stringArray(_ value: Any?) -> [String]? {
    if let strings = value as? [String] { return strings }
    let items: [Any]?
    if let array = value as? [Any] {
        items = array
    } else if let array = value as? NSArray {
        items = array.map { $0 }
    } else {
        items = nil
    }
    guard let items else { return nil }
    var result: [String] = []
    for item in items {
        guard let string = item as? String else { return nil }
        result.append(string)
    }
    return result
}

private func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int { return int }
    if let number = value as? NSNumber, !(value is Bool) {
        return number.intValue
    }
    return nil
}

private func boolValue(_ value: Any?) -> Bool? {
    value as? Bool
}

private func xmlPlist(_ body: String) -> Data {
    Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \(body)
    </dict>
    </plist>
    """.utf8)
}

private func versionOneBody(omitting omitted: String, paused: Bool, timeout: Int) -> String {
    var lines: [String] = []
    func add(_ key: String, _ xml: String) {
        if key == omitted { return }
        lines.append("<key>\(key)</key>")
        lines.append(xml)
    }
    add("schemaVersion", "<integer>1</integer>")
    add("paused", paused ? "<true/>" : "<false/>")
    add("excludedBundleIdentifiers", "<array><string>com.apple.Safari</string></array>")
    add("launchAtLogin", "<false/>")
    add("keySequenceTimeoutMilliseconds", "<integer>\(timeout)</integer>")
    add("pauseShortcut", """
    <dict>
    <key>key</key><string>v</string>
    <key>modifiers</key>
    <array><string>control</string><string>option</string></array>
    </dict>
    """)
    return lines.joined(separator: "\n")
}

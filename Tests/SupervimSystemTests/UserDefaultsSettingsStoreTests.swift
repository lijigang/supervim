import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// UserDefaults adapter. Every suite name is temporary and removed before the test returns.
final class UserDefaultsSettingsStoreTests: XCTestCase {
    func testApplicationIdentifiersStayOffTheStandardDomain() {
        XCTAssertEqual(UserDefaultsSettingsStore.applicationSuiteName, "com.lijigang.supervim")
        XCTAssertEqual(UserDefaultsSettingsStore.storageKey, "com.lijigang.supervim.settings")
    }

    func testMissingKeyReadsNil() throws {
        let defaults = try temporaryDefaults()
        defer { remove(defaults) }
        let store = UserDefaultsSettingsStore(defaults: defaults.defaults)
        XCTAssertNil(try store.read())
    }

    func testWriteThenReadRoundTripsBytes() throws {
        let defaults = try temporaryDefaults()
        defer { remove(defaults) }
        let store = UserDefaultsSettingsStore(defaults: defaults.defaults)
        let payload = Data("settings-bytes".utf8)
        try store.write(payload)
        XCTAssertEqual(try store.read(), payload)
        let replacement = Data("replaced".utf8)
        try store.write(replacement)
        XCTAssertEqual(try store.read(), replacement)
    }

    func testRepositoryRoundTripStaysInsideTheInjectedSuite() throws {
        let defaults = try temporaryDefaults()
        defer { remove(defaults) }
        let store = UserDefaultsSettingsStore(defaults: defaults.defaults)
        var edited = Settings.defaults
        edited.isPaused = true
        edited.launchAtLogin = true
        edited.excludedBundleIdentifiers = ["com.apple.Safari"]
        edited.keySequenceTimeoutMilliseconds = 1250
        edited.pauseShortcut = PauseShortcut(key: "k", modifiers: [.command])
        try SettingsRepository(store: store).save(edited)
        XCTAssertEqual(try SettingsRepository(store: store).load(), edited)

        XCTAssertNotNil(defaults.defaults.data(forKey: UserDefaultsSettingsStore.storageKey))
        XCTAssertNil(defaults.defaults.object(forKey: "excludedBundleIdentifiers"))
        XCTAssertNil(defaults.defaults.object(forKey: "paused"))
        XCTAssertNil(defaults.defaults.object(forKey: "launchAtLogin"))
        XCTAssertNil(UserDefaults.standard.data(forKey: UserDefaultsSettingsStore.storageKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: "excludedBundleIdentifiers"))
    }

    func testSeparateSuitesAreIsolated() throws {
        let first = try temporaryDefaults()
        let second = try temporaryDefaults()
        defer {
            remove(first)
            remove(second)
        }
        var edited = Settings.defaults
        edited.isPaused = true
        try SettingsRepository(store: UserDefaultsSettingsStore(defaults: first.defaults)).save(edited)
        XCTAssertEqual(
            try SettingsRepository(store: UserDefaultsSettingsStore(defaults: second.defaults)).load(),
            Settings.defaults
        )
        XCTAssertNil(try UserDefaultsSettingsStore(defaults: second.defaults).read())
    }

    func testANonDataValueIsRejectedAndLeftInPlace() throws {
        let defaults = try temporaryDefaults()
        defer { remove(defaults) }
        defaults.defaults.set("not-a-document", forKey: UserDefaultsSettingsStore.storageKey)
        let store = UserDefaultsSettingsStore(defaults: defaults.defaults)
        XCTAssertThrowsError(try store.read()) { error in
            XCTAssertEqual(error as? SettingsError, .unreadableDocument)
        }
        XCTAssertThrowsError(try SettingsRepository(store: store).load()) { error in
            XCTAssertEqual(error as? SettingsError, .unreadableDocument)
        }
        XCTAssertEqual(
            defaults.defaults.string(forKey: UserDefaultsSettingsStore.storageKey),
            "not-a-document"
        )
    }

    func testLegacyMigrationPersistsInsideTheSuite() throws {
        let defaults = try temporaryDefaults()
        defer { remove(defaults) }
        let legacy = try PropertyListSerialization.data(
            fromPropertyList: [
                "excludedApplications": ["iTerm", "Emacs"],
                "launchAtLogin": true,
            ],
            format: .xml,
            options: 0
        )
        let store = UserDefaultsSettingsStore(defaults: defaults.defaults)
        try store.write(legacy)
        let loaded = try SettingsRepository(store: store).load()
        XCTAssertEqual(loaded.excludedBundleIdentifiers, [
            "com.googlecode.iterm2",
            "org.gnu.Emacs",
        ])
        XCTAssertTrue(loaded.launchAtLogin)
        XCTAssertFalse(loaded.isPaused)
        let saved = try XCTUnwrap(try store.read())
        let object = try PropertyListSerialization.propertyList(from: saved, options: [], format: nil)
        let document = try XCTUnwrap(plistDictionary(object))
        XCTAssertEqual(plistInt(document["schemaVersion"]), 1)
        XCTAssertNil(document["excludedApplications"])
    }

    func testRemovingTheSuiteDropsTheDocument() throws {
        let defaults = try temporaryDefaults()
        let store = UserDefaultsSettingsStore(defaults: defaults.defaults)
        try store.write(Data("temporary".utf8))
        XCTAssertNotNil(try store.read())
        remove(defaults)
        XCTAssertNil(try store.read())
    }

    func testCustomKeyDoesNotUseTheDefaultStorageKey() throws {
        let defaults = try temporaryDefaults()
        defer { remove(defaults) }
        let store = UserDefaultsSettingsStore(defaults: defaults.defaults, key: "unit-test-key")
        try store.write(Data("custom".utf8))
        XCTAssertEqual(try store.read(), Data("custom".utf8))
        XCTAssertNil(defaults.defaults.data(forKey: UserDefaultsSettingsStore.storageKey))
        XCTAssertEqual(defaults.defaults.data(forKey: "unit-test-key"), Data("custom".utf8))
    }

    func testAdapterSourceDoesNotRegisterLoginItemsOrImportAppKit() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimSystem/UserDefaultsSettingsStore.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        for token in [
            "import AppKit",
            "import Cocoa",
            "SMAppService",
            "SMLoginItemSetEnabled",
            "LSSharedFileList",
            "URLSession",
            "CGEvent",
            "NSWorkspace",
            "UserDefaults.standard",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
    }
}

private struct TemporaryDefaults {
    var suiteName: String
    var defaults: UserDefaults
}

private func temporaryDefaults() throws -> TemporaryDefaults {
    let suiteName = "com.lijigang.supervim.tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return TemporaryDefaults(suiteName: suiteName, defaults: defaults)
}

private func remove(_ temporary: TemporaryDefaults) {
    temporary.defaults.removePersistentDomain(forName: temporary.suiteName)
}

private func repoRoot(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func plistDictionary(_ value: Any?) -> [String: Any]? {
    if let dict = value as? [String: Any] { return dict }
    guard let dict = value as? NSDictionary else { return nil }
    var result: [String: Any] = [:]
    for case let (key as String, nested) in dict {
        result[key] = nested
    }
    return result
}

private func plistInt(_ value: Any?) -> Int? {
    if let int = value as? Int { return int }
    if let number = value as? NSNumber, !(value is Bool) {
        return number.intValue
    }
    return nil
}

import XCTest
@testable import SupervimCore

/// Menu titles, pause persistence, and the exclusion list.
/// The global chord is fed in as a key event. No event tap is installed here.
final class MenuBarControllerTests: XCTestCase {
    func testFreshMenuShowsNormalAndKeepsSettingsAndQuitEnabled() throws {
        let fixture = try makeMenu()
        assertRunningMenu(fixture.session.snapshot(), status: "Normal")
        let editor = fixture.session.editor()
        XCTAssertEqual(editor.bundleIdentifiers, Settings.defaultExcludedBundleIdentifiers)
        XCTAssertFalse(editor.launchAtLogin)
        XCTAssertFalse(editor.isVisible)
        XCTAssertEqual(editor.notice, "")
        XCTAssertEqual(editor.windowTitle, "Settings")
        XCTAssertEqual(editor.addButtonTitle, "Add \"com.apple.Safari\"")
        XCTAssertEqual(editor.removeButtonTitle, "Remove")
        XCTAssertEqual(editor.launchAtLoginTitle, "Launch at Login")
        XCTAssertEqual(editor.frontmostBundleIdentifier, "com.apple.Safari")
        XCTAssertTrue(editor.canAddFrontmost)
        XCTAssertNil(try fixture.store.read())
    }

    func testHintIsShownAsNormalAndInsertIsShownAsInsert() throws {
        let fixture = try makeMenu()
        _ = try fixture.session.handleKeyDown(KeyEvent("f"), cache: safariCache)
        assertRunningMenu(fixture.session.snapshot(), status: "Normal")
        _ = try fixture.session.handleKeyDown(KeyEvent(identity: .escape), cache: safariCache)
        _ = try fixture.session.handleKeyDown(KeyEvent("i"), cache: safariCache)
        assertRunningMenu(fixture.session.snapshot(), status: "Insert")
    }

    func testMenuPauseAndResumePersistAndReloadPaused() throws {
        let fixture = try makeMenu()
        let paused = shown(try fixture.session.perform(.pause))
        assertRunningMenu(paused, status: "Paused")
        XCTAssertTrue(try readSaved(fixture.repository).isPaused)
        let reloaded = try MenuBarController(
            repository: fixture.repository,
            clock: ManualKeyClock(),
            frontmost: fixture.frontmost
        )
        assertRunningMenu(reloaded.snapshot(), status: "Paused")
        let blocked = try reloaded.handleKeyDown(KeyEvent("j"), cache: safariCache)
        XCTAssertEqual(blocked.delivery, .passThrough)
        XCTAssertEqual(blocked.mode, .paused)

        let resumed = shown(try reloaded.perform(.resume))
        assertRunningMenu(resumed, status: "Normal")
        XCTAssertFalse(try readSaved(fixture.repository).isPaused)
        let third = try MenuBarController(
            repository: fixture.repository,
            clock: ManualKeyClock(),
            frontmost: fixture.frontmost
        )
        assertRunningMenu(third.snapshot(), status: "Normal")
        let scrolled = try third.handleKeyDown(KeyEvent("j"), cache: safariCache)
        XCTAssertEqual(scrolled.delivery, .swallow)
        XCTAssertEqual(scrolled.mode, .normal)
        XCTAssertFalse(scrolled.actions.isEmpty)
    }

    func testMenuPauseFromHintDropsThePrefixAndInsertRestoresInsert() throws {
        let fixture = try makeMenu()
        _ = try fixture.session.handleKeyDown(KeyEvent("g"), cache: safariCache)
        assertRunningMenu(shown(try fixture.session.perform(.pause)), status: "Paused")
        assertRunningMenu(shown(try fixture.session.perform(.resume)), status: "Normal")
        let afterPrefix = try fixture.session.handleKeyDown(KeyEvent("g"), cache: safariCache)
        XCTAssertEqual(afterPrefix.delivery, .swallow)
        XCTAssertEqual(afterPrefix.mode, .normal)
        XCTAssertTrue(afterPrefix.actions.isEmpty)

        _ = try fixture.session.handleKeyDown(KeyEvent("f"), cache: safariCache)
        assertRunningMenu(shown(try fixture.session.perform(.pause)), status: "Paused")
        assertRunningMenu(shown(try fixture.session.perform(.resume)), status: "Normal")
        let afterHint = try fixture.session.handleKeyDown(KeyEvent("j"), cache: safariCache)
        XCTAssertEqual(afterHint.delivery, .swallow)
        XCTAssertEqual(afterHint.mode, .normal)
        XCTAssertFalse(afterHint.actions.isEmpty)

        _ = try fixture.session.handleKeyDown(KeyEvent("i"), cache: safariCache)
        assertRunningMenu(shown(try fixture.session.perform(.pause)), status: "Paused")
        assertRunningMenu(shown(try fixture.session.perform(.resume)), status: "Insert")
        let typed = try fixture.session.handleKeyDown(KeyEvent("j"), cache: safariCache)
        XCTAssertEqual(typed.delivery, .passThrough)
        XCTAssertEqual(typed.mode, .insert)
    }

    func testMenuPauseWorksWhenFocusIsUnknown() throws {
        let fixture = try makeMenu()
        assertRunningMenu(shown(try fixture.session.perform(.pause)), status: "Paused")
        let decision = try fixture.session.handleKeyDown(KeyEvent("f"), cache: .unknown)
        XCTAssertEqual(decision.delivery, .passThrough)
        XCTAssertEqual(decision.mode, .paused)
        XCTAssertEqual(decision.actions, [])
        assertRunningMenu(fixture.session.snapshot(), status: "Paused")
    }

    func testPauseChordUpdatesTheMenuAndPersists() throws {
        let fixture = try makeMenu()
        let paused = try fixture.session.handleKeyDown(pauseChord(), cache: safariCache)
        XCTAssertEqual(paused.delivery, .swallow)
        XCTAssertEqual(paused.mode, .paused)
        assertRunningMenu(fixture.session.snapshot(), status: "Paused")
        XCTAssertTrue(try readSaved(fixture.repository).isPaused)

        let resumed = try fixture.session.handleKeyDown(pauseChord(), cache: safariCache)
        XCTAssertEqual(resumed.delivery, .swallow)
        XCTAssertEqual(resumed.mode, .normal)
        assertRunningMenu(fixture.session.snapshot(), status: "Normal")
        XCTAssertFalse(try readSaved(fixture.repository).isPaused)
        let scrolled = try fixture.session.handleKeyDown(KeyEvent("j"), cache: safariCache)
        XCTAssertEqual(scrolled.delivery, .swallow)
        XCTAssertFalse(scrolled.actions.isEmpty)
    }

    func testUnknownFocusDoesNotLetThePauseChordPause() throws {
        let fixture = try makeMenu()
        let unknown = CachedFocus(editability: .unknown, bundleIdentifier: "com.apple.Safari")
        let decision = try fixture.session.handleKeyDown(pauseChord(), cache: unknown)
        XCTAssertEqual(decision.delivery, .passThrough)
        XCTAssertEqual(decision.mode, .normal)
        assertRunningMenu(fixture.session.snapshot(), status: "Normal")
        XCTAssertNil(try fixture.store.read())
    }

    func testCustomPauseShortcutFromSettingsDrivesTheMenu() throws {
        var settings = Settings.defaults
        settings.pauseShortcut = PauseShortcut(key: "x", modifiers: [.control, .command])
        let fixture = try makeMenu(settings: settings)
        let ignored = try fixture.session.handleKeyDown(pauseChord(), cache: safariCache)
        XCTAssertEqual(ignored.mode, .normal)
        assertRunningMenu(fixture.session.snapshot(), status: "Normal")
        let custom = try fixture.session.handleKeyDown(
            KeyEvent("x", modifiers: [.control, .command]),
            cache: safariCache
        )
        XCTAssertEqual(custom.delivery, .swallow)
        XCTAssertEqual(custom.mode, .paused)
        assertRunningMenu(fixture.session.snapshot(), status: "Paused")
        XCTAssertTrue(try readSaved(fixture.repository).isPaused)
        XCTAssertEqual(try readSaved(fixture.repository).pauseShortcut, settings.pauseShortcut)
    }

    func testExcludedAppsPassKeysThroughIncludingThePauseChord() throws {
        let fixture = try makeMenu()
        let bundles = Settings.defaultExcludedBundleIdentifiers + ["", "   ", "\n"]
        for bundle in bundles {
            let cache = CachedFocus(editability: .notEditable, bundleIdentifier: bundle)
            let typed = try fixture.session.handleKeyDown(KeyEvent("j"), cache: cache)
            XCTAssertEqual(typed.delivery, .passThrough, bundle)
            XCTAssertEqual(typed.mode, .normal, bundle)
            XCTAssertEqual(typed.actions, [], bundle)
            let chord = try fixture.session.handleKeyDown(pauseChord(), cache: cache)
            XCTAssertEqual(chord.delivery, .passThrough, bundle)
            XCTAssertEqual(chord.mode, .normal, bundle)
            assertRunningMenu(fixture.session.snapshot(), status: "Normal")
        }
        XCTAssertNil(try fixture.store.read())

        let lowercased = CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.terminal")
        let scrolled = try fixture.session.handleKeyDown(KeyEvent("j"), cache: lowercased)
        XCTAssertEqual(scrolled.delivery, .swallow)
        XCTAssertEqual(scrolled.mode, .normal)
        XCTAssertFalse(scrolled.actions.isEmpty)
    }

    func testAddingAndRemovingTheFrontmostAppChangesInterception() throws {
        let fixture = try makeMenu()
        fixture.frontmost.bundleIdentifier = "  com.example.Notes  "
        let added = try fixture.session.addFrontmost()
        XCTAssertEqual(
            added.bundleIdentifiers,
            Settings.defaultExcludedBundleIdentifiers + ["com.example.Notes"]
        )
        XCTAssertEqual(added.notice, "")
        XCTAssertFalse(added.canAddFrontmost)
        XCTAssertEqual(
            try readSaved(fixture.repository).excludedBundleIdentifiers,
            added.bundleIdentifiers
        )

        let notes = CachedFocus(editability: .notEditable, bundleIdentifier: "com.example.Notes")
        let passed = try fixture.session.handleKeyDown(KeyEvent("j"), cache: notes)
        XCTAssertEqual(passed.delivery, .passThrough)
        XCTAssertEqual(passed.actions, [])
        let chord = try fixture.session.handleKeyDown(pauseChord(), cache: notes)
        XCTAssertEqual(chord.delivery, .passThrough)
        XCTAssertEqual(chord.mode, .normal)
        let safari = try fixture.session.handleKeyDown(KeyEvent("j"), cache: safariCache)
        XCTAssertEqual(safari.delivery, .swallow)
        XCTAssertFalse(safari.actions.isEmpty)

        let removed = try fixture.session.removeExcluded(bundleIdentifier: " com.example.Notes ")
        XCTAssertEqual(removed.bundleIdentifiers, Settings.defaultExcludedBundleIdentifiers)
        XCTAssertEqual(removed.notice, "")
        let again = try fixture.session.handleKeyDown(KeyEvent("j"), cache: notes)
        XCTAssertEqual(again.delivery, .swallow)
        XCTAssertFalse(again.actions.isEmpty)

        let withoutTerminal = try fixture.session.removeExcluded(bundleIdentifier: "  com.apple.Terminal  ")
        XCTAssertEqual(
            withoutTerminal.bundleIdentifiers,
            ["com.googlecode.iterm2", "org.gnu.Emacs"]
        )
        let terminal = try fixture.session.handleKeyDown(KeyEvent("j"), cache: terminalCache)
        XCTAssertEqual(terminal.delivery, .swallow)
        XCTAssertEqual(terminal.mode, .normal)

        let missing = try fixture.session.removeExcluded(bundleIdentifier: "com.example.Missing")
        XCTAssertEqual(missing.bundleIdentifiers, ["com.googlecode.iterm2", "org.gnu.Emacs"])
        XCTAssertEqual(missing.notice, "")
    }

    func testBlankDuplicateAndInvalidFrontmostAppsAreNotSaved() throws {
        let fixture = try makeMenu()
        fixture.frontmost.bundleIdentifier = "com.apple.Terminal"
        XCTAssertFalse(fixture.session.editor().canAddFrontmost)
        XCTAssertEqual(fixture.session.editor().notice, "")
        let duplicate = try fixture.session.addFrontmost()
        XCTAssertEqual(duplicate.bundleIdentifiers, Settings.defaultExcludedBundleIdentifiers)
        XCTAssertEqual(duplicate.notice, "That app is already excluded.")
        XCTAssertNil(try fixture.store.read())

        fixture.frontmost.bundleIdentifier = "   "
        XCTAssertFalse(fixture.session.editor().canAddFrontmost)
        let blank = try fixture.session.addFrontmost()
        XCTAssertEqual(blank.bundleIdentifiers, Settings.defaultExcludedBundleIdentifiers)
        XCTAssertEqual(blank.notice, "Switch to the app you want to exclude, then come back here.")

        fixture.frontmost.bundleIdentifier = "NotABundle"
        XCTAssertTrue(fixture.session.editor().canAddFrontmost)
        let invalid = try fixture.session.addFrontmost()
        XCTAssertEqual(invalid.bundleIdentifiers, Settings.defaultExcludedBundleIdentifiers)
        XCTAssertEqual(invalid.notice, "That bundle identifier cannot be saved.")
        XCTAssertNil(try fixture.store.read())
    }

    func testSupervimItselfIsNeverAdded() throws {
        // What the app reported once the settings window was in front.
        let fixture = try makeMenu(frontmost: "com.lijigang.supervim", own: "com.lijigang.supervim")
        fixture.frontmost.name = "Supervim"
        let editor = fixture.session.editor()
        XCTAssertFalse(editor.canAddFrontmost)
        XCTAssertEqual(editor.addButtonTitle, "Add Frontmost App")
        XCTAssertEqual(editor.notice, "Switch to the app you want to exclude, then come back here.")

        let refused = try fixture.session.addFrontmost()
        XCTAssertEqual(refused.bundleIdentifiers, Settings.defaultExcludedBundleIdentifiers)
        XCTAssertEqual(refused.notice, "Switch to the app you want to exclude, then come back here.")
        XCTAssertNil(try fixture.store.read())

        fixture.frontmost.bundleIdentifier = "  COM.lijigang.Supervim "
        XCTAssertFalse(fixture.session.editor().canAddFrontmost)
        let otherCase = try fixture.session.addFrontmost()
        XCTAssertEqual(otherCase.bundleIdentifiers, Settings.defaultExcludedBundleIdentifiers)
        XCTAssertNil(try fixture.store.read())
    }

    func testWithNoOtherAppKnownTheEditorSaysWhatToDo() throws {
        let fixture = try makeMenu(frontmost: "")
        let editor = fixture.session.editor()
        XCTAssertFalse(editor.canAddFrontmost)
        XCTAssertEqual(editor.addButtonTitle, "Add Frontmost App")
        XCTAssertEqual(editor.notice, "Switch to the app you want to exclude, then come back here.")

        fixture.frontmost.bundleIdentifier = "com.example.Notes"
        let known = fixture.session.editor()
        XCTAssertTrue(known.canAddFrontmost)
        XCTAssertEqual(known.notice, "")
    }

    func testAddButtonNamesTheAppItWillAdd() throws {
        let fixture = try makeMenu(frontmost: "com.tencent.xinWeChat")
        fixture.frontmost.name = "  WeChat "
        XCTAssertEqual(fixture.session.editor().addButtonTitle, "Add \"WeChat\"")

        fixture.frontmost.name = "   "
        XCTAssertEqual(fixture.session.editor().addButtonTitle, "Add \"com.tencent.xinWeChat\"")

        fixture.frontmost.name = "WeChat"
        let added = try fixture.session.addFrontmost()
        XCTAssertTrue(added.bundleIdentifiers.contains("com.tencent.xinWeChat"))
        XCTAssertFalse(added.canAddFrontmost)
        XCTAssertEqual(added.addButtonTitle, "Add \"WeChat\"")
    }

    func testLaunchAtLoginPreferenceTogglesWithoutChangingPauseOrTimeout() throws {
        let fixture = try makeMenu(frontmost: "com.example.Notes")
        assertRunningMenu(shown(try fixture.session.perform(.pause)), status: "Paused")
        let added = try fixture.session.addFrontmost()
        XCTAssertTrue(added.bundleIdentifiers.contains("com.example.Notes"))
        let enabled = try fixture.session.setLaunchAtLogin(true)
        XCTAssertTrue(enabled.launchAtLogin)
        XCTAssertTrue(enabled.bundleIdentifiers.contains("com.example.Notes"))
        XCTAssertEqual(fixture.session.snapshot().statusTitle, "Paused")
        let stored = try readSaved(fixture.repository)
        XCTAssertTrue(stored.launchAtLogin)
        XCTAssertTrue(stored.isPaused)
        XCTAssertEqual(stored.keySequenceTimeoutMilliseconds, Settings.defaultKeySequenceTimeoutMilliseconds)
        XCTAssertEqual(stored.pauseShortcut, .default)
        let disabled = try fixture.session.setLaunchAtLogin(false)
        XCTAssertFalse(disabled.launchAtLogin)
        XCTAssertTrue(try readSaved(fixture.repository).isPaused)
        XCTAssertTrue(try readSaved(fixture.repository).excludedBundleIdentifiers.contains("com.example.Notes"))
    }

    func testSettingsVisibilityAndQuitDoNotChangePause() throws {
        let fixture = try makeMenu()
        fixture.frontmost.bundleIdentifier = "com.example.Notes"
        let opened = shown(try fixture.session.perform(.settings))
        assertRunningMenu(opened, status: "Normal")
        XCTAssertTrue(fixture.session.editor().isVisible)
        XCTAssertEqual(fixture.session.editor().frontmostBundleIdentifier, "com.example.Notes")
        XCTAssertEqual(try fixture.session.perform(.quit), .terminate)
        assertRunningMenu(fixture.session.snapshot(), status: "Normal")
        XCTAssertNil(try fixture.store.read())
        XCTAssertEqual(fixture.session.closeSettings().isVisible, false)

        _ = try fixture.session.perform(.separator)
        _ = try fixture.session.perform(.resume)
        _ = try fixture.session.setLaunchAtLogin(false)
        XCTAssertNil(try fixture.store.read())
        _ = try fixture.session.handleKeyDown(KeyEvent("j"), cache: safariCache)
        XCTAssertNil(try fixture.store.read())
    }

    func testSavedPauseStartsTheMenuPausedBeforeAnyKey() throws {
        var settings = Settings.defaults
        settings.isPaused = true
        let fixture = try makeMenu(settings: settings)
        assertRunningMenu(fixture.session.snapshot(), status: "Paused")
        let decision = try fixture.session.handleKeyDown(KeyEvent("j"), cache: safariCache)
        XCTAssertEqual(decision.delivery, .passThrough)
        XCTAssertEqual(decision.mode, .paused)
    }

    func testMenuBarAppPresentsTheSnapshotAndDoesNotInstallTheTap() throws {
        let directory = repoRoot().appendingPathComponent("Sources/Supervim")
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        XCTAssertFalse(files.isEmpty)
        var combined = ""
        for relative in files {
            combined += try String(contentsOf: directory.appendingPathComponent(relative), encoding: .utf8)
        }
        XCTAssertTrue(combined.contains("MenuBarController"))
        XCTAssertTrue(combined.contains("canImport(AppKit)"))
        XCTAssertFalse(files.contains("main.swift"))
        let entry = try String(
            contentsOf: directory.appendingPathComponent("SupervimApp.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(entry.hasPrefix("#if os(macOS)\n"))
        XCTAssertTrue(entry.contains("@main"))
        XCTAssertFalse(entry.contains("canImport(AppKit)"))
        XCTAssertTrue(combined.contains("statusTitle"))
        XCTAssertTrue(combined.contains("addButtonTitle"))
        XCTAssertTrue(combined.contains("launchAtLoginTitle"))
        XCTAssertTrue(combined.contains("windowTitle"))
        XCTAssertFalse(combined.contains("MenuBarPlaceholder"))
        for token in [
            "CGEvent",
            "EventTap",
            "tapCreate",
            "SMAppService",
            "ServiceManagement",
            "AXUIElement",
            "scanFocus(",
            "URLSession",
            "keySequenceTimeout",
        ] {
            XCTAssertFalse(combined.contains(token), token)
        }

        let core = repoRoot().appendingPathComponent("Sources/SupervimCore")
        let coreFiles = try FileManager.default.subpathsOfDirectory(atPath: core.path)
            .filter { $0.hasSuffix(".swift") }
        var coreText = ""
        for relative in coreFiles {
            coreText += try String(contentsOf: core.appendingPathComponent(relative), encoding: .utf8)
        }
        for token in ["SMAppService", "ServiceManagement", "import AppKit"] {
            XCTAssertFalse(coreText.contains(token), token)
        }
    }
}

private let safariCache = CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.Safari")
private let terminalCache = CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.Terminal")

private struct MenuFixture {
    var repository: SettingsRepository
    var store: InMemorySettingsStore
    var frontmost: FixedFrontmost
    var session: MenuBarController<ManualKeyClock>
}

private func makeMenu(
    settings: Settings? = nil,
    frontmost bundleIdentifier: String = "com.apple.Safari",
    own ownBundleIdentifier: String = ""
) throws -> MenuFixture {
    let store = InMemorySettingsStore()
    let repository = SettingsRepository(store: store)
    if let settings {
        try repository.save(settings)
    }
    let frontmost = FixedFrontmost(bundleIdentifier: bundleIdentifier)
    let session = try MenuBarController(
        repository: repository,
        clock: ManualKeyClock(),
        frontmost: frontmost,
        ownBundleIdentifier: ownBundleIdentifier
    )
    return MenuFixture(
        repository: repository,
        store: store,
        frontmost: frontmost,
        session: session
    )
}

private func readSaved(_ repository: SettingsRepository) throws -> Settings {
    try repository.load()
}

private func pauseChord() -> KeyEvent {
    KeyEvent("v", modifiers: [.control, .option])
}

private func shown(
    _ effect: MenuBarEffect,
    file: StaticString = #filePath,
    line: UInt = #line
) -> MenuBarSnapshot {
    guard case .show(let snapshot) = effect else {
        XCTFail("expected the menu to stay open", file: file, line: line)
        return MenuBarSnapshot(statusTitle: "", commands: [])
    }
    return snapshot
}

private func menuItem(_ snapshot: MenuBarSnapshot, _ kind: MenuCommandKind) -> MenuCommand? {
    snapshot.commands.first { $0.kind == kind }
}

private func assertRunningMenu(
    _ snapshot: MenuBarSnapshot,
    status: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(snapshot.statusTitle, status, file: file, line: line)
    XCTAssertEqual(
        snapshot.commands.map(\.kind),
        [.pause, .resume, .settings, .separator, .quit],
        file: file,
        line: line
    )
    XCTAssertEqual(menuItem(snapshot, .pause)?.title, "Pause", file: file, line: line)
    XCTAssertEqual(menuItem(snapshot, .pause)?.enabled, status != "Paused", file: file, line: line)
    XCTAssertEqual(menuItem(snapshot, .resume)?.title, "Resume", file: file, line: line)
    XCTAssertEqual(menuItem(snapshot, .resume)?.enabled, status == "Paused", file: file, line: line)
    XCTAssertEqual(menuItem(snapshot, .settings)?.title, "Settings", file: file, line: line)
    XCTAssertEqual(menuItem(snapshot, .settings)?.enabled, true, file: file, line: line)
    XCTAssertEqual(menuItem(snapshot, .separator)?.title, "", file: file, line: line)
    XCTAssertEqual(menuItem(snapshot, .separator)?.enabled, false, file: file, line: line)
    XCTAssertEqual(menuItem(snapshot, .quit)?.title, "Quit Supervim", file: file, line: line)
    XCTAssertEqual(menuItem(snapshot, .quit)?.enabled, true, file: file, line: line)
}

private final class FixedFrontmost: FrontmostBundleProviding, @unchecked Sendable {
    var bundleIdentifier: String
    var name = ""

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    func frontmostBundleIdentifier() -> String {
        bundleIdentifier
    }

    func frontmostApplicationName() -> String {
        name
    }
}

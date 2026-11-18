import XCTest
@testable import SupervimCore

/// Which app `Add Frontmost App` means once the settings window is in front.
/// The activations are fed in by hand. Nothing here asks the system.
final class LastExternalAppTests: XCTestCase {
    func testOpeningSettingsStillAddsTheAppThatWasInFrontBefore() throws {
        let tracker = makeTracker()
        tracker.noteActivated(weChat)
        tracker.noteActivated(supervim)

        let repository = SettingsRepository(store: InMemorySettingsStore())
        let session = try MenuBarController(
            repository: repository,
            clock: ManualKeyClock(),
            frontmost: tracker,
            ownBundleIdentifier: ownBundle
        )
        XCTAssertEqual(session.editor().frontmostBundleIdentifier, "com.tencent.xinWeChat")
        XCTAssertTrue(session.editor().canAddFrontmost)

        let added = try session.addFrontmost()
        XCTAssertEqual(
            added.bundleIdentifiers,
            Settings.defaultExcludedBundleIdentifiers + ["com.tencent.xinWeChat"]
        )
        XCTAssertFalse(added.bundleIdentifiers.contains(ownBundle))
        XCTAssertEqual(try repository.load().excludedBundleIdentifiers, added.bundleIdentifiers)
    }

    func testNothingIsKnownBeforeAnotherAppWasInFront() {
        let tracker = makeTracker()
        XCTAssertEqual(tracker.frontmostBundleIdentifier(), "")
        XCTAssertEqual(tracker.frontmostApplicationName(), "")

        tracker.noteActivated(supervim)
        XCTAssertEqual(tracker.frontmostBundleIdentifier(), "")
        XCTAssertEqual(tracker.frontmostApplicationName(), "")
    }

    func testTheMostRecentOtherAppIsRemembered() {
        let tracker = makeTracker()
        tracker.noteActivated(weChat)
        tracker.noteActivated(supervim)
        tracker.noteActivated(safari)
        tracker.noteActivated(supervim)
        XCTAssertEqual(tracker.frontmostBundleIdentifier(), "com.apple.Safari")
        XCTAssertEqual(tracker.frontmostApplicationName(), "Safari")
    }

    func testSupervimIsKnownByItsProcessWhenItHasNoBundleIdentifier() {
        // Run from the build folder, the process has no bundle identifier.
        let tracker = LastExternalApp(ownProcessIdentifier: ownProcess, ownBundleIdentifier: "")
        tracker.noteActivated(weChat)
        tracker.noteActivated(ActivatedApp(processIdentifier: ownProcess, bundleIdentifier: "", name: "Supervim"))
        tracker.noteActivated(
            ActivatedApp(processIdentifier: ownProcess, bundleIdentifier: "com.example.Renamed", name: "Supervim")
        )
        XCTAssertEqual(tracker.frontmostBundleIdentifier(), "com.tencent.xinWeChat")
        XCTAssertEqual(tracker.frontmostApplicationName(), "WeChat")
    }

    func testASecondCopyOfSupervimIsKnownByItsBundleIdentifier() {
        let tracker = makeTracker()
        tracker.noteActivated(weChat)
        tracker.noteActivated(ActivatedApp(processIdentifier: 4242, bundleIdentifier: ownBundle, name: "Supervim"))
        tracker.noteActivated(
            ActivatedApp(processIdentifier: 4243, bundleIdentifier: " COM.Lijigang.Supervim ", name: "Supervim")
        )
        XCTAssertEqual(tracker.frontmostBundleIdentifier(), "com.tencent.xinWeChat")
    }

    func testAnAppThatCannotBeNamedDoesNotReplaceTheRememberedOne() {
        let tracker = makeTracker()
        tracker.noteActivated(weChat)
        tracker.noteActivated(ActivatedApp(processIdentifier: 77, bundleIdentifier: "", name: "helper"))
        tracker.noteActivated(ActivatedApp(processIdentifier: 78, bundleIdentifier: "  \n", name: "helper"))
        XCTAssertEqual(tracker.frontmostBundleIdentifier(), "com.tencent.xinWeChat")
        XCTAssertEqual(tracker.frontmostApplicationName(), "WeChat")
    }

    func testIdentifierAndNameAreStoredTrimmed() {
        let tracker = makeTracker()
        tracker.noteActivated(
            ActivatedApp(processIdentifier: 90, bundleIdentifier: "  com.example.Notes\n", name: "  Notes ")
        )
        XCTAssertEqual(tracker.frontmostBundleIdentifier(), "com.example.Notes")
        XCTAssertEqual(tracker.frontmostApplicationName(), "Notes")
    }
}

private let ownProcess: Int32 = 501
private let ownBundle = "com.lijigang.supervim"

private let supervim = ActivatedApp(processIdentifier: ownProcess, bundleIdentifier: ownBundle, name: "Supervim")
private let weChat = ActivatedApp(processIdentifier: 610, bundleIdentifier: "com.tencent.xinWeChat", name: "WeChat")
private let safari = ActivatedApp(processIdentifier: 611, bundleIdentifier: "com.apple.Safari", name: "Safari")

private func makeTracker() -> LastExternalApp {
    LastExternalApp(ownProcessIdentifier: ownProcess, ownBundleIdentifier: ownBundle)
}

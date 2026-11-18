#if canImport(AppKit)
import AppKit
#endif
import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// The settings window makes Supervim the frontmost app. `Add Frontmost App`
/// must still mean the app that was in front before it.
final class WorkspaceActivationFeedTests: XCTestCase {
    func testTheAppAsksTheFeedAndDoesNotReadTheFrontmostAppAtClickTime() throws {
        let directory = repoRoot().appendingPathComponent("Sources/Supervim")
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        var combined = ""
        for relative in files {
            combined += try String(contentsOf: directory.appendingPathComponent(relative), encoding: .utf8)
        }
        XCTAssertTrue(combined.contains("LastExternalApp("))
        XCTAssertTrue(combined.contains("WorkspaceActivationFeed("))
        XCTAssertTrue(combined.contains("ownBundleIdentifier:"))
        XCTAssertFalse(combined.contains("frontmostApplication"))
        XCTAssertFalse(combined.contains("WorkspaceFrontmost"))
    }

    #if canImport(AppKit)
    func testActivatingThisProcessKeepsTheAppThatWasInFrontBefore() throws {
        let own = NSRunningApplication.current
        let other = try otherApplication()
        let tracker = LastExternalApp(
            ownProcessIdentifier: own.processIdentifier,
            ownBundleIdentifier: own.bundleIdentifier ?? ""
        )
        let center = NotificationCenter()
        let changes = ChangeCount()
        let feed = WorkspaceActivationFeed(tracker: tracker, center: center) {
            changes.add()
        }

        post(other, to: center)
        XCTAssertEqual(tracker.frontmostBundleIdentifier(), other.bundleIdentifier)
        XCTAssertEqual(changes.value, 1)

        post(own, to: center)
        XCTAssertEqual(tracker.frontmostBundleIdentifier(), other.bundleIdentifier)
        XCTAssertEqual(
            tracker.frontmostApplicationName(),
            (other.localizedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
        XCTAssertEqual(changes.value, 2)
        withExtendedLifetime(feed) {}
    }

    func testANotificationWithoutAnAppIsIgnored() throws {
        let own = NSRunningApplication.current
        let other = try otherApplication()
        let tracker = LastExternalApp(
            ownProcessIdentifier: own.processIdentifier,
            ownBundleIdentifier: own.bundleIdentifier ?? ""
        )
        let center = NotificationCenter()
        let changes = ChangeCount()
        let feed = WorkspaceActivationFeed(tracker: tracker, center: center) {
            changes.add()
        }

        post(other, to: center)
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil, userInfo: nil)
        center.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: "not an app"]
        )
        XCTAssertEqual(tracker.frontmostBundleIdentifier(), other.bundleIdentifier)
        XCTAssertEqual(changes.value, 1)
        withExtendedLifetime(feed) {}
    }

    private func otherApplication() throws -> NSRunningApplication {
        let own = NSRunningApplication.current
        let found = NSWorkspace.shared.runningApplications.first { application in
            guard let bundle = application.bundleIdentifier, !bundle.isEmpty else {
                return false
            }
            return application.processIdentifier != own.processIdentifier && bundle != own.bundleIdentifier
        }
        return try XCTUnwrap(found, "no other running app with a bundle identifier")
    }

    private func post(_ application: NSRunningApplication, to center: NotificationCenter) {
        center.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: application]
        )
    }
    #endif
}

#if canImport(AppKit)
private final class ChangeCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func add() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
#endif

private func repoRoot(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

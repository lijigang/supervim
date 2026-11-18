import SupervimCore
@testable import SupervimSystem
import XCTest

/// macOS switches an event tap off when its callback was slow, or when the
/// user did something it treats as an escape. Nothing switches it back on.
/// From then on every key goes straight to the app and Supervim looks dead.
final class TapGuardTests: XCTestCase {
    func testADisabledNoticeTurnsTheTapBackOnAtOnce() {
        let port = FakePort(enabled: false)
        let tapGuard = TapGuard(port: port)
        let lines = tapLines {
            tapGuard.disabled(.timeout)
        }
        XCTAssertTrue(port.isEnabled())
        XCTAssertEqual(port.enables, 1)
        XCTAssertEqual(tapGuard.revivals, 1)
        XCTAssertEqual(lines, ["tap-disabled reason=timeout reenabled=1"])
    }

    func testAUserInputNoticeIsTreatedTheSameWay() {
        let port = FakePort(enabled: false)
        let tapGuard = TapGuard(port: port)
        let lines = tapLines {
            tapGuard.disabled(.userInput)
        }
        XCTAssertTrue(port.isEnabled())
        XCTAssertEqual(lines, ["tap-disabled reason=userInput reenabled=1"])
    }

    /// The notice itself travels through the run loop the tap is on. When
    /// that loop is stuck, the notice does not arrive. The watchdog runs on
    /// its own queue and looks at the port directly.
    func testTheWatchdogTurnsOnATapThatWentOffWithoutANotice() {
        let port = FakePort(enabled: true)
        let tapGuard = TapGuard(port: port)
        XCTAssertFalse(tapGuard.check())
        XCTAssertEqual(port.enables, 0, "a healthy tap is left alone")

        port.switchOff()
        let lines = tapLines {
            XCTAssertTrue(tapGuard.check())
        }
        XCTAssertTrue(port.isEnabled())
        XCTAssertEqual(port.enables, 1)
        XCTAssertEqual(tapGuard.revivals, 1)
        XCTAssertEqual(lines, ["tap-disabled reason=watchdog reenabled=1"])

        XCTAssertFalse(tapGuard.check())
        XCTAssertEqual(port.enables, 1)
    }

    func testAPortThatRefusesIsReportedAndTriedAgain() {
        let port = FakePort(enabled: false)
        port.refuses = true
        let tapGuard = TapGuard(port: port)
        let lines = tapLines {
            XCTAssertTrue(tapGuard.check())
            XCTAssertTrue(tapGuard.check())
        }
        XCTAssertEqual(port.enables, 2)
        XCTAssertEqual(tapGuard.revivals, 0)
        XCTAssertEqual(lines, [
            "tap-disabled reason=watchdog reenabled=0",
            "tap-disabled reason=watchdog reenabled=0",
        ])
    }

    func testAReleasedGuardDoesNothing() {
        let port = FakePort(enabled: false)
        let tapGuard = TapGuard(port: port)
        tapGuard.release()
        XCTAssertFalse(tapGuard.check())
        tapGuard.disabled(.timeout)
        XCTAssertEqual(port.enables, 0, "an uninstalled tap must stay off")
        XCTAssertFalse(port.isEnabled())
    }

    func testManyThreadsCanAskAtOnce() {
        let port = FakePort(enabled: false)
        let tapGuard = TapGuard(port: port)
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            if index % 2 == 0 {
                tapGuard.disabled(.timeout)
            } else {
                _ = tapGuard.check()
            }
        }
        XCTAssertTrue(port.isEnabled())
        XCTAssertGreaterThanOrEqual(tapGuard.revivals, 1)
    }

    /// The hook thread must be the only thing the tap waits on.
    func testTheMacTapRunsOnItsOwnThreadAndIsWatched() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let text = try String(
            contentsOf: root.appendingPathComponent("Sources/SupervimSystem/CGEventTapSession.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("Thread {"), "the tap needs a run loop of its own")
        XCTAssertTrue(text.contains("CFRunLoopRun()"))
        XCTAssertTrue(text.contains("TapGuard("))
        XCTAssertTrue(text.contains("tapGuard.disabled("))
        XCTAssertTrue(text.contains("makeTimerSource"), "the watchdog must not depend on the tap's run loop")
        XCTAssertTrue(text.contains("CGEvent.tapIsEnabled"))
        XCTAssertFalse(text.contains("DispatchQueue.main"), "the tap must not wait for the main thread")
        XCTAssertFalse(text.contains("CFRunLoopGetMain"))
    }
}

private func tapLines(_ body: () -> Void) -> [String] {
    ModeTrace.capture(body).filter { $0.hasPrefix("tap-disabled") }
}

private final class FakePort: TapPortControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool
    private var count = 0
    var refuses = false

    init(enabled: Bool) {
        self.enabled = enabled
    }

    var enables: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func switchOff() {
        lock.lock()
        enabled = false
        lock.unlock()
    }

    func isEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    func enable() {
        lock.lock()
        count += 1
        if !refuses {
            enabled = true
        }
        lock.unlock()
    }
}

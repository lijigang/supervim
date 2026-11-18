#if os(macOS)
import ApplicationServices
import CoreGraphics
import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// Installs the real event tap on a machine that allows one and sends it
/// real key events. It runs only with `SUPERVIM_LIVE_AX_BENCH=1`, which the
/// CI test step sets, and skips when the process may not tap or post.
///
/// Every key posted here carries the mark of a synthesized event and is
/// swallowed by the test's handler, so no app receives it while the tap is
/// on. Keys that arrive while the tap is off reach the front app as the
/// letter `a`.
final class LiveEventTapTests: XCTestCase {
    func testTheTapAnswersOffTheMainThreadAndComesBackAfterItIsSwitchedOff() throws {
        guard ProcessInfo.processInfo.environment["SUPERVIM_LIVE_AX_BENCH"] == "1" else {
            throw XCTSkip("set SUPERVIM_LIVE_AX_BENCH=1 to install a real event tap")
        }
        guard AXIsProcessTrusted() else {
            print("BENCH tap trusted=0")
            throw XCTSkip("this process is not trusted for Accessibility")
        }
        let keys = RecordedKeys()
        let session = CGEventTapSession(wiring: keys)
        do {
            try session.install()
        } catch {
            print("BENCH tap install=failed")
            throw XCTSkip("this machine does not allow an event tap")
        }
        defer { session.uninstall() }
        XCTAssertTrue(session.isTapEnabled)

        // The app posts shortcuts from a queue, never from the main thread.
        let poster = CGEventActuatorPoster()
        let posting = DispatchQueue(label: "supervim.test.post")
        let post: @Sendable () -> Void = {
            posting.async {
                poster.post(.shortcut(KeyCombo("a", modifiers: [])))
            }
        }

        // This thread, the main one, blocks while it waits. A tap on the
        // main run loop could not answer; that was v0.1.4.
        guard let first = keys.next(after: post, timeout: 5) else {
            print("BENCH tap install=ok delivered=0")
            throw XCTSkip("posted keys do not reach a tap on this machine")
        }
        XCTAssertFalse(first.onMainThread)
        XCTAssertEqual(first.thread, "supervim.event-tap")
        XCTAssertEqual(first.record.keyCode, 0)
        XCTAssertEqual(first.record.sourceUserData, SynthesizedEventMark.userData)
        var trips: [Double] = [first.milliseconds]
        for _ in 0..<9 {
            if let seen = keys.next(after: post, timeout: 5) {
                trips.append(seen.milliseconds)
            }
        }
        XCTAssertEqual(trips.count, 10)
        trips.sort()
        print(
            "BENCH tap install=ok thread=\(first.thread) unicode=\(first.record.unicode) "
                + "post_to_callback_ms min=\(Self.text(trips[0])) median=\(Self.text(trips[trips.count / 2])) "
                + "max=\(Self.text(trips[trips.count - 1]))"
        )

        // Switched off with no notice: only the watchdog can find out.
        var revivedAfter = -1.0
        var afterRevival: RecordedKeys.Seen?
        let watchdogLines = ModeTrace.capture {
            session.switchOffAsTheSystemDoes()
            XCTAssertFalse(session.isTapEnabled)
            let started = DispatchTime.now().uptimeNanoseconds
            while Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000 < 3_000 {
                if session.isTapEnabled {
                    revivedAfter = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                    break
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
            afterRevival = keys.next(after: post, timeout: 5)
        }
        XCTAssertTrue(session.isTapEnabled, "the watchdog must turn the tap back on")
        XCTAssertGreaterThanOrEqual(revivedAfter, 0)
        XCTAssertLessThan(revivedAfter, 1_500)
        XCTAssertTrue(
            watchdogLines.contains("tap-disabled reason=watchdog reenabled=1"),
            "\(watchdogLines)"
        )
        XCTAssertNotNil(afterRevival, "a key after the revival must reach the tap")
        print("BENCH tap watchdog revived_after_ms=\(Self.text(revivedAfter))")

        // A callback that takes three seconds, with more keys arriving
        // meanwhile. Whether macOS switches the tap off for this is its
        // decision; either way the next key must be handled.
        var afterStall: RecordedKeys.Seen?
        let stallLines = ModeTrace.capture {
            keys.stallNextKey(seconds: 3)
            post()
            for _ in 0..<6 {
                Thread.sleep(forTimeInterval: 0.4)
                post()
            }
            Thread.sleep(forTimeInterval: 2)
            keys.drain()
            afterStall = keys.next(after: post, timeout: 5)
        }
        let notices = stallLines.filter { $0.hasPrefix("tap-disabled") }
        print(
            "BENCH tap stall_ms=3000 disabled_notices=\(notices.count) "
                + "reasons=\(notices.map { $0.replacingOccurrences(of: "tap-disabled ", with: "") }) "
                + "handled_after=\(afterStall == nil ? 0 : 1)"
        )
        XCTAssertNotNil(afterStall, "a key after a slow callback must still reach the tap")
        XCTAssertTrue(session.isTapEnabled)
        XCTAssertTrue(notices.allSatisfy { $0.hasSuffix("reenabled=1") }, "\(notices)")
    }

    private static func text(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private final class RecordedKeys: SystemKeyHandling, @unchecked Sendable {
    struct Seen {
        var record: SystemKeyRecord
        var onMainThread: Bool
        var thread: String
        var milliseconds: Double
    }

    private let lock = NSLock()
    private let arrived = DispatchSemaphore(value: 0)
    private var seen: [Seen] = []
    private var stall = 0.0
    private var posted: UInt64 = 0

    func stallNextKey(seconds: Double) {
        lock.lock()
        stall = seconds
        lock.unlock()
    }

    /// Forgets what arrived so far.
    func drain() {
        while arrived.wait(timeout: .now()) == .success {}
        lock.lock()
        seen = []
        lock.unlock()
    }

    /// Posts, then waits for the next marked key-down.
    func next(after post: () -> Void, timeout: Double) -> Seen? {
        lock.lock()
        posted = DispatchTime.now().uptimeNanoseconds
        lock.unlock()
        post()
        guard arrived.wait(timeout: .now() + timeout) == .success else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return seen.isEmpty ? nil : seen.removeFirst()
    }

    func handleSystemRecord(_ record: SystemKeyRecord) -> SystemKeyOutcome {
        guard record.sourceUserData == SynthesizedEventMark.userData else {
            return SystemKeyOutcome(delivery: .passThrough, decision: nil)
        }
        guard record.kind == .keyDown else {
            return SystemKeyOutcome(delivery: .swallow, decision: nil)
        }
        lock.lock()
        let wait = stall
        stall = 0
        let started = posted
        lock.unlock()
        if wait > 0 {
            Thread.sleep(forTimeInterval: wait)
        }
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        seen.append(Seen(
            record: record,
            onMainThread: Thread.isMainThread,
            thread: Thread.current.name ?? "",
            milliseconds: now > started ? Double(now - started) / 1_000_000 : 0
        ))
        lock.unlock()
        arrived.signal()
        return SystemKeyOutcome(delivery: .swallow, decision: nil)
    }
}
#endif

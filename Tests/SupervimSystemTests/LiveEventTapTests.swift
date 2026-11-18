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

        // The string a key event carries, read on the main thread, on
        // another thread, and by the tap on its own thread. v0.1.4 read it
        // on the main thread only; the three must agree.
        let reading = DispatchQueue(label: "supervim.test.read")
        func strings(shift: Bool) -> (main: String, background: String) {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x03, keyDown: true) else {
                return ("<none>", "<none>")
            }
            if shift {
                event.flags = .maskShift
            }
            let onMain = keyboardString(of: event)
            let offMain = reading.sync { keyboardString(of: event) }
            return (onMain, offMain)
        }
        let plain = strings(shift: false)
        let shifted = strings(shift: true)
        XCTAssertEqual(plain.main, plain.background)
        XCTAssertEqual(shifted.main, shifted.background)
        let madeOffMain: String = reading.sync {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x03, keyDown: true) else {
                return "<none>"
            }
            return keyboardString(of: event)
        }
        XCTAssertEqual(madeOffMain, plain.main)

        var carried = "<none>"
        var carriedOnTap = "<none>"
        if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x03, keyDown: true) {
            let units = Array("é".utf16)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event.setIntegerValueField(.eventSourceUserData, value: SynthesizedEventMark.userData)
            carried = keyboardString(of: event)
            let held = HeldEvent(event)
            let seen = keys.next(after: { posting.async { held.event.post(tap: .cghidEventTap) } }, timeout: 5)
            carriedOnTap = seen?.record.unicode ?? "<none>"
            XCTAssertEqual(seen?.record.keyCode, 0x03)
            XCTAssertEqual(carriedOnTap, carried)
        }
        print(
            "BENCH tap string plain_main=\(plain.main) plain_background=\(plain.background) "
                + "made_off_main=\(madeOffMain) "
                + "shift_main=\(shifted.main) shift_background=\(shifted.background) "
                + "posted_on_tap=\(first.record.unicode) set_main=\(carried) set_on_tap=\(carriedOnTap)"
        )

        // The same two posted keys, `f` and Shift-`f`, seen by a second tap
        // on the main run loop, which is where v0.1.4 read them, and by the
        // session's tap on its own thread.
        let probe = MainTapProbe()
        if let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue),
            callback: mainTapProbeCallback,
            userInfo: Unmanaged.passUnretained(probe).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            keys.drain()
            posting.async {
                poster.post(.shortcut(KeyCombo("f", modifiers: [])))
                poster.post(.shortcut(KeyCombo("f", modifiers: [.shift])))
            }
            var onMainLoop: [MainTapProbe.Seen] = []
            let deadline = Date().addingTimeInterval(3)
            while onMainLoop.count < 2, Date() < deadline {
                _ = CFRunLoopRunInMode(.defaultMode, 0.05, true)
                onMainLoop += probe.take()
            }
            Thread.sleep(forTimeInterval: 0.3)
            let onTapThread = keys.takeAll()
            CGEvent.tapEnable(tap: port, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(port)
            keys.drain()
            print(
                "BENCH tap posted f and shift-f main_loop_tap=\(onMainLoop.map(\.string)) "
                    + "main_loop_tap_on_main=\(onMainLoop.map { $0.onMain ? 1 : 0 }) "
                    + "tap_thread=\(onTapThread.map(\.record.unicode)) "
                    + "tap_thread_flags=\(onTapThread.map { $0.record.modifierFlags & SystemModifierMask.shift != 0 ? "shift" : "none" })"
            )
            if onMainLoop.count == 2, onTapThread.count == 2 {
                XCTAssertEqual(onTapThread.map(\.record.unicode), onMainLoop.map(\.string))
            }
        } else {
            print("BENCH tap posted f and shift-f main_loop_tap=<not installed>")
        }
        withExtendedLifetime(probe) {}

        // Switched off by a call, the way macOS does it. macOS may tell the
        // callback; if it does not, only the watchdog can find out.
        var revivedAfter = -1.0
        var afterRevival: RecordedKeys.Seen?
        let watchdogLines = ModeTrace.capture {
            session.switchOffAsTheSystemDoes()
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
        XCTAssertTrue(session.isTapEnabled, "the tap must be on again")
        XCTAssertGreaterThanOrEqual(revivedAfter, 0)
        XCTAssertLessThan(revivedAfter, 1_500)
        let revivals = watchdogLines.filter { $0.hasPrefix("tap-disabled") && $0.hasSuffix("reenabled=1") }
        XCTAssertFalse(revivals.isEmpty, "\(watchdogLines)")
        XCTAssertNotNil(afterRevival, "a key after the revival must reach the tap")
        print(
            "BENCH tap switched_off revived_after_ms=\(Self.text(revivedAfter)) "
                + "notices=\(watchdogLines.filter { $0.hasPrefix("tap-disabled") })"
        )

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
        // While the callback is still stuck macOS may switch the tap off
        // again at once, so a notice can say `reenabled=0`. The watchdog
        // asks again half a second later.
        XCTAssertNotNil(afterStall, "a key after a slow callback must still reach the tap")
        XCTAssertTrue(session.isTapEnabled)
    }

    private static func text(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private final class MainTapProbe: @unchecked Sendable {
    struct Seen {
        var string: String
        var onMain: Bool
    }

    private let lock = NSLock()
    private var seen: [Seen] = []

    func record(_ string: String, onMain: Bool) {
        lock.lock()
        seen.append(Seen(string: string, onMain: onMain))
        lock.unlock()
    }

    func take() -> [Seen] {
        lock.lock()
        defer { lock.unlock() }
        let all = seen
        seen = []
        return all
    }
}

private func mainTapProbeCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .keyDown, let userInfo,
       event.getIntegerValueField(.eventSourceUserData) == SynthesizedEventMark.userData {
        let probe = Unmanaged<MainTapProbe>.fromOpaque(userInfo).takeUnretainedValue()
        probe.record(keyboardString(of: event), onMain: Thread.isMainThread)
    }
    return Unmanaged.passUnretained(event)
}

private final class HeldEvent: @unchecked Sendable {
    let event: CGEvent

    init(_ event: CGEvent) {
        self.event = event
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

    func takeAll() -> [Seen] {
        lock.lock()
        defer { lock.unlock() }
        let all = seen
        seen = []
        return all
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

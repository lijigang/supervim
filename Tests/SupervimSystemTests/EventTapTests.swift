import XCTest
@testable import SupervimCore
@testable import SupervimSystem

#if os(macOS)
import CoreGraphics
#endif

/// The event hook reads a cached focus and returns a decision.
/// It must not scan, click, scroll, post a new event, or draw.
final class EventTapTests: XCTestCase {
    func testKeyDecisionUsesTheCacheAndDoesNotScan() {
        let fixture = makeWiring()
        fixture.cache.snapshot = CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.Safari")
        fixture.scanner.snapshot = CachedFocus(editability: .editable, bundleIdentifier: "com.example.Scanned")

        let decision = fixture.wiring.handleKeyDown(KeyEvent("j"))

        XCTAssertEqual(fixture.scanner.scans, 0)
        XCTAssertEqual(fixture.cache.reads, 1)
        XCTAssertEqual(decision.delivery, .swallow)
        XCTAssertEqual(decision.mode, .normal)
        XCTAssertEqual(decision.actions, [CommandMap().action(for: .scrollDown)])
        XCTAssertEqual(fixture.wiring.refreshFocus().bundleIdentifier, "com.example.Scanned")
        XCTAssertEqual(fixture.scanner.scans, 1)
    }

    func testPublishingTheCacheDoesNotScan() {
        let fixture = makeWiring()
        fixture.cache.snapshot = CachedFocus(editability: .editable, bundleIdentifier: "com.apple.Safari")
        let decision = fixture.wiring.publishCachedFocus()
        XCTAssertEqual(fixture.scanner.scans, 0)
        XCTAssertEqual(decision.mode, .insert)
        XCTAssertEqual(decision.delivery, .passThrough)
        XCTAssertTrue(decision.actions.isEmpty)
    }

    func testUnknownCachePassesTheKeyThroughTheWiring() {
        let fixture = makeWiring()
        fixture.cache.snapshot = CachedFocus(editability: .unknown, bundleIdentifier: "com.apple.Safari")
        let decision = fixture.wiring.handleKeyDown(KeyEvent("f"))
        XCTAssertEqual(fixture.scanner.scans, 0)
        XCTAssertEqual(decision.delivery, .passThrough)
        XCTAssertTrue(decision.actions.isEmpty)
        XCTAssertEqual(decision.mode, .normal)
    }

    func testExcludedCacheIsNotIntercepted() {
        let fixture = makeWiring()
        fixture.cache.snapshot = CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.Terminal")
        let decision = fixture.wiring.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(fixture.scanner.scans, 0)
        XCTAssertEqual(decision.delivery, .passThrough)
        XCTAssertTrue(decision.actions.isEmpty)
    }

    func testKeyUpFlagsAndOtherEventsDoNotReachTheParser() {
        let fixture = makeWiring(cache: safari)
        let first = fixture.wiring.handleSystemRecord(keyRecord(kind: .keyDown, keyCode: 0x05, unicode: "g"))
        XCTAssertEqual(first.delivery, .swallow)
        XCTAssertEqual(first.decision?.actions, [])
        let keyUp = fixture.wiring.handleSystemRecord(keyRecord(kind: .keyUp, keyCode: 0x05, unicode: "g"))
        XCTAssertEqual(keyUp, SystemKeyOutcome(delivery: .passThrough, decision: nil))
        XCTAssertEqual(
            fixture.wiring.handleSystemRecord(keyRecord(kind: .flagsChanged, keyCode: 0x05)),
            SystemKeyOutcome(delivery: .passThrough, decision: nil)
        )
        XCTAssertEqual(
            fixture.wiring.handleSystemRecord(keyRecord(kind: .other, keyCode: 0x05, unicode: "g")),
            SystemKeyOutcome(delivery: .passThrough, decision: nil)
        )
        XCTAssertEqual(fixture.scanner.scans, 0)
        let completed = fixture.wiring.handleSystemRecord(keyRecord(kind: .keyDown, keyCode: 0x05, unicode: "g"))
        XCTAssertEqual(completed.delivery, .swallow)
        XCTAssertEqual(completed.decision?.actions, [CommandMap().action(for: .scrollToTop)])
    }

    func testSystemRecordForJDecidesScrollAndDoesNotScan() {
        let fixture = makeWiring(cache: safari)
        let outcome = fixture.wiring.handleSystemRecord(keyRecord(keyCode: 0x00, unicode: "j"))
        XCTAssertEqual(fixture.scanner.scans, 0)
        XCTAssertEqual(outcome.delivery, .swallow)
        XCTAssertEqual(outcome.decision?.actions, [CommandMap().action(for: .scrollDown)])
        XCTAssertEqual(outcome.decision?.mode, .normal)
    }

    func testPauseRecordTogglesPauseAndDoesNotScan() {
        let fixture = makeWiring(cache: safari)
        let flags = SystemModifierMask.control | SystemModifierMask.option
        let first = fixture.wiring.handleSystemRecord(
            keyRecord(keyCode: 0x09, flags: flags, unicode: "√")
        )
        XCTAssertEqual(first.delivery, .swallow)
        XCTAssertEqual(first.decision?.mode, .paused)
        XCTAssertEqual(fixture.scanner.scans, 0)
        XCTAssertEqual(fixture.interpreter.mode, .paused)
        let passed = fixture.wiring.handleSystemRecord(keyRecord(keyCode: 0x26, unicode: "j"))
        XCTAssertEqual(passed.delivery, .passThrough)
        XCTAssertTrue(passed.decision?.actions.isEmpty == true)
        let resume = fixture.wiring.handleSystemRecord(keyRecord(keyCode: 0x09, flags: flags, unicode: ""))
        XCTAssertEqual(resume.delivery, .swallow)
        XCTAssertEqual(resume.decision?.mode, .normal)
    }

    func testQuestionMarkRecordOpensHelpWithoutDrawing() {
        let fixture = makeWiring(cache: safari)
        let outcome = fixture.wiring.handleSystemRecord(
            keyRecord(keyCode: 0x2C, flags: SystemModifierMask.shift, unicode: "?")
        )
        XCTAssertEqual(fixture.scanner.scans, 0)
        XCTAssertEqual(outcome.delivery, .swallow)
        XCTAssertEqual(outcome.decision?.actions, [.showHelp])
        XCTAssertEqual(outcome.decision?.overlay, .showHelp)
        XCTAssertEqual(outcome.decision?.mode, .normal)
    }

    func testControlBracketRecordPassesTheNextKey() {
        let fixture = makeWiring(cache: safari)
        let chord = fixture.wiring.handleSystemRecord(
            keyRecord(keyCode: 0x1E, flags: SystemModifierMask.control, unicode: "\u{1D}")
        )
        XCTAssertEqual(chord.delivery, .swallow)
        XCTAssertEqual(chord.decision?.actions, [.passNextKey])
        let passed = fixture.wiring.handleSystemRecord(keyRecord(keyCode: 0x26, unicode: "j"))
        XCTAssertEqual(passed.delivery, .passThrough)
        XCTAssertTrue(passed.decision?.actions.isEmpty == true)
        XCTAssertEqual(fixture.scanner.scans, 0)
        let scroll = fixture.wiring.handleSystemRecord(keyRecord(keyCode: 0x26, unicode: "j"))
        XCTAssertEqual(scroll.delivery, .swallow)
        XCTAssertEqual(scroll.decision?.actions, [CommandMap().action(for: .scrollDown)])
    }

    func testMarkedScrollKeyDoesNotScroll() {
        XCTAssertEqual(SynthesizedEventMark.userData, 0x5356_4D31)
        let fixture = makeWiring(cache: safari)
        let marked = fixture.wiring.handleSystemRecord(
            keyRecord(keyCode: 0x26, unicode: "j", sourceUserData: SynthesizedEventMark.userData)
        )
        XCTAssertEqual(marked, SystemKeyOutcome(delivery: .passThrough, decision: nil))
        XCTAssertEqual(fixture.scanner.scans, 0)
        let user = fixture.wiring.handleSystemRecord(keyRecord(keyCode: 0x26, unicode: "j"))
        XCTAssertEqual(user.delivery, .swallow)
        XCTAssertEqual(user.decision?.actions, [CommandMap().action(for: .scrollDown)])
    }

    func testMarkedKeyDoesNotConsumePassNext() {
        let fixture = makeWiring(cache: safari)
        let arm = fixture.wiring.handleSystemRecord(
            keyRecord(keyCode: 0x1E, flags: SystemModifierMask.control, unicode: "\u{1D}")
        )
        XCTAssertEqual(arm.decision?.actions, [.passNextKey])
        let marked = fixture.wiring.handleSystemRecord(
            keyRecord(keyCode: 0x26, unicode: "j", sourceUserData: SynthesizedEventMark.userData)
        )
        XCTAssertEqual(marked, SystemKeyOutcome(delivery: .passThrough, decision: nil))
        XCTAssertEqual(fixture.scanner.scans, 0)
        let stillArmed = fixture.wiring.handleSystemRecord(keyRecord(keyCode: 0x26, unicode: "j"))
        XCTAssertEqual(stillArmed.delivery, .passThrough)
        XCTAssertTrue(stillArmed.decision?.actions.isEmpty == true)
        let scroll = fixture.wiring.handleSystemRecord(keyRecord(keyCode: 0x26, unicode: "j"))
        XCTAssertEqual(scroll.delivery, .swallow)
        XCTAssertEqual(scroll.decision?.actions, [CommandMap().action(for: .scrollDown)])
    }

    func testPlainUnicodeWinsOverTheVirtualKeyCode() {
        let event = SystemKeyTranslation.keyEvent(from: keyRecord(keyCode: 0x00, unicode: "j"))
        XCTAssertEqual(event, KeyEvent("j"))
    }

    func testModifiedKeysUseTheUnshiftedVirtualKey() {
        let flags = SystemModifierMask.control | SystemModifierMask.option
        let event = SystemKeyTranslation.keyEvent(from: keyRecord(keyCode: 0x09, flags: flags, unicode: "√"))
        XCTAssertEqual(event, KeyEvent("v", modifiers: [.control, .option]))

        let shifted = SystemModifierMask.control | SystemModifierMask.option | SystemModifierMask.shift
        let shiftedEvent = SystemKeyTranslation.keyEvent(
            from: keyRecord(keyCode: 0x09, flags: shifted, unicode: "◊")
        )
        XCTAssertEqual(shiftedEvent, KeyEvent("v", modifiers: [.control, .option, .shift]))
    }

    func testOptionAloneDoesNotBecomeThePauseChord() {
        let event = SystemKeyTranslation.keyEvent(
            from: keyRecord(keyCode: 0x09, flags: SystemModifierMask.option, unicode: "√")
        )
        XCTAssertEqual(event, KeyEvent("v", modifiers: .option))
    }

    func testEscapeTranslation() {
        XCTAssertEqual(
            SystemKeyTranslation.keyEvent(from: keyRecord(keyCode: 0x35, unicode: "")),
            KeyEvent(identity: .escape)
        )
        XCTAssertEqual(
            SystemKeyTranslation.keyEvent(from: keyRecord(keyCode: 0x00, unicode: "\u{1B}")),
            KeyEvent(identity: .escape)
        )
        XCTAssertEqual(
            SystemKeyTranslation.keyEvent(
                from: keyRecord(keyCode: 0x35, flags: SystemModifierMask.command, unicode: "")
            ),
            KeyEvent(identity: .escape, modifiers: .command)
        )
    }

    func testIgnoredModifierBitsDoNotChangeTheKey() {
        let caps = UInt64(0x00010000)
        let fn = UInt64(0x00800000)
        let pad = UInt64(0x00200000)
        let event = SystemKeyTranslation.keyEvent(from: keyRecord(keyCode: 0x0C, flags: caps | fn | pad, unicode: "j"))
        XCTAssertEqual(event, KeyEvent("j"))
    }

    func testUnmappedModifiedKeyIsUnnamed() {
        let event = SystemKeyTranslation.keyEvent(
            from: keyRecord(keyCode: 0x7A, flags: SystemModifierMask.command, unicode: "")
        )
        XCTAssertEqual(event, KeyEvent(identity: .unnamed, modifiers: .command))
    }

    func testModifiedUnmappedKeyKeepsAPlainUnicodeCharacter() {
        let event = SystemKeyTranslation.keyEvent(
            from: keyRecord(keyCode: 0x7A, flags: SystemModifierMask.option, unicode: "ø")
        )
        XCTAssertEqual(event, KeyEvent("ø", modifiers: .option))
    }

    func testUnmappedPlainKeyIsUnnamed() {
        XCTAssertEqual(
            SystemKeyTranslation.keyEvent(from: keyRecord(keyCode: 0x7A, unicode: "")),
            KeyEvent(identity: .unnamed)
        )
    }

    func testUnshiftedVirtualKeyRoundTrip() {
        XCTAssertEqual(SystemKeyTranslation.virtualKeyCode(forUnshifted: "j"), 0x26)
        XCTAssertEqual(SystemKeyTranslation.virtualKeyCode(forUnshifted: "["), 0x21)
        XCTAssertEqual(SystemKeyTranslation.virtualKeyCode(forUnshifted: "]"), 0x1E)
        XCTAssertEqual(SystemKeyTranslation.virtualKeyCode(forUnshifted: "f"), 0x03)
        XCTAssertEqual(SystemKeyTranslation.virtualKeyCode(forUnshifted: "l"), 0x25)
        XCTAssertEqual(SystemKeyTranslation.virtualKeyCode(forUnshifted: "c"), 0x08)
        XCTAssertNil(SystemKeyTranslation.virtualKeyCode(forUnshifted: "J"))
        XCTAssertNil(SystemKeyTranslation.virtualKeyCode(forUnshifted: "é"))
    }

    func testMultiCharacterUnicodeFallsBackToTheVirtualKey() {
        let event = SystemKeyTranslation.keyEvent(from: keyRecord(keyCode: 0x26, unicode: "jj"))
        XCTAssertEqual(event, KeyEvent("j"))
    }

    func testControlCharacterUnicodeFallsBackToTheVirtualKey() {
        let event = SystemKeyTranslation.keyEvent(from: keyRecord(keyCode: 0x26, unicode: "\u{01}"))
        XCTAssertEqual(event, KeyEvent("j"))
    }

    func testKeyUpAndNonKeyDownDoNotBecomeKeyEvents() {
        XCTAssertNil(SystemKeyTranslation.keyEvent(from: keyRecord(kind: .keyUp, unicode: "j")))
        XCTAssertNil(SystemKeyTranslation.keyEvent(from: keyRecord(kind: .flagsChanged, unicode: "j")))
        XCTAssertNil(SystemKeyTranslation.keyEvent(from: keyRecord(kind: .other, unicode: "j")))
    }

    func testRightBracketWithControlIsThePassNextCharacter() {
        let event = SystemKeyTranslation.keyEvent(
            from: keyRecord(keyCode: 0x1E, flags: SystemModifierMask.control, unicode: "\u{1D}")
        )
        XCTAssertEqual(event, KeyEvent("]", modifiers: .control))
    }

    func testSystemClockIsMonotonicMilliseconds() {
        let clock = SystemKeyClock()
        let first = clock.nowMilliseconds()
        let wall = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        XCTAssertGreaterThan(first, 1_700_000_000_000)
        XCTAssertLessThan(abs(first - wall), 5_000)
        XCTAssertGreaterThanOrEqual(clock.nowMilliseconds(), first)
    }

    func testFakeInstallerIsNotRequiredForADecision() throws {
        let fixture = makeWiring(cache: safari)
        let installer = RecordingInstaller()
        try installer.install()
        let decision = fixture.wiring.handleKeyDown(KeyEvent("d"))
        installer.uninstall()
        XCTAssertEqual(installer.installs, 1)
        XCTAssertEqual(installer.removals, 1)
        XCTAssertEqual(fixture.scanner.scans, 0)
        XCTAssertEqual(decision.actions, [CommandMap().action(for: .scrollHalfPageDown)])
    }

    func testWiringSourceDoesNotPerformOrDraw() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimSystem/EventTap.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(text.components(separatedBy: "scanFocus(").count - 1, 2)
        for token in [
            "CGEvent.post",
            "AXUIElement",
            "URLSession",
            "os_log",
            "Logger(",
            "NSLog",
            "print(",
            ".perform(",
            "import AppKit",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
    }

    func testMacOSTapSourceInstallsATapAndDoesNotScanOrAct() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimSystem/CGEventTapSession.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("CGEvent.tapCreate"))
        XCTAssertTrue(text.contains("handleSystemRecord"))
        XCTAssertTrue(text.contains("eventSourceUserData"))
        for token in ["scanFocus(", "AXUIElement", "URLSession", "print(", "os_log", "NSLog", "CGEvent.post"] {
            XCTAssertFalse(text.contains(token), token)
        }
    }

    func testMenuBarPlaceholderDoesNotInstallTheTap() throws {
        let text = try appTargetSource()
        for token in ["CGEvent", "EventTap", "AXUIElement", "scanFocus("] {
            XCTAssertFalse(text.contains(token), token)
        }
    }

    #if os(macOS)
    func testModifierMasksMatchCoreGraphics() {
        XCTAssertEqual(SystemModifierMask.shift, CGEventFlags.maskShift.rawValue)
        XCTAssertEqual(SystemModifierMask.control, CGEventFlags.maskControl.rawValue)
        XCTAssertEqual(SystemModifierMask.option, CGEventFlags.maskAlternate.rawValue)
        XCTAssertEqual(SystemModifierMask.command, CGEventFlags.maskCommand.rawValue)
    }
    #endif
}

private let safari = CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.Safari")

private struct WiringFixture {
    var interpreter: EventInterpreter<ManualKeyClock>
    var cache: MemoryFocusCache
    var scanner: RecordingScanner
    var wiring: EventTapWiring
}

private func makeWiring(cache snapshot: CachedFocus = .unknown) -> WiringFixture {
    let clock = ManualKeyClock()
    let interpreter = EventInterpreter(clock: clock, cache: snapshot)
    let cache = MemoryFocusCache(snapshot: snapshot)
    let scanner = RecordingScanner()
    let wiring = EventTapWiring(decider: interpreter, cache: cache, scanner: scanner)
    return WiringFixture(interpreter: interpreter, cache: cache, scanner: scanner, wiring: wiring)
}

private func keyRecord(
    kind: SystemEventKind = .keyDown,
    keyCode: UInt16 = 0,
    flags: UInt64 = 0,
    unicode: String = "",
    sourceUserData: Int64 = 0
) -> SystemKeyRecord {
    SystemKeyRecord(
        kind: kind,
        keyCode: keyCode,
        modifierFlags: flags,
        unicode: unicode,
        sourceUserData: sourceUserData
    )
}

private final class MemoryFocusCache: FocusCacheReading, @unchecked Sendable {
    var snapshot: CachedFocus
    private(set) var reads = 0

    init(snapshot: CachedFocus) {
        self.snapshot = snapshot
    }

    func currentFocus() -> CachedFocus {
        reads += 1
        return snapshot
    }
}

private final class RecordingScanner: AccessibilityScanning, @unchecked Sendable {
    var snapshot = CachedFocus(editability: .editable, bundleIdentifier: "com.example.Scanned")
    private(set) var scans = 0

    func scanFocus() -> CachedFocus {
        scans += 1
        return snapshot
    }
}

private final class RecordingInstaller: EventTapInstalling, @unchecked Sendable {
    private(set) var installs = 0
    private(set) var removals = 0

    func install() throws {
        installs += 1
    }

    func uninstall() {
        removals += 1
    }
}

private func appTargetSource() throws -> String {
    let directory = repoRoot().appendingPathComponent("Sources/Supervim")
    let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
        .filter { $0.hasSuffix(".swift") }
    XCTAssertFalse(files.isEmpty)
    var text = ""
    for relative in files {
        text += try String(contentsOf: directory.appendingPathComponent(relative), encoding: .utf8)
    }
    return text
}

private func repoRoot(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

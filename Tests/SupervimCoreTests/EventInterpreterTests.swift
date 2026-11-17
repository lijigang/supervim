import XCTest
@testable import SupervimCore

/// Decision chain for one key: cached focus, ModeMachine, KeyParser, and CommandMap.
/// No accessibility walk, click, scroll, or overlay drawing happens here.
final class EventInterpreterTests: XCTestCase {
    func testFreshInterpreterPassesKeysUntilFocusAndAppAreKnown() {
        let ready = makeInterpreter()
        let decision = ready.interpreter.handleKeyDown(KeyEvent("j"), cache: .unknown)
        XCTAssertEqual(decision, passed(mode: .normal))
        XCTAssertEqual(ready.interpreter.mode, .normal)
    }

    func testUnknownEditabilityPassesKeysThatWouldOtherwiseBeCommands() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("j"), cache: unknownSafari),
            passed(mode: .normal)
        )
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("f"), cache: unknownSafari),
            passed(mode: .normal)
        )
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent(identity: .escape), cache: unknownSafari),
            passed(mode: .normal)
        )
        XCTAssertEqual(interpreter.handleKeyDown(pauseChord(), cache: unknownSafari), passed(mode: .normal))
        XCTAssertEqual(interpreter.mode, .normal)
    }

    func testExcludedAppsPassKeysIncludingThePauseChord() {
        let interpreter = makeInterpreter().interpreter
        for bundle in Settings.defaultExcludedBundleIdentifiers + ["", "   ", "\n"] {
            let cache = CachedFocus(editability: .notEditable, bundleIdentifier: bundle)
            XCTAssertEqual(
                interpreter.handleKeyDown(KeyEvent("j"), cache: cache),
                passed(mode: .normal),
                bundle
            )
            XCTAssertEqual(interpreter.handleKeyDown(pauseChord(), cache: cache), passed(mode: .normal), bundle)
            XCTAssertEqual(interpreter.mode, .normal, bundle)
        }
    }

    func testBundleComparisonUsesSettingsAndIsCaseSensitive() {
        let interpreter = makeInterpreter().interpreter
        let lowercased = CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.terminal")
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: lowercased), scrollDown())

        var settings = Settings.defaults
        settings.excludedBundleIdentifiers = []
        interpreter.replaceSettings(settings)
        let terminal = CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.Terminal")
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: terminal), scrollDown())
    }

    func testSavedPauseFlagStartsTheMachinePaused() {
        var settings = Settings.defaults
        settings.isPaused = true
        let interpreter = makeInterpreter(settings: settings).interpreter
        XCTAssertEqual(interpreter.mode, .paused)
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), passed(mode: .paused))
    }

    func testSavedPauseOnAnEditableFieldResumesToInsert() {
        var settings = Settings.defaults
        settings.isPaused = true
        let interpreter = makeInterpreter(settings: settings, cache: editableSafari).interpreter
        XCTAssertEqual(interpreter.mode, .paused)
        XCTAssertEqual(
            interpreter.handleKeyDown(pauseChord(), cache: editableSafari),
            EventDecision(delivery: .swallow, mode: .insert)
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: editableSafari), passed(mode: .insert))
    }

    func testDefaultPauseShortcutTogglesPauseOutsideTheParser() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(
            interpreter.handleKeyDown(pauseChord(), cache: safari),
            EventDecision(delivery: .swallow, mode: .paused)
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), passed(mode: .paused))
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("g"), cache: safari), passed(mode: .paused))
        XCTAssertEqual(
            interpreter.handleKeyDown(pauseChord(), cache: safari),
            EventDecision(delivery: .swallow, mode: .normal)
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), scrollDown())
    }

    func testPauseRequiresTheExactShortcut() {
        let interpreter = makeInterpreter().interpreter
        let shifted = KeyEvent("v", modifiers: [.control, .option, .shift])
        XCTAssertEqual(interpreter.handleKeyDown(shifted, cache: safari), passed(mode: .normal))
        let uppercase = KeyEvent("V", modifiers: [.control, .option])
        XCTAssertEqual(interpreter.handleKeyDown(uppercase, cache: safari), passed(mode: .normal))
        XCTAssertEqual(interpreter.mode, .normal)
    }

    func testCustomPauseShortcutComesFromSettings() {
        let ready = makeInterpreter()
        var settings = Settings.defaults
        settings.pauseShortcut = PauseShortcut(key: "x", modifiers: [.control, .command])
        ready.interpreter.replaceSettings(settings)
        XCTAssertEqual(ready.interpreter.handleKeyDown(pauseChord(), cache: safari), passed(mode: .normal))
        let custom = KeyEvent("x", modifiers: [.control, .command])
        XCTAssertEqual(
            ready.interpreter.handleKeyDown(custom, cache: safari),
            EventDecision(delivery: .swallow, mode: .paused)
        )
    }

    func testPauseFromHintEndsTheHintAndResumeDoesNotRestoreIt() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("f"), cache: safari), plainHint())
        XCTAssertEqual(
            interpreter.handleKeyDown(pauseChord(), cache: safari),
            EventDecision(
                delivery: .swallow,
                mode: .paused,
                overlay: .endHint,
                modeEffects: [.endHint]
            )
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), passed(mode: .paused))
        XCTAssertEqual(
            interpreter.handleKeyDown(pauseChord(), cache: safari),
            EventDecision(delivery: .swallow, mode: .normal)
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), scrollDown())
    }

    func testPauseFromManualInsertResumesManualInsert() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("i"), cache: safari), enteredInsert())
        XCTAssertEqual(
            interpreter.handleKeyDown(pauseChord(), cache: safari),
            EventDecision(delivery: .swallow, mode: .paused)
        )
        XCTAssertEqual(
            interpreter.handleKeyDown(pauseChord(), cache: safari),
            EventDecision(delivery: .swallow, mode: .insert)
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), passed(mode: .insert))
    }

    func testPauseFromAutomaticInsertFollowsTheCachedFocus() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(interpreter.updateCache(editableSafari).mode, .insert)
        XCTAssertEqual(
            interpreter.handleKeyDown(pauseChord(), cache: editableSafari),
            EventDecision(delivery: .swallow, mode: .paused)
        )
        XCTAssertEqual(
            interpreter.updateCache(safari),
            EventDecision(delivery: .passThrough, mode: .paused)
        )
        XCTAssertEqual(
            interpreter.handleKeyDown(pauseChord(), cache: safari),
            EventDecision(delivery: .swallow, mode: .normal)
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), scrollDown())
    }

    func testUnknownNormalKeyPassesThrough() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("q"), cache: safari), passed(mode: .normal))
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("z"), cache: safari), passed(mode: .normal))
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent(identity: .unnamed), cache: safari),
            passed(mode: .normal)
        )
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("j", modifiers: .command), cache: safari),
            passed(mode: .normal)
        )
    }

    func testEveryDefaultBindingReachesTheCommandMapAction() {
        let map = CommandMap()
        for binding in map.bindings where binding.keys != "Esc" && binding.keys != "Ctrl+]" {
            let interpreter = makeInterpreter().interpreter
            var decision = passed(mode: .normal)
            for character in binding.keys {
                decision = interpreter.handleKeyDown(KeyEvent(character), cache: safari)
            }
            XCTAssertEqual(decision.delivery, .swallow, binding.keys)
            XCTAssertEqual(decision.actions, [binding.action], binding.keys)
        }
    }

    func testEscapeInNormalPassesThrough() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(
            CommandMap().disposition(for: .command(.escape)),
            .perform(.escape)
        )
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent(identity: .escape), cache: safari),
            passed(mode: .normal)
        )
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("\u{1B}"), cache: safari),
            passed(mode: .normal)
        )
    }

    func testHeldPrefixIsSwallowedAndAFailedSecondKeyIsReparsed() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("g"), cache: safari),
            EventDecision(delivery: .swallow, mode: .normal)
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("x"), cache: safari), closeTab())
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("g"), cache: safari),
            EventDecision(delivery: .swallow, mode: .normal)
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("z"), cache: safari), passed(mode: .normal))
    }

    func testPrefixTimeoutUsesTheSettingsValue() {
        var settings = Settings.defaults
        settings.keySequenceTimeoutMilliseconds = 40
        let ready = makeInterpreter(settings: settings)
        XCTAssertEqual(
            ready.interpreter.handleKeyDown(KeyEvent("g"), cache: safari),
            EventDecision(delivery: .swallow, mode: .normal)
        )
        ready.clock.advance(by: 39)
        XCTAssertEqual(
            ready.interpreter.handleKeyDown(KeyEvent("g"), cache: safari),
            scrollToTop()
        )

        XCTAssertEqual(
            ready.interpreter.handleKeyDown(KeyEvent("g"), cache: safari),
            EventDecision(delivery: .swallow, mode: .normal)
        )
        ready.clock.advance(by: 40)
        XCTAssertEqual(
            ready.interpreter.handleKeyDown(KeyEvent("g"), cache: safari),
            EventDecision(delivery: .swallow, mode: .normal)
        )
    }

    func testReplacingSettingsDropsAPendingPrefixWhenTheTimeoutChanges() {
        let ready = makeInterpreter()
        _ = ready.interpreter.handleKeyDown(KeyEvent("g"), cache: safari)
        var settings = Settings.defaults
        settings.keySequenceTimeoutMilliseconds = 25
        ready.interpreter.replaceSettings(settings)
        ready.clock.advance(by: 25)
        XCTAssertEqual(
            ready.interpreter.handleKeyDown(KeyEvent("g"), cache: safari),
            EventDecision(delivery: .swallow, mode: .normal)
        )
    }

    func testReplacingSettingsKeepsPassNextWhenTheTimeoutIsUnchanged() {
        let interpreter = makeInterpreter().interpreter
        let chord = KeyEvent("]", modifiers: .control)
        XCTAssertEqual(interpreter.handleKeyDown(chord, cache: safari), passNext())
        var settings = Settings.defaults
        settings.pauseShortcut = PauseShortcut(key: "x", modifiers: [.control, .command])
        interpreter.replaceSettings(settings)
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), passed(mode: .normal))
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), scrollDown())
    }

    func testPassNextKeyIsSwallowedAndTheFollowingKeyIsDelivered() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("]", modifiers: .control), cache: safari),
            passNext()
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), passed(mode: .normal))
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent(identity: .escape), cache: safari), passed(mode: .normal))
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), scrollDown())
    }

    func testPauseClearsAPendingPrefixAndPassNext() {
        let interpreter = makeInterpreter().interpreter
        _ = interpreter.handleKeyDown(KeyEvent("g"), cache: safari)
        _ = interpreter.handleKeyDown(pauseChord(), cache: safari)
        _ = interpreter.handleKeyDown(pauseChord(), cache: safari)
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("g"), cache: safari),
            EventDecision(delivery: .swallow, mode: .normal)
        )

        _ = interpreter.handleKeyDown(KeyEvent("]", modifiers: .control), cache: safari)
        _ = interpreter.handleKeyDown(pauseChord(), cache: safari)
        _ = interpreter.handleKeyDown(pauseChord(), cache: safari)
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), scrollDown())
    }

    func testLeavingNormalDropsAPendingPrefix() {
        let interpreter = makeInterpreter().interpreter
        _ = interpreter.handleKeyDown(KeyEvent("g"), cache: safari)
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("g"), cache: unknownSafari), passed(mode: .normal))
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("g"), cache: safari),
            EventDecision(delivery: .swallow, mode: .normal)
        )

        _ = interpreter.handleKeyDown(KeyEvent("y"), cache: safari)
        let terminal = CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.Terminal")
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("y"), cache: terminal), passed(mode: .normal))
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("y"), cache: safari),
            EventDecision(delivery: .swallow, mode: .normal)
        )
    }

    func testFocusFirstInputDoesNotEnterInsertByItself() {
        let interpreter = makeInterpreter().interpreter
        _ = interpreter.handleKeyDown(KeyEvent("g"), cache: safari)
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("i"), cache: safari),
            EventDecision(
                delivery: .swallow,
                mode: .normal,
                actions: [CommandMap().action(for: .focusFirstInput)]
            )
        )
        XCTAssertEqual(interpreter.mode, .normal)
    }

    func testCopyURLStaysADecidedSequence() {
        let interpreter = makeInterpreter().interpreter
        _ = interpreter.handleKeyDown(KeyEvent("y"), cache: safari)
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("y"), cache: safari),
            EventDecision(
                delivery: .swallow,
                mode: .normal,
                actions: [CommandMap().action(for: .copyURL)]
            )
        )
    }

    func testPlainHintOwnsLaterKeysUntilEscape() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("f"), cache: safari), plainHint())
        let hintKey = KeyEvent("j")
        XCTAssertEqual(
            interpreter.handleKeyDown(hintKey, cache: safari),
            EventDecision(
                delivery: .swallow,
                mode: .hint(.plain),
                overlay: .hintKey(hintKey),
                modeEffects: [.swallowKey]
            )
        )
        let chord = KeyEvent("c", modifiers: .command)
        XCTAssertEqual(
            interpreter.handleKeyDown(chord, cache: safari),
            EventDecision(
                delivery: .swallow,
                mode: .hint(.plain),
                overlay: .hintKey(chord),
                modeEffects: [.swallowKey]
            )
        )
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent(identity: .escape), cache: safari),
            EventDecision(
                delivery: .swallow,
                mode: .normal,
                overlay: .endHint,
                modeEffects: [.swallowKey, .endHint]
            )
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), scrollDown())
    }

    func testCommandHintUsesTheCommandClickAction() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("F"), cache: safari),
            EventDecision(
                delivery: .swallow,
                mode: .hint(.command),
                actions: [.beginHint(.command)],
                overlay: .beginHint(.command),
                modeEffects: [.swallowKey, .beginHint(.command)]
            )
        )
    }

    func testEditableFocusEndsHintAndThenPassesTheKey() {
        let interpreter = makeInterpreter().interpreter
        _ = interpreter.handleKeyDown(KeyEvent("f"), cache: safari)
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("s"), cache: editableSafari),
            EventDecision(
                delivery: .passThrough,
                mode: .insert,
                overlay: .endHint,
                modeEffects: [.endHint, .passKeyThrough]
            )
        )
    }

    func testHelpIsAnOverlayUpdateWithoutASecondToggle() {
        let interpreter = makeInterpreter().interpreter
        let help = EventDecision(
            delivery: .swallow,
            mode: .normal,
            actions: [.showHelp],
            overlay: .showHelp
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("?"), cache: safari), help)
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("?"), cache: safari), help)
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), scrollDown())
    }

    func testManualInsertPassesTextAndEscapeAsksToBlur() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("i"), cache: safari), enteredInsert())
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), passed(mode: .insert))
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("f"), cache: safari), passed(mode: .insert))
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent(identity: .escape), cache: safari),
            EventDecision(
                delivery: .swallow,
                mode: .normal,
                modeEffects: [.swallowKey, .blurFocus]
            )
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), scrollDown())
    }

    func testEscapeFromAutomaticInsertPassesKeysWhileTheFieldStillLooksEditable() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(
            interpreter.updateCache(editableSafari),
            EventDecision(delivery: .passThrough, mode: .insert)
        )
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent(identity: .escape), cache: editableSafari),
            EventDecision(
                delivery: .swallow,
                mode: .normal,
                modeEffects: [.swallowKey, .blurFocus]
            )
        )
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("j"), cache: editableSafari),
            passed(mode: .insert)
        )
        XCTAssertEqual(interpreter.updateCache(safari), EventDecision(delivery: .passThrough, mode: .normal))
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), scrollDown())
    }

    func testEscapeCharacterAlsoLeavesInsert() {
        let interpreter = makeInterpreter().interpreter
        _ = interpreter.handleKeyDown(KeyEvent("i"), cache: safari)
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("\u{1B}"), cache: safari),
            EventDecision(
                delivery: .swallow,
                mode: .normal,
                modeEffects: [.swallowKey, .blurFocus]
            )
        )
    }

    func testModifiedEscapeInInsertIsTextAndDoesNotBlur() {
        let interpreter = makeInterpreter().interpreter
        _ = interpreter.handleKeyDown(KeyEvent("i"), cache: safari)
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent(identity: .escape, modifiers: .command), cache: safari),
            passed(mode: .insert)
        )
    }

    func testUnknownFocusInsideInsertDoesNotBlur() {
        let interpreter = makeInterpreter().interpreter
        XCTAssertEqual(
            interpreter.updateCache(editableSafari),
            EventDecision(delivery: .passThrough, mode: .insert)
        )
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent(identity: .escape), cache: unknownSafari),
            EventDecision(delivery: .passThrough, mode: .insert, modeEffects: [.passKeyThrough])
        )
        XCTAssertFalse(
            interpreter.handleKeyDown(KeyEvent("a"), cache: unknownSafari).modeEffects.contains(.blurFocus)
        )
    }

    func testManualInsertSurvivesANotEditableCache() {
        let interpreter = makeInterpreter().interpreter
        _ = interpreter.handleKeyDown(KeyEvent("i"), cache: safari)
        XCTAssertEqual(
            interpreter.updateCache(safari),
            EventDecision(delivery: .passThrough, mode: .insert)
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), passed(mode: .insert))
    }

    func testAutomaticInsertReturnsToNormalWhenTheFieldGoesAway() {
        let interpreter = makeInterpreter().interpreter
        _ = interpreter.updateCache(editableSafari)
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("a"), cache: editableSafari), passed(mode: .insert))
        XCTAssertEqual(interpreter.updateCache(safari), EventDecision(delivery: .passThrough, mode: .normal))
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: safari), scrollDown())
    }

    func testCacheUpdateCanEndHintWithoutAKeyAndWithoutACommand() {
        let interpreter = makeInterpreter().interpreter
        _ = interpreter.handleKeyDown(KeyEvent("f"), cache: safari)
        XCTAssertEqual(
            interpreter.updateCache(unknownSafari),
            EventDecision(
                delivery: .passThrough,
                mode: .normal,
                overlay: .endHint,
                modeEffects: [.endHint]
            )
        )
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: unknownSafari), passed(mode: .normal))
    }

    func testSwitchingToAnExcludedAppEndsHint() {
        let interpreter = makeInterpreter().interpreter
        _ = interpreter.handleKeyDown(KeyEvent("F"), cache: safari)
        let terminal = CachedFocus(editability: .notEditable, bundleIdentifier: "com.googlecode.iterm2")
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("s"), cache: terminal),
            EventDecision(
                delivery: .passThrough,
                mode: .normal,
                overlay: .endHint,
                modeEffects: [.endHint, .passKeyThrough]
            )
        )
    }

    func testReturningFromExclusionWithAnEditableFieldEntersInsert() {
        let interpreter = makeInterpreter().interpreter
        let terminal = CachedFocus(editability: .notEditable, bundleIdentifier: "org.gnu.Emacs")
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("j"), cache: terminal), passed(mode: .normal))
        XCTAssertEqual(
            interpreter.handleKeyDown(KeyEvent("j"), cache: editableSafari),
            passed(mode: .insert)
        )
    }

    func testSameCacheTwiceDoesNotRestartHintOrInsert() {
        let interpreter = makeInterpreter().interpreter
        _ = interpreter.handleKeyDown(KeyEvent("f"), cache: safari)
        XCTAssertEqual(
            interpreter.updateCache(safari),
            EventDecision(delivery: .passThrough, mode: .hint(.plain))
        )
        _ = interpreter.handleKeyDown(KeyEvent(identity: .escape), cache: safari)
        _ = interpreter.updateCache(editableSafari)
        XCTAssertEqual(
            interpreter.updateCache(editableSafari),
            EventDecision(delivery: .passThrough, mode: .insert)
        )
    }

    func testGThenFStartsHintAfterThePrefixIsCancelled() {
        let interpreter = makeInterpreter().interpreter
        _ = interpreter.handleKeyDown(KeyEvent("g"), cache: safari)
        XCTAssertEqual(interpreter.handleKeyDown(KeyEvent("f"), cache: safari), plainHint())
    }

    func testInterpreterSourceDoesNotTouchTheSystemOrRecordKeys() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimCore/EventInterpreter.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        for token in [
            "import AppKit",
            "import CoreGraphics",
            "import Accessibility",
            "AXUIElement",
            "CGEvent",
            "URLSession",
            "os_log",
            "Logger(",
            "NSLog",
            "print(",
            "scanFocus(",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
    }
}

private let safari = CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.Safari")
private let editableSafari = CachedFocus(editability: .editable, bundleIdentifier: "com.apple.Safari")
private let unknownSafari = CachedFocus(editability: .unknown, bundleIdentifier: "com.apple.Safari")

private struct InterpreterFixture {
    var clock: ManualKeyClock
    var interpreter: EventInterpreter<ManualKeyClock>
}

private func makeInterpreter(
    settings: Settings = .defaults,
    cache: CachedFocus = safari
) -> InterpreterFixture {
    let clock = ManualKeyClock()
    return InterpreterFixture(
        clock: clock,
        interpreter: EventInterpreter(settings: settings, clock: clock, cache: cache)
    )
}

private func pauseChord() -> KeyEvent {
    KeyEvent("v", modifiers: [.control, .option])
}

private func passed(mode: SupervimMode) -> EventDecision {
    EventDecision(delivery: .passThrough, mode: mode, modeEffects: [.passKeyThrough])
}

private func scrollDown() -> EventDecision {
    EventDecision(
        delivery: .swallow,
        mode: .normal,
        actions: [CommandMap().action(for: .scrollDown)]
    )
}

private func scrollToTop() -> EventDecision {
    EventDecision(
        delivery: .swallow,
        mode: .normal,
        actions: [CommandMap().action(for: .scrollToTop)]
    )
}

private func closeTab() -> EventDecision {
    EventDecision(
        delivery: .swallow,
        mode: .normal,
        actions: [CommandMap().action(for: .close)]
    )
}

private func passNext() -> EventDecision {
    EventDecision(
        delivery: .swallow,
        mode: .normal,
        actions: [.passNextKey]
    )
}

private func plainHint() -> EventDecision {
    EventDecision(
        delivery: .swallow,
        mode: .hint(.plain),
        actions: [.beginHint(.plain)],
        overlay: .beginHint(.plain),
        modeEffects: [.swallowKey, .beginHint(.plain)]
    )
}

private func enteredInsert() -> EventDecision {
    EventDecision(
        delivery: .swallow,
        mode: .insert,
        actions: [.enterInsert],
        modeEffects: [.swallowKey]
    )
}

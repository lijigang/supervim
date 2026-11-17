import XCTest
@testable import SupervimCore

/// Behavior contract for the pure mode machine.
/// Keys arrive already classified. Sequence parsing, hint alphabets, and
/// system adapters are later tasks. These tests lock the transitions those
/// tasks will drive.
final class ModeMachineTests: XCTestCase {
    func testDefaultModeIsNormal() {
        XCTAssertEqual(ModeMachine().mode, .normal)
    }

    func testUnknownFocusPassesEveryKey() {
        var machine = ModeMachine()
        assertStep(&machine, .key(.other), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .key(.manualInsert), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .key(.hint(.plain)), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .key(.hint(.command)), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .key(.escape), mode: .normal, effects: [.passKeyThrough])
    }

    func testEditableFocusFromNormalEntersInsert() {
        var machine = ModeMachine()
        assertStep(&machine, .focus(.editable), mode: .insert, effects: [])
    }

    func testAutomaticInsertPassesTextKeys() {
        var machine = ModeMachine()
        _ = machine.handle(.focus(.editable))
        assertStep(&machine, .key(.other), mode: .insert, effects: [.passKeyThrough])
        assertStep(&machine, .key(.manualInsert), mode: .insert, effects: [.passKeyThrough])
        assertStep(&machine, .key(.hint(.plain)), mode: .insert, effects: [.passKeyThrough])
        assertStep(&machine, .key(.hint(.command)), mode: .insert, effects: [.passKeyThrough])
    }

    func testEscapeInInsertSwallowsTheKeyAndAsksToBlurFocus() {
        var machine = ModeMachine()
        _ = machine.handle(.focus(.editable))
        assertStep(&machine, .key(.escape), mode: .normal, effects: [.swallowKey, .blurFocus])
    }

    func testAfterBlurRequestKeysPassUntilFocusIsKnownAgain() {
        var machine = ModeMachine()
        _ = machine.handle(.focus(.editable))
        _ = machine.handle(.key(.escape))
        assertStep(&machine, .key(.hint(.plain)), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .key(.manualInsert), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .focus(.notEditable), mode: .normal, effects: [])
        assertStep(
            &machine,
            .key(.hint(.plain)),
            mode: .hint(.plain),
            effects: [.swallowKey, .beginHint(.plain)]
        )
    }

    func testKnownEditableFocusRestoresInsertEscape() {
        var machine = ModeMachine()
        _ = machine.handle(.focus(.editable))
        _ = machine.handle(.focus(.unknown))
        _ = machine.handle(.focus(.editable))
        assertStep(&machine, .key(.escape), mode: .normal, effects: [.swallowKey, .blurFocus])
    }

    func testManualInsertFromNormalSwallowsI() {
        var machine = armedNormal()
        assertStep(&machine, .key(.manualInsert), mode: .insert, effects: [.swallowKey])
        assertStep(&machine, .key(.other), mode: .insert, effects: [.passKeyThrough])
    }

    func testManualInsertSurvivesANotEditableFocusReport() {
        var machine = armedNormal()
        _ = machine.handle(.key(.manualInsert))
        assertStep(&machine, .focus(.notEditable), mode: .insert, effects: [])
        assertStep(&machine, .key(.hint(.plain)), mode: .insert, effects: [.passKeyThrough])
    }

    func testEscapeLeavesManualInsertOverANonEditableSurface() {
        var machine = armedNormal()
        _ = machine.handle(.key(.manualInsert))
        assertStep(&machine, .key(.escape), mode: .normal, effects: [.swallowKey, .blurFocus])
        assertStep(
            &machine,
            .key(.hint(.plain)),
            mode: .hint(.plain),
            effects: [.swallowKey, .beginHint(.plain)]
        )
    }

    func testEditableFocusAnchorsInsertSoLeavingTheFieldReturnsToNormal() {
        var machine = armedNormal()
        _ = machine.handle(.key(.manualInsert))
        assertStep(&machine, .focus(.editable), mode: .insert, effects: [])
        assertStep(&machine, .focus(.notEditable), mode: .normal, effects: [])
    }

    func testAutomaticInsertEndsWhenFocusIsNoLongerEditable() {
        var machine = ModeMachine()
        _ = machine.handle(.focus(.editable))
        assertStep(&machine, .focus(.notEditable), mode: .normal, effects: [])
        assertStep(
            &machine,
            .key(.hint(.command)),
            mode: .hint(.command),
            effects: [.swallowKey, .beginHint(.command)]
        )
    }

    func testUnknownFocusSuppressesInsertEscape() {
        var machine = ModeMachine()
        _ = machine.handle(.focus(.editable))
        assertStep(&machine, .focus(.unknown), mode: .insert, effects: [])
        assertStep(&machine, .key(.escape), mode: .insert, effects: [.passKeyThrough])
        assertStep(&machine, .key(.other), mode: .insert, effects: [.passKeyThrough])
    }

    func testPlainHintRemembersAPlainClick() {
        var machine = armedNormal()
        assertStep(
            &machine,
            .key(.hint(.plain)),
            mode: .hint(.plain),
            effects: [.swallowKey, .beginHint(.plain)]
        )
    }

    func testCommandHintRemembersACommandClick() {
        var machine = armedNormal()
        assertStep(
            &machine,
            .key(.hint(.command)),
            mode: .hint(.command),
            effects: [.swallowKey, .beginHint(.command)]
        )
    }

    func testHintCompletedReturnsToNormal() {
        var machine = armedNormal()
        _ = machine.handle(.key(.hint(.plain)))
        assertStep(&machine, .hintCompleted, mode: .normal, effects: [.endHint])
        assertStep(&machine, .key(.manualInsert), mode: .insert, effects: [.swallowKey])
    }

    func testHintCancelledReturnsToNormal() {
        var machine = armedNormal()
        _ = machine.handle(.key(.hint(.command)))
        assertStep(&machine, .hintCancelled, mode: .normal, effects: [.endHint])
    }

    func testEscapeCancelsHintWithoutBlurring() {
        var machine = armedNormal()
        _ = machine.handle(.key(.hint(.plain)))
        assertStep(&machine, .key(.escape), mode: .normal, effects: [.swallowKey, .endHint])
        assertStep(
            &machine,
            .key(.hint(.command)),
            mode: .hint(.command),
            effects: [.swallowKey, .beginHint(.command)]
        )
    }

    func testNonEscapeKeysStayInsideTheSameHint() {
        var machine = armedNormal()
        _ = machine.handle(.key(.hint(.command)))
        assertStep(&machine, .key(.other), mode: .hint(.command), effects: [.swallowKey])
        assertStep(&machine, .key(.manualInsert), mode: .hint(.command), effects: [.swallowKey])
        assertStep(&machine, .key(.hint(.plain)), mode: .hint(.command), effects: [.swallowKey])
    }

    func testHintResolutionOutsideHintDoesNothing() {
        var machine = armedNormal()
        assertStep(&machine, .hintCompleted, mode: .normal, effects: [])
        assertStep(&machine, .hintCancelled, mode: .normal, effects: [])
        _ = machine.handle(.focus(.editable))
        assertStep(&machine, .hintCompleted, mode: .insert, effects: [])
        assertStep(&machine, .hintCancelled, mode: .insert, effects: [])
    }

    func testEditableFocusDuringHintCancelsHintAndEntersInsert() {
        var machine = armedNormal()
        _ = machine.handle(.key(.hint(.plain)))
        assertStep(&machine, .focus(.editable), mode: .insert, effects: [.endHint])
        assertStep(&machine, .key(.other), mode: .insert, effects: [.passKeyThrough])
    }

    func testUnknownFocusDuringHintCancelsHintAndPassesKeys() {
        var machine = armedNormal()
        _ = machine.handle(.key(.hint(.command)))
        assertStep(&machine, .focus(.unknown), mode: .normal, effects: [.endHint])
        assertStep(&machine, .key(.hint(.plain)), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .key(.escape), mode: .normal, effects: [.passKeyThrough])
    }

    func testNotEditableFocusDuringHintKeepsTheHint() {
        var machine = armedNormal()
        _ = machine.handle(.key(.hint(.plain)))
        assertStep(&machine, .focus(.notEditable), mode: .hint(.plain), effects: [])
        assertStep(&machine, .key(.other), mode: .hint(.plain), effects: [.swallowKey])
    }

    func testEscapeInNormalPassesThrough() {
        var machine = armedNormal()
        assertStep(&machine, .key(.escape), mode: .normal, effects: [.passKeyThrough])
    }

    func testUnrecognizedKeyInNormalPassesThrough() {
        var machine = armedNormal()
        assertStep(&machine, .key(.other), mode: .normal, effects: [.passKeyThrough])
    }

    func testPauseFromNormalPassesKeysAndResumeRestoresCommands() {
        var machine = armedNormal()
        assertStep(&machine, .togglePause, mode: .paused, effects: [])
        assertStep(&machine, .key(.hint(.plain)), mode: .paused, effects: [.passKeyThrough])
        assertStep(&machine, .key(.escape), mode: .paused, effects: [.passKeyThrough])
        assertStep(&machine, .key(.manualInsert), mode: .paused, effects: [.passKeyThrough])
        assertStep(&machine, .togglePause, mode: .normal, effects: [])
        assertStep(
            &machine,
            .key(.hint(.plain)),
            mode: .hint(.plain),
            effects: [.swallowKey, .beginHint(.plain)]
        )
    }

    func testPauseFromAutomaticInsertResumesToInsert() {
        var machine = ModeMachine()
        _ = machine.handle(.focus(.editable))
        assertStep(&machine, .togglePause, mode: .paused, effects: [])
        assertStep(&machine, .key(.escape), mode: .paused, effects: [.passKeyThrough])
        assertStep(&machine, .togglePause, mode: .insert, effects: [])
        assertStep(&machine, .key(.other), mode: .insert, effects: [.passKeyThrough])
        assertStep(&machine, .key(.escape), mode: .normal, effects: [.swallowKey, .blurFocus])
    }

    func testPauseFromManualInsertResumesToInsert() {
        var machine = armedNormal()
        _ = machine.handle(.key(.manualInsert))
        assertStep(&machine, .pause, mode: .paused, effects: [])
        assertStep(&machine, .resume, mode: .insert, effects: [])
        assertStep(&machine, .key(.other), mode: .insert, effects: [.passKeyThrough])
    }

    func testPauseFromHintCancelsHintAndResumesToNormal() {
        var machine = armedNormal()
        _ = machine.handle(.key(.hint(.command)))
        assertStep(&machine, .togglePause, mode: .paused, effects: [.endHint])
        assertStep(&machine, .key(.other), mode: .paused, effects: [.passKeyThrough])
        assertStep(&machine, .togglePause, mode: .normal, effects: [])
        assertStep(&machine, .key(.other), mode: .normal, effects: [.passKeyThrough])
    }

    func testMenuPauseToggleAndHotkeyPauseToggleMatch() {
        var fromMenu = armedNormal()
        var fromHotkey = armedNormal()
        let pausedFromMenu = fromMenu.handle(.togglePause)
        let pausedFromHotkey = fromHotkey.handle(.togglePause)
        XCTAssertEqual(pausedFromMenu, pausedFromHotkey)
        XCTAssertEqual(pausedFromMenu.mode, .paused)
        XCTAssertEqual(pausedFromMenu.effects, [])

        let resumedFromMenu = fromMenu.handle(.togglePause)
        let resumedFromHotkey = fromHotkey.handle(.togglePause)
        XCTAssertEqual(resumedFromMenu, resumedFromHotkey)
        XCTAssertEqual(resumedFromMenu.mode, .normal)
    }

    func testRepeatedPauseKeepsTheOriginalResumeTarget() {
        var machine = armedNormal()
        _ = machine.handle(.key(.manualInsert))
        _ = machine.handle(.pause)
        assertStep(&machine, .pause, mode: .paused, effects: [])
        assertStep(&machine, .resume, mode: .insert, effects: [])
    }

    func testResumeWhenNotPausedIsIgnored() {
        var machine = armedNormal()
        assertStep(&machine, .resume, mode: .normal, effects: [])
        _ = machine.handle(.key(.hint(.plain)))
        assertStep(&machine, .resume, mode: .hint(.plain), effects: [])
    }

    func testExplicitPauseAndResumeRoundTripFromNormal() {
        var machine = armedNormal()
        assertStep(&machine, .pause, mode: .paused, effects: [])
        assertStep(&machine, .resume, mode: .normal, effects: [])
        assertStep(&machine, .key(.manualInsert), mode: .insert, effects: [.swallowKey])
    }

    func testEditableFocusWhilePausedResumesToInsert() {
        var machine = armedNormal()
        _ = machine.handle(.pause)
        assertStep(&machine, .focus(.editable), mode: .paused, effects: [])
        assertStep(&machine, .key(.other), mode: .paused, effects: [.passKeyThrough])
        assertStep(&machine, .resume, mode: .insert, effects: [])
    }

    func testNotEditableFocusWhilePausedEndsAnAutomaticInsertResume() {
        var machine = ModeMachine()
        _ = machine.handle(.focus(.editable))
        _ = machine.handle(.pause)
        assertStep(&machine, .focus(.notEditable), mode: .paused, effects: [])
        assertStep(&machine, .resume, mode: .normal, effects: [])
    }

    func testNotEditableFocusWhilePausedKeepsAManualInsertResume() {
        var machine = armedNormal()
        _ = machine.handle(.key(.manualInsert))
        _ = machine.handle(.pause)
        assertStep(&machine, .focus(.notEditable), mode: .paused, effects: [])
        assertStep(&machine, .resume, mode: .insert, effects: [])
    }

    func testUnknownFocusWhilePausedDoesNotDropTheResumeTarget() {
        var machine = armedNormal()
        _ = machine.handle(.key(.manualInsert))
        _ = machine.handle(.pause)
        assertStep(&machine, .focus(.unknown), mode: .paused, effects: [])
        assertStep(&machine, .resume, mode: .insert, effects: [])
        assertStep(&machine, .key(.escape), mode: .insert, effects: [.passKeyThrough])
    }

    func testPauseFromHintThenEditableFocusResumesToInsert() {
        var machine = armedNormal()
        _ = machine.handle(.key(.hint(.plain)))
        _ = machine.handle(.togglePause)
        _ = machine.handle(.focus(.editable))
        assertStep(&machine, .resume, mode: .insert, effects: [])
    }

    func testPauseWhileFocusIsUnknownResumesWithoutSwallowing() {
        var machine = ModeMachine()
        assertStep(&machine, .togglePause, mode: .paused, effects: [])
        assertStep(&machine, .togglePause, mode: .normal, effects: [])
        assertStep(&machine, .key(.hint(.plain)), mode: .normal, effects: [.passKeyThrough])
    }

    func testExcludedForegroundPassesKeys() {
        var machine = armedNormal()
        assertStep(&machine, .foreground(.excluded), mode: .normal, effects: [])
        assertStep(&machine, .key(.hint(.plain)), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .key(.hint(.command)), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .key(.manualInsert), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .key(.escape), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .key(.other), mode: .normal, effects: [.passKeyThrough])
    }

    func testBecomingExcludedDuringHintCancelsTheHint() {
        var machine = armedNormal()
        _ = machine.handle(.key(.hint(.command)))
        assertStep(&machine, .foreground(.excluded), mode: .normal, effects: [.endHint])
        assertStep(&machine, .key(.other), mode: .normal, effects: [.passKeyThrough])
    }

    func testExcludedDuringInsertDoesNotBlurOrLeaveOnEscape() {
        var machine = ModeMachine()
        _ = machine.handle(.focus(.editable))
        assertStep(&machine, .foreground(.excluded), mode: .insert, effects: [])
        assertStep(&machine, .key(.escape), mode: .insert, effects: [.passKeyThrough])
        assertStep(&machine, .key(.hint(.plain)), mode: .insert, effects: [.passKeyThrough])
    }

    func testEditableFocusWhileExcludedDoesNotEnterInsertUntilTheAppIsControlled() {
        var machine = ModeMachine()
        _ = machine.handle(.foreground(.excluded))
        assertStep(&machine, .focus(.editable), mode: .normal, effects: [])
        assertStep(&machine, .key(.other), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .foreground(.controlled), mode: .insert, effects: [])
        assertStep(&machine, .key(.other), mode: .insert, effects: [.passKeyThrough])
    }

    func testLeavingExcludedAppWithUnknownFocusKeepsPassingKeys() {
        var machine = armedNormal()
        _ = machine.handle(.foreground(.excluded))
        _ = machine.handle(.focus(.unknown))
        assertStep(&machine, .foreground(.controlled), mode: .normal, effects: [])
        assertStep(&machine, .key(.hint(.plain)), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .key(.escape), mode: .normal, effects: [.passKeyThrough])
    }

    func testLeavingExcludedAppWithNotEditableFocusRestoresNormalCommands() {
        var machine = armedNormal()
        _ = machine.handle(.foreground(.excluded))
        assertStep(&machine, .foreground(.controlled), mode: .normal, effects: [])
        assertStep(&machine, .key(.manualInsert), mode: .insert, effects: [.swallowKey])
    }

    func testLeavingExcludedAppKeepsInsertWhenFocusIsStillEditable() {
        var machine = ModeMachine()
        _ = machine.handle(.focus(.editable))
        _ = machine.handle(.foreground(.excluded))
        assertStep(&machine, .foreground(.controlled), mode: .insert, effects: [])
        assertStep(&machine, .key(.escape), mode: .normal, effects: [.swallowKey, .blurFocus])
    }

    func testFocusLeavingDuringExclusionEndsAutomaticInsertOnReturn() {
        var machine = ModeMachine()
        _ = machine.handle(.focus(.editable))
        _ = machine.handle(.foreground(.excluded))
        assertStep(&machine, .focus(.notEditable), mode: .insert, effects: [])
        assertStep(&machine, .foreground(.controlled), mode: .normal, effects: [])
        assertStep(&machine, .key(.manualInsert), mode: .insert, effects: [.swallowKey])
    }

    func testExcludedHintThenEditableFocusEntersInsertWhenControlledAgain() {
        var machine = armedNormal()
        _ = machine.handle(.key(.hint(.plain)))
        _ = machine.handle(.foreground(.excluded))
        _ = machine.handle(.focus(.editable))
        XCTAssertEqual(machine.mode, .normal)
        assertStep(&machine, .foreground(.controlled), mode: .insert, effects: [])
    }

    func testPauseStillWorksWhileTheForegroundAppIsExcluded() {
        var machine = armedNormal()
        _ = machine.handle(.foreground(.excluded))
        assertStep(&machine, .togglePause, mode: .paused, effects: [])
        assertStep(&machine, .key(.other), mode: .paused, effects: [.passKeyThrough])
        assertStep(&machine, .togglePause, mode: .normal, effects: [])
        assertStep(&machine, .key(.hint(.plain)), mode: .normal, effects: [.passKeyThrough])
    }

    func testResumeWhileExcludedPassesKeys() {
        var machine = ModeMachine()
        _ = machine.handle(.focus(.editable))
        _ = machine.handle(.pause)
        _ = machine.handle(.foreground(.excluded))
        assertStep(&machine, .resume, mode: .insert, effects: [])
        assertStep(&machine, .key(.escape), mode: .insert, effects: [.passKeyThrough])
    }

    func testRepeatedEditableFocusStaysInInsert() {
        var machine = ModeMachine()
        _ = machine.handle(.focus(.editable))
        assertStep(&machine, .focus(.editable), mode: .insert, effects: [])
    }

    func testRepeatedControlledForegroundIsIgnored() {
        var machine = armedNormal()
        assertStep(&machine, .foreground(.controlled), mode: .normal, effects: [])
    }

    func testRepeatedExcludedForegroundDoesNotEndHintTwice() {
        var machine = armedNormal()
        _ = machine.handle(.key(.hint(.plain)))
        _ = machine.handle(.foreground(.excluded))
        assertStep(&machine, .foreground(.excluded), mode: .normal, effects: [])
    }

    func testNotEditableFocusWhileNormalDoesNothing() {
        var machine = ModeMachine()
        assertStep(&machine, .focus(.notEditable), mode: .normal, effects: [])
        assertStep(&machine, .key(.manualInsert), mode: .insert, effects: [.swallowKey])
    }

    func testHintResolutionWhilePausedDoesNotResume() {
        var machine = armedNormal()
        _ = machine.handle(.pause)
        assertStep(&machine, .hintCompleted, mode: .paused, effects: [])
        assertStep(&machine, .hintCancelled, mode: .paused, effects: [])
        assertStep(&machine, .resume, mode: .normal, effects: [])
    }

    func testOtherKeyIsNotTreatedAsThePauseHotkey() {
        var machine = armedNormal()
        assertStep(&machine, .key(.other), mode: .normal, effects: [.passKeyThrough])
        XCTAssertNotEqual(machine.mode, .paused)
    }

    func testResumeWhileExcludedDoesNotEnterInsertEvenIfFocusIsEditable() {
        var machine = ModeMachine()
        _ = machine.handle(.foreground(.excluded))
        _ = machine.handle(.focus(.editable))
        _ = machine.handle(.pause)
        assertStep(&machine, .resume, mode: .normal, effects: [])
        assertStep(&machine, .key(.other), mode: .normal, effects: [.passKeyThrough])
        assertStep(&machine, .foreground(.controlled), mode: .insert, effects: [])
    }

    func testResumeAfterControlledReturnsWithEditableFocusEntersInsert() {
        var machine = ModeMachine()
        _ = machine.handle(.foreground(.excluded))
        _ = machine.handle(.focus(.editable))
        _ = machine.handle(.pause)
        assertStep(&machine, .foreground(.controlled), mode: .paused, effects: [])
        assertStep(&machine, .resume, mode: .insert, effects: [])
    }

    func testManualInsertSurvivesExclusion() {
        var machine = armedNormal()
        _ = machine.handle(.key(.manualInsert))
        _ = machine.handle(.foreground(.excluded))
        assertStep(&machine, .focus(.notEditable), mode: .insert, effects: [])
        assertStep(&machine, .key(.escape), mode: .insert, effects: [.passKeyThrough])
        assertStep(&machine, .foreground(.controlled), mode: .insert, effects: [])
        assertStep(&machine, .key(.other), mode: .insert, effects: [.passKeyThrough])
    }

    func testEditableFocusWhilePausedAnchorsResumeToTheField() {
        var machine = armedNormal()
        _ = machine.handle(.key(.manualInsert))
        _ = machine.handle(.pause)
        _ = machine.handle(.focus(.editable))
        assertStep(&machine, .focus(.notEditable), mode: .paused, effects: [])
        assertStep(&machine, .resume, mode: .normal, effects: [])
    }

    func testHoldManualInsertEntersInsertEvenWhenFocusIsUnknown() {
        var machine = armedNormal()
        let step = machine.holdManualInsert()
        XCTAssertEqual(machine.mode, .insert)
        XCTAssertEqual(step.effects, [.swallowKey])
        assertStep(&machine, .focus(.notEditable), mode: .insert, effects: [])

        var unknown = ModeMachine()
        XCTAssertEqual(unknown.holdManualInsert().mode, .insert)

        var paused = armedNormal()
        _ = paused.handle(.pause)
        XCTAssertEqual(paused.holdManualInsert().mode, .paused)

        var hint = armedNormal()
        _ = hint.handle(.key(.hint(.plain)))
        let left = hint.holdManualInsert()
        XCTAssertEqual(hint.mode, .insert)
        XCTAssertTrue(left.effects.contains(.endHint))

        var excluded = armedNormal()
        _ = excluded.handle(.foreground(.excluded))
        XCTAssertEqual(excluded.holdManualInsert().mode, .normal)
    }

    func testValueCopiesDoNotShareLaterTransitions() {
        let original = armedNormal()
        var copy = original
        _ = copy.handle(.pause)
        XCTAssertEqual(original.mode, .normal)
        XCTAssertEqual(copy.mode, .paused)
    }
}

private func assertStep(
    _ machine: inout ModeMachine,
    _ input: ModeInput,
    mode: SupervimMode,
    effects: [ModeEffect],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let step = machine.handle(input)
    XCTAssertEqual(step.mode, mode, file: file, line: line)
    XCTAssertEqual(step.effects, effects, file: file, line: line)
    XCTAssertEqual(machine.mode, mode, file: file, line: line)
}

private func armedNormal(file: StaticString = #filePath, line: UInt = #line) -> ModeMachine {
    var machine = ModeMachine()
    let step = machine.handle(.focus(.notEditable))
    XCTAssertEqual(step.mode, .normal, file: file, line: line)
    XCTAssertEqual(step.effects, [], file: file, line: line)
    return machine
}

import XCTest
@testable import SupervimCore

/// Behavior contract for the pure key parser.
/// The parser maps a key stream to command tokens. It does not know
/// Normal, Insert, Hint, or Paused, and it does not perform the commands.
final class KeyParserTests: XCTestCase {
    func testDefaultPrefixTimeoutIsOneSecond() {
        let parser = KeyParser(clock: ManualKeyClock())
        XCTAssertEqual(parser.prefixTimeoutMilliseconds, 1000)
    }

    func testEveryApprovedSingleKeyBinding() {
        let rows: [(Character, KeyCommand)] = [
            ("f", .hint(.plain)),
            ("F", .hint(.command)),
            ("i", .manualInsert),
            ("j", .scrollDown),
            ("k", .scrollUp),
            ("h", .scrollLeft),
            ("l", .scrollRight),
            ("d", .scrollHalfPageDown),
            ("u", .scrollHalfPageUp),
            ("G", .scrollToBottom),
            ("H", .historyBack),
            ("L", .historyForward),
            ("J", .previousTab),
            ("K", .nextTab),
            ("x", .close),
            ("t", .create),
            ("r", .reload),
            ("/", .find),
            ("?", .help),
        ]
        for (character, command) in rows {
            var parser = makeParser().parser
            assertHandle(
                &parser,
                KeyEvent(character),
                [.command(command)],
                "\(character)"
            )
        }
    }

    func testEscapeIsACommand() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent(identity: .escape), [.command(.escape)])
        assertHandle(&parser, KeyEvent("\u{1B}"), [.command(.escape)])
    }

    func testCaseIsDistinctForEveryAmbiguousLetter() {
        let rows: [(Character, [KeyParseResult])] = [
            ("f", [.command(.hint(.plain))]),
            ("F", [.command(.hint(.command))]),
            ("g", [.waitingForPrefix]),
            ("G", [.command(.scrollToBottom)]),
            ("h", [.command(.scrollLeft)]),
            ("H", [.command(.historyBack)]),
            ("j", [.command(.scrollDown)]),
            ("J", [.command(.previousTab)]),
            ("k", [.command(.scrollUp)]),
            ("K", [.command(.nextTab)]),
            ("y", [.waitingForPrefix]),
            ("Y", [.passThrough]),
        ]
        for (character, results) in rows {
            var parser = makeParser().parser
            assertHandle(&parser, KeyEvent(character), results, "\(character)")
        }
    }

    func testLowercaseGThenGScrollsToTop() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(&parser, KeyEvent("g"), [.command(.scrollToTop)])
        assertHandle(&parser, KeyEvent("j"), [.command(.scrollDown)])
    }

    func testLowercaseGThenIFocusesTheFirstInput() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(&parser, KeyEvent("i"), [.command(.focusFirstInput)])
    }

    func testYYCopiesTheURL() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("y"), [.waitingForPrefix])
        assertHandle(&parser, KeyEvent("y"), [.command(.copyURL)])
    }

    func testGIIsNotManualInsertAndYYIsNotTwoPrefixes() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(&parser, KeyEvent("i"), [.command(.focusFirstInput)])
        assertHandle(&parser, KeyEvent("y"), [.waitingForPrefix])
        assertHandle(&parser, KeyEvent("y"), [.command(.copyURL)])
        assertHandle(&parser, KeyEvent("i"), [.command(.manualInsert)])
    }

    func testUppercaseGIsImmediateAndDoesNotWait() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("G"), [.command(.scrollToBottom)])
        assertHandle(&parser, KeyEvent("G"), [.command(.scrollToBottom)])
    }

    func testUppercaseYIsNotAPrefixOrACommand() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("Y"), [.passThrough])
        assertHandle(&parser, KeyEvent("y"), [.waitingForPrefix])
    }

    func testFailedPrefixPassesAnUnknownSecondKey() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(&parser, KeyEvent("z"), [.prefixCancelled, .passThrough])
        assertHandle(&parser, KeyEvent("j"), [.command(.scrollDown)])
    }

    func testFailedPrefixReparsesASecondKeyThatIsItsOwnCommand() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(&parser, KeyEvent("u"), [.prefixCancelled, .command(.scrollHalfPageUp)])
        assertHandle(&parser, KeyEvent("y"), [.waitingForPrefix])
        assertHandle(&parser, KeyEvent("x"), [.prefixCancelled, .command(.close)])
    }

    func testFailedPrefixCanStartADifferentPrefix() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(&parser, KeyEvent("y"), [.prefixCancelled, .waitingForPrefix])
        assertHandle(&parser, KeyEvent("y"), [.command(.copyURL)])
    }

    func testGThenUppercaseGIsBottomNotTop() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(&parser, KeyEvent("G"), [.prefixCancelled, .command(.scrollToBottom)])
    }

    func testYThenUppercaseYPassesTheSecondKey() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("y"), [.waitingForPrefix])
        assertHandle(&parser, KeyEvent("Y"), [.prefixCancelled, .passThrough])
    }

    func testLonelyPrefixIsNotACommandAfterTimeout() {
        let fixture = makeParser()
        var parser = fixture.parser
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        fixture.clock.advance(by: 1000)
        XCTAssertEqual(parser.expirePendingPrefix(), .prefixCancelled)
        XCTAssertNil(parser.expirePendingPrefix())
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
    }

    func testTimeoutIsCheckedWhenTheNextKeyArrives() {
        let fixture = makeParser()
        var parser = fixture.parser
        assertHandle(&parser, KeyEvent("y"), [.waitingForPrefix])
        fixture.clock.advance(by: 1000)
        assertHandle(&parser, KeyEvent("y"), [.prefixCancelled, .waitingForPrefix])
    }

    func testSecondKeyJustBeforeTheTimeoutStillCompletes() {
        let fixture = makeParser()
        var parser = fixture.parser
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        fixture.clock.advance(by: 999)
        XCTAssertNil(parser.expirePendingPrefix())
        assertHandle(&parser, KeyEvent("g"), [.command(.scrollToTop)])
    }

    func testPrefixTimeoutIsConfigurable() {
        let clock = ManualKeyClock()
        var parser = KeyParser(clock: clock, prefixTimeoutMilliseconds: 50)
        XCTAssertEqual(parser.prefixTimeoutMilliseconds, 50)
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        clock.advance(by: 49)
        assertHandle(&parser, KeyEvent("i"), [.command(.focusFirstInput)])

        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        clock.advance(by: 50)
        assertHandle(&parser, KeyEvent("i"), [.prefixCancelled, .command(.manualInsert)])
    }

    func testExpireBeforeTheDeadlineLeavesThePrefixWaiting() {
        let fixture = makeParser()
        var parser = fixture.parser
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        fixture.clock.advance(by: 999)
        XCTAssertNil(parser.expirePendingPrefix())
        assertHandle(&parser, KeyEvent("i"), [.command(.focusFirstInput)])
    }

    func testExpireWithNothingPendingDoesNothing() {
        var parser = makeParser().parser
        XCTAssertNil(parser.expirePendingPrefix())
        assertHandle(&parser, KeyEvent("j"), [.command(.scrollDown)])
    }

    func testEscapeCancelsAPrefixAndIsStillEscape() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(
            &parser,
            KeyEvent(identity: .escape),
            [.prefixCancelled, .command(.escape)]
        )
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(&parser, KeyEvent("\u{1B}"), [.prefixCancelled, .command(.escape)])
        assertHandle(&parser, KeyEvent("j"), [.command(.scrollDown)])
    }

    func testModifiedEscapeDoesNotCancelAsEscape() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("y"), [.waitingForPrefix])
        assertHandle(
            &parser,
            KeyEvent(identity: .escape, modifiers: .command),
            [.prefixCancelled, .passThrough]
        )
        assertHandle(&parser, KeyEvent("j"), [.command(.scrollDown)])
    }

    func testUnknownKeysPassThrough() {
        let characters: [Character] = ["q", "z", "Q", "Z", "0", "1", " ", "v", "V", "o", "b", "n", "N", "X", "D", "U", "T", "R", "I", "]", ".", "w"]
        for character in characters {
            var parser = makeParser().parser
            assertHandle(&parser, KeyEvent(character), [.passThrough], "\(character)")
        }
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent(identity: .unnamed), [.passThrough])
    }

    func testCommandOptionAndControlBlockSingleKeyCommands() {
        let modifiers: [KeyModifiers] = [.command, .option, .control, [.command, .shift]]
        for modifiers in modifiers {
            var parser = makeParser().parser
            assertHandle(&parser, KeyEvent("j", modifiers: modifiers), [.passThrough], "\(modifiers)")
            assertHandle(&parser, KeyEvent("f", modifiers: modifiers), [.passThrough], "f \(modifiers)")
            assertHandle(&parser, KeyEvent("G", modifiers: modifiers), [.passThrough], "G \(modifiers)")
        }
    }

    func testShiftDoesNotBlockTheCharacterThatWasProduced() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("J", modifiers: .shift), [.command(.previousTab)])
        assertHandle(&parser, KeyEvent("?", modifiers: .shift), [.command(.help)])
        assertHandle(&parser, KeyEvent("/", modifiers: []), [.command(.find)])
    }

    func testModifiedPrefixKeysDoNotWait() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("g", modifiers: .command), [.passThrough])
        assertHandle(&parser, KeyEvent("g", modifiers: .control), [.passThrough])
        assertHandle(&parser, KeyEvent("y", modifiers: .option), [.passThrough])
        assertHandle(&parser, KeyEvent("j"), [.command(.scrollDown)])
    }

    func testControlBracketArmsPassNextKey() {
        var parser = makeParser().parser
        assertHandle(
            &parser,
            KeyEvent("]", modifiers: .control),
            [.command(.passNextKey)]
        )
        assertHandle(&parser, KeyEvent("j"), [.passThrough])
        assertHandle(&parser, KeyEvent("j"), [.command(.scrollDown)])
    }

    func testControlGroupSeparatorArmsPassNextKey() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("\u{1D}"), [.command(.passNextKey)])
        assertHandle(&parser, KeyEvent("f"), [.passThrough])
        assertHandle(
            &parser,
            KeyEvent("\u{1D}", modifiers: .control),
            [.command(.passNextKey)]
        )
        assertHandle(&parser, KeyEvent(identity: .escape), [.passThrough])
        assertHandle(&parser, KeyEvent("i"), [.command(.manualInsert)])
    }

    func testPassNextKeyDoesNotParseAPrefixOrAnotherPassNext() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("]", modifiers: .control), [.command(.passNextKey)])
        assertHandle(&parser, KeyEvent("g"), [.passThrough])
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(&parser, KeyEvent("g"), [.command(.scrollToTop)])

        assertHandle(&parser, KeyEvent("]", modifiers: .control), [.command(.passNextKey)])
        assertHandle(&parser, KeyEvent("]", modifiers: .control), [.passThrough])
        assertHandle(&parser, KeyEvent("x"), [.command(.close)])
    }

    func testOtherControlChordsAreNotPassNextOrPause() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("]"), [.passThrough])
        assertHandle(&parser, KeyEvent("]", modifiers: [.control, .shift]), [.passThrough])
        assertHandle(&parser, KeyEvent("]", modifiers: [.control, .option]), [.passThrough])
        assertHandle(&parser, KeyEvent("]", modifiers: [.control, .command]), [.passThrough])
        assertHandle(&parser, KeyEvent("\u{1D}", modifiers: .option), [.passThrough])
        assertHandle(&parser, KeyEvent("v", modifiers: [.control, .option]), [.passThrough])
        assertHandle(&parser, KeyEvent("V", modifiers: [.control, .option]), [.passThrough])
        assertHandle(
            &parser,
            KeyEvent("v", modifiers: [.control, .option, .command]),
            [.passThrough]
        )
        assertHandle(&parser, KeyEvent("j"), [.command(.scrollDown)])
    }

    func testControlBracketDuringAPrefixCancelsThenArmsPassNext() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(
            &parser,
            KeyEvent("]", modifiers: .control),
            [.prefixCancelled, .command(.passNextKey)]
        )
        assertHandle(&parser, KeyEvent("f"), [.passThrough])
        assertHandle(&parser, KeyEvent("F"), [.command(.hint(.command))])
    }

    func testTimedOutPrefixIsSwallowedRatherThanCompletedByALateKey() {
        let fixture = makeParser()
        var parser = fixture.parser
        assertHandle(&parser, KeyEvent("g"), [.waitingForPrefix])
        fixture.clock.advance(by: 1000)
        assertHandle(&parser, KeyEvent("g"), [.prefixCancelled, .waitingForPrefix])
        assertHandle(&parser, KeyEvent("i"), [.command(.focusFirstInput)])
    }

    func testEachParserKeepsItsOwnPrefixAndSharesOnlyItsClock() {
        let clock = ManualKeyClock()
        var first = KeyParser(clock: clock)
        var second = KeyParser(clock: clock, prefixTimeoutMilliseconds: 10)
        assertHandle(&first, KeyEvent("g"), [.waitingForPrefix])
        clock.advance(by: 10)
        assertHandle(&second, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(&first, KeyEvent("g"), [.command(.scrollToTop)])
        clock.advance(by: 10)
        assertHandle(&second, KeyEvent("g"), [.prefixCancelled, .waitingForPrefix])
    }

    func testValueCopiesDoNotSharePrefixOrPassNextState() {
        let clock = ManualKeyClock()
        var original = KeyParser(clock: clock)
        var copy = original
        assertHandle(&copy, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(&original, KeyEvent("g"), [.waitingForPrefix])
        assertHandle(&copy, KeyEvent("g"), [.command(.scrollToTop)])
        assertHandle(&original, KeyEvent("y"), [.prefixCancelled, .waitingForPrefix])

        assertHandle(&copy, KeyEvent("]", modifiers: .control), [.command(.passNextKey)])
        assertHandle(&original, KeyEvent("y"), [.command(.copyURL)])
        assertHandle(&copy, KeyEvent("j"), [.passThrough])
    }

    func testCommandsRepeatUntilAPrefixOrPassNextChangesTheState() {
        var parser = makeParser().parser
        assertHandle(&parser, KeyEvent("j"), [.command(.scrollDown)])
        assertHandle(&parser, KeyEvent("k"), [.command(.scrollUp)])
        assertHandle(&parser, KeyEvent("d"), [.command(.scrollHalfPageDown)])
        assertHandle(&parser, KeyEvent("u"), [.command(.scrollHalfPageUp)])
        assertHandle(&parser, KeyEvent("/"), [.command(.find)])
        assertHandle(&parser, KeyEvent("?"), [.command(.help)])
    }
}

private struct ParserFixture {
    var clock: ManualKeyClock
    var parser: KeyParser<ManualKeyClock>
}

private func makeParser(timeout: Int64 = 1000) -> ParserFixture {
    let clock = ManualKeyClock()
    return ParserFixture(clock: clock, parser: KeyParser(clock: clock, prefixTimeoutMilliseconds: timeout))
}

private func assertHandle(
    _ parser: inout KeyParser<ManualKeyClock>,
    _ event: KeyEvent,
    _ results: [KeyParseResult],
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(parser.handle(event).results, results, message, file: file, line: line)
}

import XCTest
@testable import SupervimCore

/// Help text comes from CommandMap. `?` opens it, and `?` or Esc closes it.
final class HelpSheetTests: XCTestCase {
    func testEntriesFollowTheCommandMapOrder() {
        let bindings = CommandMap().bindings
        let page = HelpPage(bindings: bindings)
        XCTAssertEqual(page.entries.map(\.keys), bindings.map(\.keys))
        XCTAssertEqual(page.entries.map(\.summary), bindings.map(\.summary))
        XCTAssertEqual(page.entries.map(\.deviatesFromVimium), bindings.map(\.deviatesFromVimium))
        XCTAssertEqual(
            page.entries.map(\.promisedApplicationNames),
            bindings.map(\.promisedApplicationNames)
        )
        XCTAssertEqual(page.text, page.entries.map(\.line).joined(separator: "\n"))
        XCTAssertFalse(page.text.isEmpty)
    }

    func testFindRowNamesCommandFAndTheVimiumDeviation() {
        let find = HelpPage(bindings: CommandMap().bindings).entries.first { $0.keys == "/" }
        XCTAssertEqual(find?.summary, "Find with the app shortcut")
        XCTAssertEqual(find?.actionText, "Command+F")
        XCTAssertEqual(find?.deviatesFromVimium, true)
        XCTAssertEqual(
            find?.line,
            "/  Find with the app shortcut  Command+F  differs from Vimium"
        )
    }

    func testOnlyFindCommandHintAndHelpDifferFromVimium() {
        let marked = HelpPage(bindings: CommandMap().bindings)
            .entries
            .filter(\.deviatesFromVimium)
            .map(\.keys)
        XCTAssertEqual(marked, ["/", "F", "?"])
        let commandHint = HelpPage(bindings: CommandMap().bindings).entries.first { $0.keys == "F" }
        XCTAssertEqual(commandHint?.actionText, "Command-click")
        XCTAssertTrue(commandHint?.line.contains("differs from Vimium") == true)
        let help = HelpPage(bindings: CommandMap().bindings).entries.first { $0.keys == "?" }
        XCTAssertEqual(help?.actionText, "show help")
        XCTAssertTrue(help?.line.contains("differs from Vimium") == true)
    }

    func testUnmarkedRowsDoNotCarryTheDeviationPhrase() {
        let page = HelpPage(bindings: CommandMap().bindings)
        XCTAssertFalse(page.entries.isEmpty)
        for entry in page.entries where !entry.deviatesFromVimium {
            XCTAssertFalse(entry.line.contains("differs from Vimium"), entry.keys)
        }
    }

    func testDefaultActionTextMatchesTheMap() {
        let expected = [
            "j": "scroll down 60 points",
            "k": "scroll up 60 points",
            "h": "scroll left 60 points",
            "l": "scroll right 60 points",
            "d": "scroll down half a page",
            "u": "scroll up half a page",
            "gg": "scroll to the top",
            "G": "scroll to the bottom",
            "gi": "focus the first input",
            "Ctrl+]": "pass the next key",
            "H": "Command+[",
            "L": "Command+]",
            "J": "Command+Shift+[",
            "K": "Command+Shift+]",
            "x": "Command+W",
            "t": "Command+T",
            "r": "Command+R",
            "/": "Command+F",
            "yy": "Command+L, Command+C",
            "f": "hint",
            "F": "Command-click",
            "?": "show help",
            "i": "enter insert",
            "Esc": "escape",
        ]
        let page = HelpPage(bindings: CommandMap().bindings)
        XCTAssertEqual(page.entries.map(\.keys), expected.keys.sorted { lhs, rhs in
            let order = CommandMap().bindings.map(\.keys)
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        })
        for entry in page.entries {
            XCTAssertEqual(entry.actionText, expected[entry.keys], entry.keys)
        }
        let copy = page.entries.first { $0.keys == "yy" }
        XCTAssertEqual(copy?.promisedApplicationNames, ["Safari", "Chromium"])
        XCTAssertEqual(copy?.line, "yy  Copy URL  Command+L, Command+C  Safari, Chromium")
    }

    func testShortcutModifiersUseCommandShiftOptionControlOrder() {
        let binding = helpBinding(
            keys: "z",
            action: .sendShortcut(KeyCombo("a", modifiers: [.control, .option, .shift, .command])),
            summary: "Chord"
        )
        XCTAssertEqual(
            HelpPage(bindings: [binding]).entries.first?.actionText,
            "Command+Shift+Option+Control+A"
        )
    }

    func testOtherScrollAmountsAndEdgesAreNamed() {
        let rows = [
            helpBinding(
                keys: "h",
                action: .scroll(direction: .left, amount: .points(10)),
                summary: "Left"
            ),
            helpBinding(
                keys: "d",
                action: .scroll(direction: .down, amount: .fractionOfPage(numerator: 1, denominator: 3)),
                summary: "Third"
            ),
            helpBinding(
                keys: "H",
                action: .scroll(direction: .left, amount: .edge),
                summary: "Far left"
            ),
            helpBinding(
                keys: "L",
                action: .scroll(direction: .right, amount: .edge),
                summary: "Far right"
            ),
        ]
        let text = HelpPage(bindings: rows).entries.map(\.actionText)
        XCTAssertEqual(text, [
            "scroll left 10 points",
            "scroll down 1/3 of a page",
            "scroll to the left edge",
            "scroll to the right edge",
        ])
    }

    func testSequencesFlattenAndAnEmptySequenceOmitsActionText() {
        let nested = helpBinding(
            keys: "p",
            action: .sequence([
                .sequence([.sendShortcut(KeyCombo("c", modifiers: .command))]),
                .sendShortcut(KeyCombo("v", modifiers: .command)),
            ]),
            summary: "Paste"
        )
        let empty = helpBinding(keys: "z", action: .sequence([]), summary: "Nothing")
        XCTAssertEqual(HelpPage(bindings: [nested]).entries.first?.actionText, "Command+C, Command+V")
        XCTAssertEqual(HelpPage(bindings: [empty]).entries.first?.actionText, "")
        XCTAssertEqual(HelpPage(bindings: [empty]).entries.first?.line, "z  Nothing")
    }

    func testDeviationAndPromisedNamesBothAppear() {
        let binding = helpBinding(
            keys: "/",
            action: .sendShortcut(KeyCombo("f", modifiers: .command)),
            summary: "Find",
            deviatesFromVimium: true,
            promisedApplicationNames: ["Safari"]
        )
        XCTAssertEqual(
            HelpPage(bindings: [binding]).entries.first?.line,
            "/  Find  Command+F  differs from Vimium  Safari"
        )
    }

    func testQuestionMarkOpensAndTheNextQuestionMarkCloses() {
        var sheet = HelpSheet()
        XCTAssertFalse(sheet.isOpen)
        guard case .shown(let page) = sheet.handle(KeyEvent("?")) else {
            return XCTFail("? should open help")
        }
        XCTAssertTrue(sheet.isOpen)
        XCTAssertEqual(page.entries.map(\.keys), CommandMap().bindings.map(\.keys))
        XCTAssertTrue(page.text.contains("Command+F"))
        XCTAssertEqual(sheet.handle(KeyEvent("?")), .hidden)
        XCTAssertFalse(sheet.isOpen)
    }

    func testShiftedQuestionMarkTogglesAndModifiedQuestionMarkDoesNot() {
        var shifted = HelpSheet()
        guard case .shown = shifted.handle(KeyEvent("?", modifiers: .shift)) else {
            return XCTFail("shift+? is how the key is typed")
        }
        XCTAssertEqual(shifted.handle(KeyEvent("?", modifiers: .shift)), .hidden)

        var commanded = HelpSheet()
        XCTAssertEqual(commanded.handle(KeyEvent("?", modifiers: .command)), .unchanged)
        XCTAssertFalse(commanded.isOpen)
        XCTAssertEqual(commanded.handle(KeyEvent("?", modifiers: .option)), .unchanged)
        XCTAssertEqual(commanded.handle(KeyEvent("?", modifiers: .control)), .unchanged)
    }

    func testEscapeClosesOnlyWhileHelpIsOpen() {
        var sheet = HelpSheet()
        XCTAssertEqual(sheet.handle(KeyEvent(identity: .escape)), .unchanged)
        XCTAssertFalse(sheet.isOpen)
        _ = sheet.handle(KeyEvent("?"))
        XCTAssertEqual(sheet.handle(KeyEvent(identity: .escape)), .hidden)
        XCTAssertFalse(sheet.isOpen)
        XCTAssertEqual(sheet.handle(KeyEvent("\u{1B}")), .unchanged)

        _ = sheet.show()
        XCTAssertEqual(sheet.handle(KeyEvent("\u{1B}")), .hidden)
    }

    func testModifiedEscapeAndOtherKeysLeaveHelpOpen() {
        var sheet = HelpSheet()
        _ = sheet.show()
        XCTAssertEqual(sheet.handle(KeyEvent("j")), .unchanged)
        XCTAssertEqual(sheet.handle(KeyEvent(identity: .escape, modifiers: .command)), .unchanged)
        XCTAssertEqual(sheet.handle(KeyEvent(identity: .unnamed)), .unchanged)
        XCTAssertTrue(sheet.isOpen)
    }

    func testShowAndHideAreIdempotent() {
        var sheet = HelpSheet(bindings: [])
        XCTAssertEqual(sheet.hide(), .unchanged)
        guard case .shown(let page) = sheet.show() else {
            return XCTFail("an empty map still opens")
        }
        XCTAssertEqual(page.entries, [])
        XCTAssertEqual(page.text, "")
        XCTAssertEqual(sheet.show(), .unchanged)
        XCTAssertEqual(sheet.hide(), .hidden)
        XCTAssertEqual(sheet.hide(), .unchanged)
    }

    func testSheetSourceDoesNotTouchTheSystemOrRecordKeys() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimCore/HelpSheet.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        for token in [
            "import AppKit",
            "import ApplicationServices",
            "import CoreGraphics",
            "import Accessibility",
            "AXUIElement",
            "CGEvent",
            "URLSession",
            "os_log",
            "Logger(",
            "NSLog",
            "print(",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
    }
}

private func helpBinding(
    keys: String,
    action: Action,
    summary: String,
    deviatesFromVimium: Bool = false,
    promisedApplicationNames: [String]? = nil
) -> CommandBinding {
    CommandBinding(
        keys: keys,
        command: .scrollDown,
        action: action,
        summary: summary,
        deviatesFromVimium: deviatesFromVimium,
        promisedApplicationNames: promisedApplicationNames
    )
}

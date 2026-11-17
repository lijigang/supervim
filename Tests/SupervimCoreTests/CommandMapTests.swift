import XCTest
@testable import SupervimCore

/// Behavior contract for the pure command map.
/// KeyParser tokens become actions. Nothing here scrolls, clicks, or sends keys.
final class CommandMapTests: XCTestCase {
    func testScrollStepIsSixtyPoints() {
        XCTAssertEqual(CommandMap.scrollStepPoints, 60)
    }

    func testHalfPageIsOneHalfOfTheVisiblePage() {
        XCTAssertEqual(CommandMap.halfPageNumerator, 1)
        XCTAssertEqual(CommandMap.halfPageDenominator, 2)
    }

    func testEveryCommandTokenMapsToTheApprovedAction() {
        let map = CommandMap()
        for row in approvedBindings {
            XCTAssertEqual(map.action(for: row.command), row.action, row.keys)
        }
    }

    func testBindingsFollowTheSpecOrder() {
        let bindings = CommandMap().bindings
        XCTAssertEqual(bindings.map(\.keys), approvedBindings.map(\.keys))
        XCTAssertEqual(bindings.map(\.command), approvedBindings.map(\.command))
        XCTAssertEqual(bindings.map(\.action), approvedBindings.map(\.action))
        XCTAssertEqual(bindings.map(\.summary), approvedBindings.map(\.summary))
        XCTAssertEqual(bindings.map(\.deviatesFromVimium), approvedBindings.map(\.deviatesFromVimium))
        XCTAssertEqual(
            bindings.map(\.promisedApplicationNames),
            approvedBindings.map(\.promisedApplicationNames)
        )
    }

    func testEachTokenAppearsOnceBesidesTheTwoHintKinds() {
        let commands = CommandMap().bindings.map(\.command)
        XCTAssertEqual(commands.count, approvedBindings.count)
        XCTAssertEqual(commands.count, 24)
        XCTAssertEqual(commands.filter { $0 == .hint(.plain) }.count, 1)
        XCTAssertEqual(commands.filter { $0 == .hint(.command) }.count, 1)
        let singles = commands.filter {
            if case .hint = $0 { return false }
            return true
        }
        XCTAssertEqual(Set(singles.map(String.init(describing:))).count, singles.count)
        XCTAssertEqual(singles.count, 22)
    }

    func testBindingKeysRoundTripThroughKeyParser() {
        let map = CommandMap()
        for binding in map.bindings {
            var parser = KeyParser(clock: ManualKeyClock())
            var commands: [KeyCommand] = []
            for event in events(for: binding.keys) {
                for result in parser.handle(event).results {
                    switch map.disposition(for: result) {
                    case .perform(let action):
                        XCTAssertEqual(action, binding.action, binding.keys)
                        guard case .command(let command) = result else {
                            XCTFail("perform without a command for \(binding.keys)")
                            continue
                        }
                        commands.append(command)
                    case .passThrough:
                        XCTFail("binding \(binding.keys) passed a key through")
                    case .swallow:
                        XCTAssertNotEqual(result, .passThrough, binding.keys)
                    }
                }
            }
            XCTAssertEqual(commands, [binding.command], binding.keys)
        }
    }

    func testCommandResultsPerformTheirActions() {
        let map = CommandMap()
        for row in approvedBindings {
            XCTAssertEqual(
                map.disposition(for: .command(row.command)),
                .perform(row.action),
                row.keys
            )
        }
    }

    func testScrollDirectionsAndAmounts() {
        let map = CommandMap()
        XCTAssertEqual(
            map.action(for: .scrollLeft),
            .scroll(direction: .left, amount: .points(CommandMap.scrollStepPoints))
        )
        XCTAssertEqual(
            map.action(for: .scrollDown),
            .scroll(direction: .down, amount: .points(60))
        )
        XCTAssertEqual(
            map.action(for: .scrollUp),
            .scroll(direction: .up, amount: .points(60))
        )
        XCTAssertEqual(
            map.action(for: .scrollRight),
            .scroll(direction: .right, amount: .points(60))
        )
        XCTAssertEqual(
            map.action(for: .scrollHalfPageDown),
            .scroll(
                direction: .down,
                amount: .fractionOfPage(numerator: 1, denominator: 2)
            )
        )
        XCTAssertEqual(
            map.action(for: .scrollHalfPageUp),
            .scroll(
                direction: .up,
                amount: .fractionOfPage(numerator: 1, denominator: 2)
            )
        )
        XCTAssertEqual(map.action(for: .scrollToTop), .scroll(direction: .up, amount: .edge))
        XCTAssertEqual(map.action(for: .scrollToBottom), .scroll(direction: .down, amount: .edge))
    }

    func testHalfPageIsNotAPointCount() {
        let half = CommandMap().action(for: .scrollHalfPageDown)
        let step = CommandMap().action(for: .scrollDown)
        XCTAssertNotEqual(half, step)
        guard case .scroll(_, let amount) = half else {
            return XCTFail("expected a scroll")
        }
        guard case .fractionOfPage(let numerator, let denominator) = amount else {
            return XCTFail("half page must be a page fraction, not \(amount)")
        }
        XCTAssertEqual(numerator, 1)
        XCTAssertEqual(denominator, 2)
    }

    func testEdgesAreOnlyTheVerticalExtremes() {
        for binding in CommandMap().bindings {
            guard case .scroll(let direction, .edge) = binding.action else { continue }
            XCTAssertTrue(direction == .up || direction == .down, binding.keys)
        }
        let edged = CommandMap().bindings.filter {
            if case .scroll(_, .edge) = $0.action { return true }
            return false
        }
        XCTAssertEqual(edged.map(\.keys), ["gg", "G"])
    }

    func testHistoryBackAndForwardAreCommandBracket() {
        let map = CommandMap()
        XCTAssertEqual(map.action(for: .historyBack), .sendShortcut(KeyCombo("[", modifiers: .command)))
        XCTAssertEqual(map.action(for: .historyForward), .sendShortcut(KeyCombo("]", modifiers: .command)))
    }

    func testPreviousAndNextTabAreCommandShiftBracket() {
        let map = CommandMap()
        XCTAssertEqual(
            map.action(for: .previousTab),
            .sendShortcut(KeyCombo("[", modifiers: [.command, .shift]))
        )
        XCTAssertEqual(
            map.action(for: .nextTab),
            .sendShortcut(KeyCombo("]", modifiers: [.command, .shift]))
        )
    }

    func testCloseNewReloadAndFindUseApplicationShortcuts() {
        let map = CommandMap()
        XCTAssertEqual(map.action(for: .close), .sendShortcut(KeyCombo("w", modifiers: .command)))
        XCTAssertEqual(map.action(for: .create), .sendShortcut(KeyCombo("t", modifiers: .command)))
        XCTAssertEqual(map.action(for: .reload), .sendShortcut(KeyCombo("r", modifiers: .command)))
        XCTAssertEqual(map.action(for: .find), .sendShortcut(KeyCombo("f", modifiers: .command)))
    }

    func testSingleShortcutsUseTheUnshiftedBaseCharacter() {
        let shifted: Set<Character> = ["[", "]"]
        for binding in CommandMap().bindings {
            guard case .sendShortcut(let combo) = binding.action else { continue }
            XCTAssertTrue(combo.character.isLowercase || shifted.contains(combo.character), binding.keys)
            if combo.character.isLetter {
                XCTAssertFalse(combo.modifiers.contains(.shift), binding.keys)
            }
            XCTAssertFalse(combo.modifiers.contains(.control), binding.keys)
            XCTAssertFalse(combo.modifiers.contains(.option), binding.keys)
        }
    }

    func testCopyURLIsCommandLThenCommandC() {
        let action = CommandMap().action(for: .copyURL)
        XCTAssertEqual(
            action,
            .sequence([
                .sendShortcut(KeyCombo("l", modifiers: .command)),
                .sendShortcut(KeyCombo("c", modifiers: .command)),
            ])
        )
        guard case .sequence(let steps) = action else {
            return XCTFail("expected a sequence")
        }
        XCTAssertEqual(steps.count, 2)
        for step in steps {
            guard case .sendShortcut = step else {
                return XCTFail("copy URL must be a flat list of shortcuts, got \(step)")
            }
        }
    }

    func testCopyURLIsPromisedOnlyForTheSpecApplicationNames() {
        let binding = CommandMap().bindings.first { $0.command == .copyURL }
        XCTAssertEqual(binding?.keys, "yy")
        XCTAssertEqual(binding?.promisedApplicationNames, ["Safari", "Chromium"])
        let others = CommandMap().bindings.filter { $0.command != .copyURL }
        XCTAssertTrue(others.allSatisfy { $0.promisedApplicationNames == nil })
    }

    func testCommandMapDoesNotChooseBundleIdentifiers() {
        let names = CommandMap().bindings.flatMap { $0.promisedApplicationNames ?? [] }
        XCTAssertEqual(names, ["Safari", "Chromium"])
        for name in names {
            XCTAssertFalse(name.contains("."))
            XCTAssertFalse(name.contains("com."))
        }
    }

    func testFBeginsCommandClickAndDoesNotSendAShortcut() {
        let map = CommandMap()
        let action = map.action(for: .hint(.command))
        XCTAssertEqual(action, .beginHint(.command))
        XCTAssertNotEqual(action, .beginHint(.plain))
        guard case .beginHint(.command) = action else {
            return XCTFail("F must begin a Command-click hint, got \(action)")
        }
        let binding = map.bindings.first { $0.command == .hint(.command) }
        XCTAssertEqual(binding?.deviatesFromVimium, true)
        XCTAssertEqual(binding?.summary, "Command-click hint")
        let summary = binding?.summary ?? ""
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("context menu"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("right-click"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("new tab"))
    }

    func testPlainHintIsNotCommandClick() {
        XCTAssertEqual(CommandMap().action(for: .hint(.plain)), .beginHint(.plain))
        let binding = CommandMap().bindings.first { $0.command == .hint(.plain) }
        XCTAssertEqual(binding?.deviatesFromVimium, false)
        XCTAssertEqual(binding?.summary, "Hint")
    }

    func testFocusFirstInputDoesNotAlsoEnterInsert() {
        let map = CommandMap()
        XCTAssertEqual(map.action(for: .focusFirstInput), .focusFirstInput)
        XCTAssertEqual(map.action(for: .manualInsert), .enterInsert)
        XCTAssertNotEqual(map.action(for: .focusFirstInput), map.action(for: .manualInsert))
    }

    func testHelpShowsHelpAndDoesNotToggleInsideTheMap() {
        let map = CommandMap()
        XCTAssertEqual(map.action(for: .help), .showHelp)
        let binding = map.bindings.first { $0.command == .help }
        XCTAssertEqual(binding?.keys, "?")
        XCTAssertEqual(binding?.deviatesFromVimium, true)
        XCTAssertEqual(binding?.summary, "Show help")
    }

    func testFindUsesTheAppShortcutAndIsMarkedAsAVimiumDeviation() {
        let binding = CommandMap().bindings.first { $0.command == .find }
        XCTAssertEqual(binding?.action, .sendShortcut(KeyCombo("f", modifiers: .command)))
        XCTAssertEqual(binding?.deviatesFromVimium, true)
        XCTAssertEqual(binding?.summary, "Find with the app shortcut")
    }

    func testOnlyFFindAndHelpDeviateFromVimium() {
        let keys = CommandMap().bindings.filter(\.deviatesFromVimium).map(\.keys)
        XCTAssertEqual(keys, ["/", "F", "?"])
    }

    func testEscapeAndPassNextKeyAreActions() {
        let map = CommandMap()
        XCTAssertEqual(map.action(for: .escape), .escape)
        XCTAssertEqual(map.action(for: .passNextKey), .passNextKey)
    }

    func testUnknownKeysPassThrough() {
        let map = CommandMap()
        for character: Character in ["q", "z", "1", " ", "Y", "I", "D", "U"] {
            var parser = KeyParser(clock: ManualKeyClock())
            let step = parser.handle(KeyEvent(character))
            XCTAssertEqual(step.results, [.passThrough], String(character))
            XCTAssertEqual(map.disposition(for: step.results[0]), .passThrough, String(character))
        }
        XCTAssertEqual(map.disposition(for: .passThrough), .passThrough)
    }

    func testModifiedPlainKeysPassThrough() {
        var parser = KeyParser(clock: ManualKeyClock())
        let step = parser.handle(KeyEvent("j", modifiers: .command))
        XCTAssertEqual(step.results, [.passThrough])
        XCTAssertEqual(CommandMap().disposition(for: step.results[0]), .passThrough)
    }

    func testPauseChordIsNotACommandAction() {
        var parser = KeyParser(clock: ManualKeyClock())
        let step = parser.handle(KeyEvent("v", modifiers: [.control, .option]))
        XCTAssertEqual(step.results, [.passThrough])
        XCTAssertEqual(CommandMap().disposition(for: step.results[0]), .passThrough)
    }

    func testHeldPrefixIsSwallowed() {
        var parser = KeyParser(clock: ManualKeyClock())
        let step = parser.handle(KeyEvent("g"))
        XCTAssertEqual(step.results, [.waitingForPrefix])
        XCTAssertEqual(CommandMap().disposition(for: .waitingForPrefix), .swallow)
        XCTAssertEqual(CommandMap().disposition(for: step.results[0]), .swallow)
    }

    func testCancelledPrefixIsSwallowed() {
        let clock = ManualKeyClock()
        var parser = KeyParser(clock: clock)
        _ = parser.handle(KeyEvent("y"))
        clock.advance(by: 1000)
        XCTAssertEqual(parser.expirePendingPrefix(), .prefixCancelled)
        XCTAssertEqual(CommandMap().disposition(for: .prefixCancelled), .swallow)
    }

    func testFailedPrefixThenUnknownKeySwallowsThenPasses() {
        var parser = KeyParser(clock: ManualKeyClock())
        let map = CommandMap()
        let first = parser.handle(KeyEvent("g"))
        XCTAssertEqual(map.disposition(for: first.results[0]), .swallow)
        let second = parser.handle(KeyEvent("z"))
        XCTAssertEqual(second.results, [.prefixCancelled, .passThrough])
        XCTAssertEqual(map.disposition(for: second.results[0]), .swallow)
        XCTAssertEqual(map.disposition(for: second.results[1]), .passThrough)
    }

    func testControlBracketPassesTheFollowingKey() {
        var parser = KeyParser(clock: ManualKeyClock())
        let map = CommandMap()
        let armed = parser.handle(KeyEvent("]", modifiers: .control))
        XCTAssertEqual(armed.results, [.command(.passNextKey)])
        XCTAssertEqual(map.disposition(for: armed.results[0]), .perform(.passNextKey))
        let passed = parser.handle(KeyEvent("j"))
        XCTAssertEqual(passed.results, [.passThrough])
        XCTAssertEqual(map.disposition(for: passed.results[0]), .passThrough)
        let restored = parser.handle(KeyEvent("j"))
        XCTAssertEqual(restored.results, [.command(.scrollDown)])
        XCTAssertEqual(
            map.disposition(for: restored.results[0]),
            .perform(.scroll(direction: .down, amount: .points(60)))
        )
    }

    func testLookupIsStable() {
        let map = CommandMap()
        let first = map.bindings
        XCTAssertEqual(map.action(for: .reload), map.action(for: .reload))
        XCTAssertEqual(map.disposition(for: .passThrough), map.disposition(for: .passThrough))
        XCTAssertEqual(map.bindings, first)
        let copy = map
        XCTAssertEqual(copy.bindings, map.bindings)
        XCTAssertEqual(copy.action(for: .scrollToTop), map.action(for: .scrollToTop))
    }
}

private struct ExpectedBinding {
    var keys: String
    var command: KeyCommand
    var action: Action
    var summary: String
    var deviatesFromVimium: Bool
    var promisedApplicationNames: [String]?
}

private let step = ScrollAmount.points(60)
private let half = ScrollAmount.fractionOfPage(numerator: 1, denominator: 2)

private func shortcut(_ character: Character, _ modifiers: KeyModifiers) -> Action {
    .sendShortcut(KeyCombo(character, modifiers: modifiers))
}

private let approvedBindings: [ExpectedBinding] = [
    ExpectedBinding(
        keys: "j",
        command: .scrollDown,
        action: .scroll(direction: .down, amount: step),
        summary: "Scroll down",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "k",
        command: .scrollUp,
        action: .scroll(direction: .up, amount: step),
        summary: "Scroll up",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "h",
        command: .scrollLeft,
        action: .scroll(direction: .left, amount: step),
        summary: "Scroll left",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "l",
        command: .scrollRight,
        action: .scroll(direction: .right, amount: step),
        summary: "Scroll right",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "d",
        command: .scrollHalfPageDown,
        action: .scroll(direction: .down, amount: half),
        summary: "Scroll down half a page",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "u",
        command: .scrollHalfPageUp,
        action: .scroll(direction: .up, amount: half),
        summary: "Scroll up half a page",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "gg",
        command: .scrollToTop,
        action: .scroll(direction: .up, amount: .edge),
        summary: "Scroll to the top",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "G",
        command: .scrollToBottom,
        action: .scroll(direction: .down, amount: .edge),
        summary: "Scroll to the bottom",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "gi",
        command: .focusFirstInput,
        action: .focusFirstInput,
        summary: "Focus the first input",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "Ctrl+]",
        command: .passNextKey,
        action: .passNextKey,
        summary: "Pass the next key",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "H",
        command: .historyBack,
        action: shortcut("[", .command),
        summary: "History back",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "L",
        command: .historyForward,
        action: shortcut("]", .command),
        summary: "History forward",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "J",
        command: .previousTab,
        action: shortcut("[", [.command, .shift]),
        summary: "Previous tab",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "K",
        command: .nextTab,
        action: shortcut("]", [.command, .shift]),
        summary: "Next tab",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "x",
        command: .close,
        action: shortcut("w", .command),
        summary: "Close",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "t",
        command: .create,
        action: shortcut("t", .command),
        summary: "New",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "r",
        command: .reload,
        action: shortcut("r", .command),
        summary: "Reload",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "/",
        command: .find,
        action: shortcut("f", .command),
        summary: "Find with the app shortcut",
        deviatesFromVimium: true,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "yy",
        command: .copyURL,
        action: .sequence([
            shortcut("l", .command),
            shortcut("c", .command),
        ]),
        summary: "Copy URL",
        deviatesFromVimium: false,
        promisedApplicationNames: ["Safari", "Chromium"]
    ),
    ExpectedBinding(
        keys: "f",
        command: .hint(.plain),
        action: .beginHint(.plain),
        summary: "Hint",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "F",
        command: .hint(.command),
        action: .beginHint(.command),
        summary: "Command-click hint",
        deviatesFromVimium: true,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "?",
        command: .help,
        action: .showHelp,
        summary: "Show help",
        deviatesFromVimium: true,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "i",
        command: .manualInsert,
        action: .enterInsert,
        summary: "Insert",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
    ExpectedBinding(
        keys: "Esc",
        command: .escape,
        action: .escape,
        summary: "Escape",
        deviatesFromVimium: false,
        promisedApplicationNames: nil
    ),
]

private func events(for keys: String) -> [KeyEvent] {
    switch keys {
    case "Esc":
        return [KeyEvent(identity: .escape)]
    case "Ctrl+]":
        return [KeyEvent("]", modifiers: .control)]
    default:
        return keys.map { KeyEvent($0) }
    }
}

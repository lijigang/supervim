import XCTest
@testable import SupervimCore

/// Task 11's pure decision: which actions reach an actuator, and when a missed
/// scroll gives the original key back. Nothing here posts an event.
final class CommandFollowThroughTests: XCTestCase {
    func testScrollActionsArePreparedForTheActuator() {
        let amounts: [ScrollAmount] = [
            .points(60),
            .fractionOfPage(numerator: 1, denominator: 2),
            .edge,
        ]
        let directions: [ScrollDirection] = [.left, .down, .up, .right]
        for direction in directions {
            for amount in amounts {
                let action = Action.scroll(direction: direction, amount: amount)
                let prepared = CommandFollowThrough.prepare(decision(action))
                XCTAssertEqual(prepared.actuatorActions, [action])
                XCTAssertFalse(prepared.requestsFocus)
                XCTAssertEqual(prepared.decisionDelivery, .swallow)
            }
        }
    }

    func testAMissedScrollGivesTheKeyBack() {
        let prepared = CommandFollowThrough.prepare(decision(.scroll(direction: .down, amount: .points(60))))
        XCTAssertEqual(
            CommandFollowThrough.delivery(prepared: prepared, reports: [.passedThrough]),
            .passThrough
        )
        let edge = CommandFollowThrough.prepare(decision(.scroll(direction: .up, amount: .edge)))
        XCTAssertEqual(
            CommandFollowThrough.delivery(prepared: edge, reports: [.passedThrough]),
            .passThrough
        )
    }

    func testAPerformedScrollStaysSwallowed() {
        let prepared = CommandFollowThrough.prepare(decision(.scroll(direction: .up, amount: .points(60))))
        XCTAssertEqual(
            CommandFollowThrough.delivery(prepared: prepared, reports: [.performed]),
            .swallow
        )
    }

    func testOneMovingScrollKeepsTheKeyEvenIfAnotherMisses() {
        let prepared = PreparedCommand(
            decisionDelivery: .swallow,
            actuatorActions: [
                .scroll(direction: .down, amount: .points(60)),
                .scroll(direction: .up, amount: .points(60)),
            ],
            requestsFocus: false
        )
        XCTAssertEqual(
            CommandFollowThrough.delivery(prepared: prepared, reports: [.passedThrough, .performed]),
            .swallow
        )
        XCTAssertEqual(
            CommandFollowThrough.delivery(prepared: prepared, reports: [.passedThrough, .passedThrough]),
            .passThrough
        )
    }

    func testAScrollTheActuatorDoesNotOwnStaysSwallowed() {
        let prepared = CommandFollowThrough.prepare(decision(.scroll(direction: .left, amount: .points(60))))
        XCTAssertEqual(
            CommandFollowThrough.delivery(prepared: prepared, reports: [.notActuatorWork]),
            .swallow
        )
        XCTAssertEqual(
            CommandFollowThrough.delivery(prepared: prepared, reports: []),
            .swallow
        )
    }

    func testShortcutDeclineStaysSwallowed() {
        let copyURL = CommandMap().action(for: .copyURL)
        let prepared = CommandFollowThrough.prepare(decision(copyURL))
        XCTAssertEqual(prepared.actuatorActions, [copyURL])
        XCTAssertFalse(prepared.requestsFocus)
        if case .sequence(let steps) = copyURL {
            XCTAssertEqual(steps.count, 2)
        } else {
            XCTFail("yy stays one sequence so a decline cannot post the first shortcut")
        }
        XCTAssertEqual(
            CommandFollowThrough.delivery(prepared: prepared, reports: [.passedThrough]),
            .swallow
        )
        XCTAssertEqual(
            CommandFollowThrough.delivery(prepared: prepared, reports: [.performed]),
            .swallow
        )
    }

    func testSingleShortcutsAreActuatorWork() {
        let commands: [KeyCommand] = [
            .historyBack, .historyForward, .previousTab, .nextTab,
            .close, .create, .reload, .find,
        ]
        for command in commands {
            let action = CommandMap().action(for: command)
            let prepared = CommandFollowThrough.prepare(decision(action))
            XCTAssertEqual(prepared.actuatorActions, [action], "\(command)")
            XCTAssertFalse(prepared.requestsFocus)
        }
    }

    func testFocusFirstInputRequestsFocusAndDoesNotActuate() {
        let prepared = CommandFollowThrough.prepare(decision(.focusFirstInput))
        XCTAssertTrue(prepared.requestsFocus)
        XCTAssertTrue(prepared.actuatorActions.isEmpty)
        XCTAssertEqual(
            CommandFollowThrough.delivery(prepared: prepared, reports: []),
            .swallow
        )
    }

    func testPassNextHintHelpInsertAndEscapeAreNotActuatorWork() {
        let actions: [Action] = [
            .passNextKey,
            .beginHint(.plain),
            .beginHint(.command),
            .showHelp,
            .escape,
            .enterInsert,
        ]
        for action in actions {
            let prepared = CommandFollowThrough.prepare(decision(action))
            XCTAssertTrue(prepared.actuatorActions.isEmpty, "\(action)")
            XCTAssertFalse(prepared.requestsFocus, "\(action)")
            XCTAssertEqual(CommandFollowThrough.delivery(prepared: prepared, reports: []), .swallow, "\(action)")
        }
    }

    func testAReleasedKeyStaysReleased() {
        let prepared = CommandFollowThrough.prepare(
            EventDecision(delivery: .passThrough, mode: .normal, actions: [])
        )
        XCTAssertTrue(prepared.actuatorActions.isEmpty)
        XCTAssertEqual(
            CommandFollowThrough.delivery(prepared: prepared, reports: []),
            .passThrough
        )
        let odd = PreparedCommand(
            decisionDelivery: .passThrough,
            actuatorActions: [.scroll(direction: .down, amount: .points(60))],
            requestsFocus: false
        )
        XCTAssertEqual(
            CommandFollowThrough.delivery(prepared: odd, reports: [.performed]),
            .passThrough
        )
    }

    func testAHeldPrefixIsNotGivenBack() {
        let prepared = CommandFollowThrough.prepare(
            EventDecision(delivery: .swallow, mode: .normal, actions: [])
        )
        XCTAssertFalse(prepared.requestsFocus)
        XCTAssertEqual(CommandFollowThrough.delivery(prepared: prepared, reports: []), .swallow)
    }

    func testFollowThroughSourceStaysInCore() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimCore/CommandFollowThrough.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        for token in [
            "import AppKit",
            "import ApplicationServices",
            "import CoreGraphics",
            "AXUIElement",
            "CGEvent",
            "URLSession",
            "print(",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
    }
}

private func decision(_ action: Action) -> EventDecision {
    EventDecision(delivery: .swallow, mode: .normal, actions: [action])
}

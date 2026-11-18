import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// Task 11 wires scroll commands and application shortcuts to the actuator.
/// `gi` focuses the cached first input and enters Insert only after the focus
/// read is editable. Ctrl+] passes the next key through without posting it.
/// The key path reads a snapshot. It does not walk the accessibility tree.
final class NormalCommandSessionTests: XCTestCase {
    /// After Esc the caret is still in the composer. `k` wheels the chat
    /// history, at that area's center, and does not wheel the composer.
    func testNormalKWheelsTheChatHistoryInsteadOfTheComposer() {
        let composerFrame = ActuatorRect(x: 0, y: 520, width: 800, height: 80)
        let chatFrame = ActuatorRect(x: 0, y: 0, width: 800, height: 500)
        let composer = sessionArea(
            "composer",
            frame: composerFrame,
            depth: 4,
            travelUp: 40,
            travelDown: 40,
            role: "AXScrollArea",
            textInput: true
        )
        let chat = sessionArea(
            "history",
            frame: chatFrame,
            depth: 1,
            travelUp: 900,
            travelDown: 40,
            role: "AXScrollArea"
        )
        let fixture = composerSession(
            areas: [composer, chat],
            pointer: ActuatorPoint(x: 400, y: 560)
        )
        _ = fixture.session.handleKeyDown(KeyEvent(identity: .escape))
        let performance = fixture.session.handleKeyDown(KeyEvent("k"))
        XCTAssertEqual(performance.mode, .normal)
        XCTAssertEqual(performance.delivery, .swallow)
        // The pointer is over the composer. A wheel goes to what is under
        // the pointer, so the pointer is put on the history first.
        XCTAssertEqual(fixture.poster.effects.first, .pointerMove(to: ActuatorPoint(x: 400, y: 250)))
        guard case .pointerScroll(let target, _, _, let location, let horizontal, let vertical) =
            fixture.poster.effects.last
        else {
            return XCTFail("expected a wheel event, got \(fixture.poster.effects)")
        }
        XCTAssertEqual(fixture.poster.effects.count, 2)
        XCTAssertEqual(target, "history")
        XCTAssertEqual(location, ActuatorPoint(x: 400, y: 250))
        XCTAssertEqual(horizontal, 0)
        XCTAssertGreaterThan(vertical, 0)
    }

    /// `k` in Normal must not reach the composer as a typed character.
    func testNormalKIsNotDeliveredToTheComposer() {
        let scrolling = composerSession(
            areas: [
                sessionArea(
                    "history",
                    frame: ActuatorRect(x: 0, y: 0, width: 800, height: 500),
                    travelUp: 400,
                    role: "AXWebArea"
                ),
            ],
            pointer: ActuatorPoint(x: 20, y: 20)
        )
        _ = scrolling.session.handleKeyDown(KeyEvent(identity: .escape))
        let moved = scrolling.session.handleSystemRecord(sampleKey(keyCode: 0x28, unicode: "k"))
        XCTAssertEqual(moved.mode, .normal)
        XCTAssertEqual(moved.delivery, .swallow)
        XCTAssertFalse(scrolling.poster.effects.isEmpty)

        let stuck = composerSession(areas: [], ready: true, pointer: ActuatorPoint(x: 400, y: 560))
        _ = stuck.session.handleKeyDown(KeyEvent(identity: .escape))
        let held = stuck.session.handleSystemRecord(sampleKey(keyCode: 0x28, unicode: "k"))
        XCTAssertEqual(held.mode, .normal)
        XCTAssertEqual(held.delivery, .swallow)
        XCTAssertTrue(stuck.poster.effects.isEmpty)
    }

    func testHeldNormalKWheelsABarlessWebAreaFromTheStructuralList() {
        let fixture = composerSession(areas: [], pointer: ActuatorPoint(x: 12, y: 16))
        let page = sessionArea(
            "page",
            frame: ActuatorRect(x: 0, y: 0, width: 400, height: 300),
            travelUp: 1,
            role: "AXWebArea"
        )
        fixture.session.replaceSnapshot(
            CommandSnapshot(
                scrollAreas: [],
                scrollCatalogReady: true,
                firstInput: .none,
                focusPoint: nil,
                structuralAreas: [page]
            )
        )
        _ = fixture.session.handleKeyDown(KeyEvent(identity: .escape))
        let performance = fixture.session.handleKeyDown(KeyEvent("k"))
        XCTAssertEqual(performance.delivery, .swallow)
        XCTAssertEqual(performance.mode, .normal)
        guard case .pointerScroll(let target, _, _, let location, _, let vertical) = fixture.poster.effects.first else {
            return XCTFail("expected a wheel event, got \(fixture.poster.effects)")
        }
        XCTAssertEqual(target, "page")
        // The pointer is already on the page.
        XCTAssertEqual(location, ActuatorPoint(x: 12, y: 16))
        XCTAssertGreaterThan(vertical, 0)
    }

    func testScrollKeysPostTheSameEffectAsTheActuator() {
        let keys: [(Character, KeyCommand)] = [
            ("j", .scrollDown),
            ("k", .scrollUp),
            ("h", .scrollLeft),
            ("l", .scrollRight),
            ("d", .scrollHalfPageDown),
            ("u", .scrollHalfPageUp),
            ("G", .scrollToBottom),
        ]
        for (key, command) in keys {
            let fixture = makeSession(bundle: "com.apple.Safari")
            let performance = fixture.session.handleKeyDown(KeyEvent(key))
            let expected = direct(
                CommandMap().action(for: command),
                bundle: "com.apple.Safari",
                areas: aimedPage(),
                pointer: pagePointer
            )
            XCTAssertEqual(performance.delivery, .swallow, String(key))
            XCTAssertEqual(performance.mode, .normal, String(key))
            XCTAssertEqual(performance.outcomes, [expected.outcome], String(key))
            XCTAssertEqual(fixture.poster.effects, expected.effects, String(key))
            XCTAssertEqual(fixture.reader.windowReads, 0, String(key))
            XCTAssertEqual(fixture.reader.focusedReads, 0, String(key))
            XCTAssertEqual(fixture.pointer.reads, 1, String(key))
        }
    }

    func testGGOnAWebPageWheelsThePageUnderThePointer() {
        var page = pageArea()
        page.role = "AXWebArea"
        let fixture = makeSession(bundle: "com.apple.Safari", areas: [page])
        let prefix = fixture.session.handleKeyDown(KeyEvent("g"))
        XCTAssertEqual(prefix.delivery, .swallow)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        let performance = fixture.session.handleKeyDown(KeyEvent("g"))
        XCTAssertEqual(performance.delivery, .swallow)
        XCTAssertEqual(performance.mode, .normal)
        guard case .pointerScroll(let target, _, _, let location, let horizontal, let vertical) =
            fixture.poster.effects.first
        else {
            return XCTFail("expected a wheel at the page center, got \(fixture.poster.effects)")
        }
        XCTAssertEqual(target, "page")
        XCTAssertEqual(location, pagePointer)
        XCTAssertEqual(horizontal, 0)
        XCTAssertGreaterThan(vertical, 1000)
    }

    func testShiftGOnAWebPageWheelsTowardTheBottom() {
        var page = pageArea()
        page.role = "AXWebArea"
        let fixture = makeSession(bundle: "com.apple.Safari", areas: [page])
        let performance = fixture.session.handleSystemRecord(
            sampleKey(keyCode: 0x05, flags: SystemModifierMask.shift, unicode: "G")
        )
        XCTAssertEqual(performance.delivery, .swallow)
        XCTAssertEqual(performance.mode, .normal)
        guard case .pointerScroll(let target, _, _, let location, _, let vertical) = fixture.poster.effects.first else {
            return XCTFail("expected a wheel at the page center, got \(fixture.poster.effects)")
        }
        XCTAssertEqual(target, "page")
        XCTAssertEqual(location, pagePointer)
        XCTAssertLessThan(vertical, -1000)
    }

    func testHeldNormalGGWheelsTheHistoryCenter() {
        let composerFrame = ActuatorRect(x: 0, y: 520, width: 800, height: 80)
        let chatFrame = ActuatorRect(x: 0, y: 0, width: 800, height: 500)
        let fixture = composerSession(
            areas: [
                sessionArea(
                    "composer",
                    frame: composerFrame,
                    depth: 4,
                    travelUp: 40,
                    travelDown: 40,
                    role: "AXScrollArea",
                    textInput: true
                ),
                sessionArea(
                    "history",
                    frame: chatFrame,
                    depth: 1,
                    travelUp: 900,
                    travelDown: 40,
                    role: "AXScrollArea"
                ),
            ],
            pointer: ActuatorPoint(x: 400, y: 560)
        )
        _ = fixture.session.handleKeyDown(KeyEvent(identity: .escape))
        _ = fixture.session.handleKeyDown(KeyEvent("g"))
        let performance = fixture.session.handleKeyDown(KeyEvent("g"))
        XCTAssertEqual(performance.mode, .normal)
        XCTAssertEqual(performance.delivery, .swallow)
        XCTAssertEqual(fixture.poster.effects.first, .pointerMove(to: ActuatorPoint(x: 400, y: 250)))
        guard case .pointerScroll(let target, _, _, let location, _, let vertical) = fixture.poster.effects.last else {
            return XCTFail("expected a wheel at the history center, got \(fixture.poster.effects)")
        }
        XCTAssertEqual(target, "history")
        XCTAssertEqual(location, ActuatorPoint(x: 400, y: 250))
        XCTAssertGreaterThan(vertical, 1000)
    }

    func testGGScrollsToTheTopAfterThePrefix() {
        let fixture = makeSession(bundle: "com.apple.Safari")
        let prefix = fixture.session.handleKeyDown(KeyEvent("g"))
        XCTAssertEqual(prefix.delivery, .swallow)
        XCTAssertTrue(prefix.outcomes.isEmpty)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        let performance = fixture.session.handleKeyDown(KeyEvent("g"))
        let expected = direct(
            CommandMap().action(for: .scrollToTop),
            bundle: "com.apple.Safari",
            areas: aimedPage(),
            pointer: pagePointer
        )
        XCTAssertEqual(performance.delivery, .swallow)
        XCTAssertEqual(performance.outcomes, [expected.outcome])
        XCTAssertEqual(fixture.poster.effects, expected.effects)
    }

    func testRepeatedScrollKeepsUsingTheSnapshot() {
        let fixture = makeSession(bundle: "com.apple.Safari")
        let first = fixture.session.handleKeyDown(KeyEvent("j"))
        let second = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(first.outcomes, second.outcomes)
        XCTAssertEqual(fixture.poster.effects.count, 2)
        XCTAssertEqual(fixture.reader.windowReads, 0)
    }

    func testAReadyCatalogWithNoAreaWheelsAtThePointer() {
        let fixture = makeSession(bundle: "com.apple.Safari", areas: [], ready: true)
        let performance = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(performance.delivery, .swallow)
        XCTAssertEqual(fixture.poster.effects, [
            .pointerScroll(
                targetID: "window",
                direction: .down,
                amount: .points(60),
                location: pagePointer,
                horizontal: 0,
                vertical: -60
            ),
        ])
        XCTAssertEqual(fixture.reader.windowReads, 0)
    }

    func testAScrollWithNoPointerAndNoWindowPassesTheKey() {
        let fixture = makeSession(bundle: "com.apple.Safari", areas: [], ready: true, pointer: nil)
        let performance = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(performance.delivery, .passThrough)
        XCTAssertEqual(performance.outcomes, [.passedThrough])
        XCTAssertTrue(fixture.poster.effects.isEmpty)
    }

    func testAnUnreadyCatalogDoesNotNameAStaleArea() {
        let fixture = makeSession(bundle: "com.apple.Safari", areas: [pageArea()], ready: false)
        let performance = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(performance.delivery, .swallow)
        guard case .pointerScroll(let target, _, _, let location, _, _) = fixture.poster.effects.first else {
            return XCTFail("expected a wheel at the pointer, got \(fixture.poster.effects)")
        }
        XCTAssertEqual(target, "window")
        XCTAssertEqual(location, pagePointer)
        XCTAssertEqual(fixture.poster.effects.count, 1)
    }

    func testAStalePointerFlagDoesNotMoveThePointer() {
        var stale = pageArea()
        stale.containsPointer = true
        stale.isFocusContainer = true
        stale.frame = ActuatorRect(x: 0, y: 0, width: 10, height: 10)
        let fixture = makeSession(
            bundle: "com.apple.Safari",
            areas: [stale],
            focus: nil,
            pointer: ActuatorPoint(x: 400, y: 400)
        )
        let performance = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(performance.delivery, .swallow)
        XCTAssertEqual(fixture.poster.effects, [
            .pointerScroll(
                targetID: "window",
                direction: .down,
                amount: .points(60),
                location: ActuatorPoint(x: 400, y: 400),
                horizontal: 0,
                vertical: -60
            ),
        ])
    }

    func testFocusPointScrollsWhenThePointerIsMissing() {
        let fixture = makeSession(
            bundle: "com.apple.Notes",
            areas: [pageArea()],
            focus: pagePointer,
            pointer: nil
        )
        let performance = fixture.session.handleKeyDown(KeyEvent("k"))
        XCTAssertEqual(performance.delivery, .swallow)
        let center = ActuatorPoint(x: 100, y: 100)
        XCTAssertEqual(fixture.poster.effects, [
            .pointerMove(to: center),
            .pointerScroll(
                targetID: "page",
                direction: .up,
                amount: .points(60),
                location: center,
                horizontal: 0,
                vertical: 60
            ),
        ])
    }

    func testCopyURLPostsOnlyForThePromisedBrowserList() {
        XCTAssertTrue(PromisedApplications.browserBundleIdentifiers.contains("com.apple.Safari"))
        XCTAssertTrue(PromisedApplications.browserBundleIdentifiers.contains("com.google.Chrome"))
        XCTAssertFalse(PromisedApplications.browserBundleIdentifiers.contains("org.mozilla.firefox"))
        XCTAssertFalse(PromisedApplications.browserBundleIdentifiers.contains("com.operasoftware.Opera"))
        let action = CommandMap().action(for: .copyURL)
        for bundle in PromisedApplications.browserBundleIdentifiers {
            let fixture = makeSession(bundle: bundle)
            let prefix = fixture.session.handleKeyDown(KeyEvent("y"))
            XCTAssertTrue(fixture.poster.effects.isEmpty, bundle)
            XCTAssertTrue(prefix.outcomes.isEmpty, bundle)
            let performance = fixture.session.handleKeyDown(KeyEvent("y"))
            let expected = direct(action, bundle: bundle, areas: [], pointer: nil)
            XCTAssertEqual(performance.delivery, .swallow, bundle)
            XCTAssertEqual(performance.outcomes, [expected.outcome], bundle)
            XCTAssertEqual(fixture.poster.effects, expected.effects, bundle)
            XCTAssertEqual(fixture.poster.effects.count, 2, bundle)
            XCTAssertEqual(fixture.pointer.reads, 0, bundle)
        }
        for bundle in ["com.apple.Notes", "com.apple.Finder", "org.mozilla.firefox", "com.operasoftware.Opera", "com.apple.safari", "com.apple.Safari "] {
            let fixture = makeSession(bundle: bundle)
            _ = fixture.session.handleKeyDown(KeyEvent("y"))
            let performance = fixture.session.handleKeyDown(KeyEvent("y"))
            XCTAssertEqual(performance.delivery, .swallow, bundle)
            XCTAssertEqual(performance.outcomes, [.passedThrough], bundle)
            XCTAssertTrue(fixture.poster.effects.isEmpty, bundle)
        }
    }

    func testHistoryAndTabsUseTheSameBrowserList() {
        let commands: [KeyCommand] = [.historyBack, .historyForward, .previousTab, .nextTab]
        let keys: [Character] = ["H", "L", "J", "K"]
        for (command, key) in zip(commands, keys) {
            let safari = makeSession(bundle: "com.apple.Safari")
            let posted = safari.session.handleKeyDown(KeyEvent(key))
            let expected = direct(CommandMap().action(for: command), bundle: "com.apple.Safari", areas: [], pointer: nil)
            XCTAssertEqual(posted.delivery, .swallow, String(key))
            XCTAssertEqual(posted.outcomes, [expected.outcome], String(key))
            XCTAssertEqual(safari.poster.effects, expected.effects, String(key))

            let notes = makeSession(bundle: "com.apple.Notes")
            let declined = notes.session.handleKeyDown(KeyEvent(key))
            XCTAssertEqual(declined.delivery, .swallow, String(key))
            XCTAssertEqual(declined.outcomes, [.passedThrough], String(key))
            XCTAssertTrue(notes.poster.effects.isEmpty, String(key))
        }
    }

    func testCloseNewReloadAndFindAreNotLimitedToBrowsers() {
        let commands: [(Character, KeyCommand)] = [
            ("x", .close),
            ("t", .create),
            ("r", .reload),
            ("/", .find),
        ]
        for (key, command) in commands {
            let fixture = makeSession(bundle: "com.apple.Notes")
            let performance = fixture.session.handleKeyDown(KeyEvent(key))
            let expected = direct(CommandMap().action(for: command), bundle: "com.apple.Notes", areas: [], pointer: nil)
            XCTAssertEqual(performance.delivery, .swallow, String(key))
            XCTAssertEqual(performance.outcomes, [expected.outcome], String(key))
            XCTAssertEqual(fixture.poster.effects, expected.effects, String(key))
            XCTAssertFalse(fixture.poster.effects.isEmpty, String(key))
        }
    }

    func testGIFocusesTheFirstInputAndEntersInsert() {
        let fixture = makeSession(bundle: "com.apple.Safari", first: .found(sampleInput(path: [2, 0])))
        fixture.reader.editableAfterAccept = true
        let prefix = fixture.session.handleKeyDown(KeyEvent("g"))
        XCTAssertTrue(fixture.focuser.paths.isEmpty)
        XCTAssertEqual(prefix.mode, .normal)
        let performance = fixture.session.handleKeyDown(KeyEvent("i"))
        XCTAssertEqual(fixture.focuser.paths, [[2, 0]])
        XCTAssertEqual(performance.focusedPath, [2, 0])
        XCTAssertEqual(performance.delivery, .swallow)
        XCTAssertEqual(performance.decision?.actions, [.focusFirstInput])
        XCTAssertEqual(performance.mode, .insert)
        XCTAssertEqual(fixture.reader.windowReads, 0)
        XCTAssertEqual(fixture.reader.focusedReads, 1)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        let typed = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(typed.delivery, .passThrough)
        XCTAssertEqual(typed.mode, .insert)
        XCTAssertTrue(typed.outcomes.isEmpty)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
    }

    func testGIDoesNotFocusWhenTheQueryIsMissingOrUnusable() {
        for query in [EditableInputQuery.none, .unavailable] {
            let fixture = makeSession(bundle: "com.apple.Safari", first: query)
            _ = fixture.session.handleKeyDown(KeyEvent("g"))
            let performance = fixture.session.handleKeyDown(KeyEvent("i"))
            XCTAssertTrue(fixture.focuser.paths.isEmpty, "\(query)")
            XCTAssertNil(performance.focusedPath, "\(query)")
            XCTAssertEqual(performance.delivery, .swallow, "\(query)")
            XCTAssertEqual(performance.mode, .normal, "\(query)")
            XCTAssertEqual(fixture.reader.focusedReads, 0, "\(query)")
            XCTAssertEqual(fixture.reader.windowReads, 0, "\(query)")
        }
    }

    func testGIDoesNotEnterInsertWhenFocusIsRejected() {
        let fixture = makeSession(bundle: "com.apple.Safari", first: .found(sampleInput(path: [0])))
        fixture.focuser.accept = false
        _ = fixture.session.handleKeyDown(KeyEvent("g"))
        let performance = fixture.session.handleKeyDown(KeyEvent("i"))
        XCTAssertEqual(fixture.focuser.paths, [[0]])
        XCTAssertEqual(performance.focusedPath, [0])
        XCTAssertEqual(performance.mode, .insert)
        guard case .mouseClick(let point, _, _) = fixture.poster.effects.first else {
            return XCTFail("expected a click at the field center, got \(fixture.poster.effects)")
        }
        XCTAssertEqual(point, ActuatorPoint(x: 16, y: 10))
    }

    /// Accessibility focus is rejected today, and `gi` then does nothing:
    /// the key is swallowed, Insert is not entered, and the field is not clicked.
    func testGIClicksTheFieldAndEntersInsertWhenAccessibilityFocusIsRejected() {
        let fixture = makeSession(bundle: "com.apple.Safari", first: .found(sampleInput(path: [0])))
        fixture.focuser.accept = false
        _ = fixture.session.handleKeyDown(KeyEvent("g"))
        let performance = fixture.session.handleKeyDown(KeyEvent("i"))
        XCTAssertEqual(fixture.focuser.paths, [[0]])
        XCTAssertEqual(performance.mode, .insert)
        XCTAssertEqual(performance.focusedPath, [0])
        guard case .mouseClick(let point, _, _) = fixture.poster.effects.first else {
            return XCTFail("expected a click at the field center, got \(fixture.poster.effects)")
        }
        XCTAssertEqual(point, ActuatorPoint(x: 16, y: 10))
        let typed = fixture.session.handleKeyDown(KeyEvent("a"))
        XCTAssertEqual(typed.delivery, .passThrough)
        XCTAssertEqual(typed.mode, .insert)
    }

    func testGIEntersInsertEvenWhenTheFollowUpReadIsNotEditable() {
        let fixture = makeSession(bundle: "com.apple.Safari", first: .found(sampleInput(path: [1])))
        fixture.reader.editableAfterAccept = false
        _ = fixture.session.handleKeyDown(KeyEvent("g"))
        let performance = fixture.session.handleKeyDown(KeyEvent("i"))
        XCTAssertEqual(performance.focusedPath, [1])
        XCTAssertEqual(performance.mode, .insert)
        XCTAssertEqual(fixture.reader.focusedReads, 1)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        let typed = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(typed.delivery, .passThrough)
        XCTAssertEqual(typed.mode, .insert)
    }

    func testControlBracketPassesTheNextKeyWithoutPosting() {
        let fixture = makeSession(bundle: "com.apple.Safari")
        let chord = fixture.session.handleSystemRecord(
            sampleKey(keyCode: 0x1E, flags: SystemModifierMask.control, unicode: "\u{1D}")
        )
        XCTAssertEqual(chord.delivery, .swallow)
        XCTAssertEqual(chord.decision?.actions, [.passNextKey])
        XCTAssertTrue(chord.outcomes.isEmpty)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        XCTAssertEqual(fixture.pointer.reads, 0)
        let passed = fixture.session.handleSystemRecord(sampleKey(keyCode: 0x26, unicode: "j"))
        XCTAssertEqual(passed.delivery, .passThrough)
        XCTAssertTrue(passed.outcomes.isEmpty)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        let scroll = fixture.session.handleSystemRecord(sampleKey(keyCode: 0x26, unicode: "j"))
        XCTAssertEqual(scroll.delivery, .swallow)
        XCTAssertEqual(scroll.outcomes.count, 1)
        XCTAssertFalse(fixture.poster.effects.isEmpty)
        XCTAssertEqual(fixture.reader.windowReads, 0)
    }

    func testAMarkedKeyDoesNotScrollOrConsumePassNext() {
        let fixture = makeSession(bundle: "com.apple.Safari")
        let marked = fixture.session.handleSystemRecord(
            sampleKey(keyCode: 0x26, unicode: "j", sourceUserData: SynthesizedEventMark.userData)
        )
        XCTAssertEqual(marked.delivery, .passThrough)
        XCTAssertNil(marked.decision)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        _ = fixture.session.handleSystemRecord(
            sampleKey(keyCode: 0x1E, flags: SystemModifierMask.control, unicode: "\u{1D}")
        )
        let markedAgain = fixture.session.handleSystemRecord(
            sampleKey(keyCode: 0x26, unicode: "j", sourceUserData: SynthesizedEventMark.userData)
        )
        XCTAssertNil(markedAgain.decision)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        let passed = fixture.session.handleSystemRecord(sampleKey(keyCode: 0x26, unicode: "j"))
        XCTAssertEqual(passed.delivery, .passThrough)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
    }

    func testSystemRecordForJPostsTheScroll() {
        let fixture = makeSession(bundle: "com.apple.Safari")
        let performance = fixture.session.handleSystemRecord(sampleKey(keyCode: 0x26, unicode: "j"))
        XCTAssertEqual(performance.delivery, .swallow)
        XCTAssertEqual(performance.decision?.actions, [CommandMap().action(for: .scrollDown)])
        XCTAssertFalse(fixture.poster.effects.isEmpty)
        XCTAssertEqual(fixture.reader.windowReads, 0)
    }

    func testUnclaimedHintAndHelpPassThroughAndManualInsertDoesNotPost() {
        let hint = makeSession(bundle: "com.apple.Safari")
        let started = hint.session.handleKeyDown(KeyEvent("f"))
        XCTAssertEqual(started.delivery, .passThrough)
        XCTAssertEqual(started.mode, .normal)
        XCTAssertNil(started.swallowReason)
        XCTAssertTrue(hint.poster.effects.isEmpty)
        let typed = hint.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(typed.delivery, .swallow)
        XCTAssertEqual(typed.swallowReason, .actuator)
        XCTAssertFalse(hint.poster.effects.isEmpty)

        let help = makeSession(bundle: "com.apple.Safari")
        let shown = help.session.handleKeyDown(KeyEvent("?"))
        XCTAssertEqual(shown.delivery, .passThrough)
        XCTAssertEqual(shown.decision?.actions, [.showHelp])
        XCTAssertEqual(shown.mode, .normal)
        XCTAssertTrue(help.poster.effects.isEmpty)

        let insert = makeSession(bundle: "com.apple.Safari")
        let entered = insert.session.handleKeyDown(KeyEvent("i"))
        XCTAssertEqual(entered.mode, .insert)
        XCTAssertTrue(insert.poster.effects.isEmpty)
        let passed = insert.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(passed.delivery, .passThrough)
        XCTAssertTrue(insert.poster.effects.isEmpty)
        XCTAssertEqual(insert.pointer.reads, 0)
    }

    func testUnknownFocusAndExcludedAppsPassTheKey() {
        let unknown = makeSession(bundle: "com.apple.Safari")
        unknown.pipeline.cache.replace(CachedFocus(editability: .unknown, bundleIdentifier: "com.apple.Safari"))
        let missed = unknown.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(missed.delivery, .passThrough)
        XCTAssertTrue(missed.outcomes.isEmpty)
        XCTAssertTrue(unknown.poster.effects.isEmpty)
        XCTAssertEqual(unknown.pointer.reads, 0)
        XCTAssertEqual(unknown.reader.windowReads, 0)

        let terminal = makeSession(bundle: "com.apple.Terminal")
        let passed = terminal.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(passed.delivery, .passThrough)
        XCTAssertTrue(terminal.poster.effects.isEmpty)
        XCTAssertEqual(terminal.reader.focusedReads, 0)
    }

    func testNormalEscapePassesWithoutPosting() {
        let fixture = makeSession(bundle: "com.apple.Safari")
        let performance = fixture.session.handleKeyDown(KeyEvent(identity: .escape))
        XCTAssertEqual(performance.delivery, .passThrough)
        XCTAssertTrue(performance.outcomes.isEmpty)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
    }

    func testSessionSourceDoesNotWalkOrPost() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimSystem/NormalCommandSession.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        for token in [
            "readFrontmostWindow",
            "AXUIElement",
            "CGEvent.post",
            "URLSession",
            "print(",
            "os_log",
            "NSLog",
            "import AppKit",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
        XCTAssertTrue(text.contains("scrollCatalogReady"))
        XCTAssertTrue(text.contains("focusInput"))
    }

    func testMacOSScrollAndFocusSourcesStayBehindTheImportGuard() throws {
        let reader = try String(
            contentsOf: repoRoot().appendingPathComponent("Sources/SupervimSystem/AXApplicationReader.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(reader.contains("kAXVerticalScrollBarAttribute"))
        XCTAssertTrue(reader.contains("kAXHorizontalScrollBarAttribute"))
        XCTAssertTrue(reader.contains("kAXValueAttribute"))
        XCTAssertTrue(reader.contains("kAXMinValueAttribute"))
        XCTAssertTrue(reader.contains("kAXMaxValueAttribute"))
        XCTAssertTrue(reader.contains("ScrollTargetIdentity.identifier"))
        XCTAssertTrue(reader.contains("CFGetTypeID"))
        XCTAssertFalse(reader.contains("kAXEditableAttribute"))
        XCTAssertFalse(reader.contains("as? AXUIElement"))
        XCTAssertFalse(reader.contains("as! AXUIElement"))

        let focuser = try String(
            contentsOf: repoRoot().appendingPathComponent("Sources/SupervimSystem/AXInputFocuser.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(focuser.contains("#if canImport(ApplicationServices)"))
        XCTAssertTrue(focuser.contains("kAXFocusedAttribute"))
        XCTAssertFalse(focuser.contains("kAXFocusedUIElementAttribute"))
        XCTAssertTrue(focuser.contains("AXUIElementSetAttributeValue"))
        XCTAssertTrue(focuser.contains("CFGetTypeID"))
        XCTAssertFalse(focuser.contains("kAXEditableAttribute"))
        XCTAssertFalse(focuser.contains("as? AXUIElement"))
        XCTAssertFalse(focuser.contains("as! AXUIElement"))
        for token in ["URLSession", "print(", "os_log", "NSLog"] {
            XCTAssertFalse(focuser.contains(token), token)
        }
    }

    func testEmptyScrollUsesThePointerWhenItIsInsideTheWindow() {
        let window = ActuatorRect(x: 0, y: 0, width: 800, height: 600)
        let fixture = makeSession(
            bundle: "com.tencent.xinWeChat",
            areas: [],
            ready: true,
            pointer: ActuatorPoint(x: 120, y: 80),
            window: window
        )
        let performance = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(performance.delivery, .swallow)
        guard case .pointerScroll(let target, _, _, let location, let horizontal, let vertical) =
            fixture.poster.effects.first
        else {
            return XCTFail("expected a wheel, got \(fixture.poster.effects)")
        }
        XCTAssertEqual(target, "window")
        XCTAssertEqual(location, ActuatorPoint(x: 120, y: 80))
        XCTAssertEqual(horizontal, 0)
        XCTAssertEqual(vertical, -60)
    }

    func testEmptyScrollUsesTheWindowCenterWhenThePointerIsOutside() {
        let window = ActuatorRect(x: 10, y: 20, width: 800, height: 600)
        let fixture = makeSession(
            bundle: "com.tencent.xinWeChat",
            areas: [],
            ready: true,
            pointer: ActuatorPoint(x: -50, y: -50),
            window: window
        )
        _ = fixture.session.handleKeyDown(KeyEvent("d"))
        XCTAssertEqual(fixture.poster.effects.first, .pointerMove(to: ActuatorPoint(x: 410, y: 320)))
        guard case .pointerScroll(_, _, _, let location, _, let vertical) = fixture.poster.effects.last else {
            return XCTFail("expected a half-page wheel, got \(fixture.poster.effects)")
        }
        XCTAssertEqual(location, ActuatorPoint(x: 410, y: 320))
        XCTAssertEqual(vertical, -300)
    }

    func testEmptyGGWheelsTheWindowCenter() {
        let window = ActuatorRect(x: 0, y: 0, width: 400, height: 300)
        let fixture = makeSession(
            bundle: "com.tencent.xinWeChat",
            areas: [],
            ready: true,
            pointer: nil,
            window: window
        )
        let performance = fixture.session.handleKeyDown(KeyEvent("G"))
        XCTAssertEqual(performance.delivery, .swallow)
        XCTAssertEqual(fixture.poster.effects.first, .pointerMove(to: ActuatorPoint(x: 200, y: 150)))
        XCTAssertEqual(fixture.poster.effects.count, 9)
        guard case .pointerScroll(_, let direction, _, let location, _, let vertical) =
            fixture.poster.effects.last
        else {
            return XCTFail("expected edge wheels, got \(fixture.poster.effects)")
        }
        XCTAssertEqual(direction, .down)
        XCTAssertEqual(location, ActuatorPoint(x: 200, y: 150))
        XCTAssertLessThan(vertical, 0)
    }

    func testGIWithoutAnInputShowsABannerAndDoesNotClick() {
        let banner = HintMissBanner(duration: 2)
        let fixture = makeSession(bundle: "com.apple.Safari", areas: [], first: .none, banner: banner)
        _ = fixture.session.handleKeyDown(KeyEvent("g"))
        let performance = fixture.session.handleKeyDown(KeyEvent("i"))
        XCTAssertEqual(performance.mode, .normal)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        XCTAssertEqual(banner.title(fallback: "Normal"), HintMissBanner.inputMissingMessage)
    }

    func testGIInWeChatClicksTheBottomCenterWhenTheTreeHasNoField() {
        let window = ActuatorRect(x: 0, y: 0, width: 800, height: 600)
        let fixture = makeSession(
            bundle: "com.tencent.xinWeChat",
            areas: [],
            first: .none,
            window: window,
            bundles: { ["com.tencent.xinWeChat"] }
        )
        _ = fixture.session.handleKeyDown(KeyEvent("g"))
        let performance = fixture.session.handleKeyDown(KeyEvent("i"))
        XCTAssertEqual(performance.mode, .insert)
        guard case .mouseClick(let point, _, _) = fixture.poster.effects.first else {
            return XCTFail("expected the composer heuristic, got \(fixture.poster.effects)")
        }
        XCTAssertEqual(point, ActuatorPoint(x: 400, y: 552))
        let typed = fixture.session.handleKeyDown(KeyEvent("a"))
        XCTAssertEqual(typed.mode, .insert)
        XCTAssertEqual(typed.delivery, .passThrough)
    }
}

/// How a copied window becomes scroll areas. Selection rules live next to this type.
final class ScrollAreaCatalogTests: XCTestCase {
    func testContentLengthBecomesPointTravelAndPointerFocusFlags() {
        let window = axNode(
            frame: ElementFrame(x: 0, y: 0, width: 100, height: 80),
            vertical: ScrollBarReading(value: 25, minimum: 0, maximum: 100, contentLength: 800)
        )
        let catalog = ScrollAreaCatalog.collect(
            window: window,
            pointer: ActuatorPoint(x: 10, y: 10),
            focus: ActuatorPoint(x: 90, y: 70)
        )
        XCTAssertTrue(catalog.ready)
        guard let area = onlyArea(catalog) else { return }
        XCTAssertEqual(area.identifier, "root")
        XCTAssertEqual(area.depth, 0)
        XCTAssertEqual(area.visibleWidth, 100)
        XCTAssertEqual(area.visibleHeight, 80)
        XCTAssertEqual(area.travelUp, 180)
        XCTAssertEqual(area.travelDown, 540)
        XCTAssertEqual(area.travelLeft, 0)
        XCTAssertEqual(area.travelRight, 0)
        XCTAssertEqual(area.contentHeight, 800)
        XCTAssertNil(area.contentWidth)
        XCTAssertTrue(area.containsPointer)
        XCTAssertTrue(area.isFocusContainer)
    }

    func testMissingContentLengthUsesAOnePointSentinelOffTheEdge() {
        let window = axNode(
            vertical: ScrollBarReading(value: 0, minimum: 0, maximum: 1, contentLength: nil),
            horizontal: ScrollBarReading(value: 1, minimum: 0, maximum: 1, contentLength: nil)
        )
        let catalog = ScrollAreaCatalog.collect(window: window, pointer: nil, focus: nil)
        XCTAssertTrue(catalog.ready)
        guard let area = onlyArea(catalog) else { return }
        XCTAssertEqual(area.travelUp, 0)
        XCTAssertEqual(area.travelDown, 1)
        XCTAssertEqual(area.travelLeft, 1)
        XCTAssertEqual(area.travelRight, 0)
        XCTAssertNil(area.contentHeight)
        XCTAssertNil(area.contentWidth)
        XCTAssertFalse(area.containsPointer)
        XCTAssertFalse(area.isFocusContainer)
    }

    func testHorizontalContentLengthUsesTheWidth() {
        let window = axNode(
            frame: ElementFrame(x: 0, y: 0, width: 50, height: 80),
            horizontal: ScrollBarReading(value: 10, minimum: 0, maximum: 40, contentLength: 250)
        )
        let catalog = ScrollAreaCatalog.collect(window: window, pointer: nil, focus: nil)
        guard let area = onlyArea(catalog) else { return }
        XCTAssertEqual(area.travelLeft, 50)
        XCTAssertEqual(area.travelRight, 150)
        XCTAssertEqual(area.contentWidth, 250)
        XCTAssertNil(area.contentHeight)
    }

    func testContentThatFitsTheFrameCannotMove() {
        let window = axNode(
            frame: ElementFrame(x: 0, y: 0, width: 50, height: 80),
            vertical: ScrollBarReading(value: 40, minimum: 0, maximum: 100, contentLength: 80)
        )
        let catalog = ScrollAreaCatalog.collect(window: window, pointer: nil, focus: nil)
        XCTAssertTrue(catalog.ready)
        guard let area = onlyArea(catalog) else { return }
        XCTAssertEqual(area.travelUp, 0)
        XCTAssertEqual(area.travelDown, 0)
        XCTAssertEqual(area.contentHeight, 80)
    }

    func testANonFiniteContentLengthFallsBackToTheSentinel() {
        let window = axNode(
            vertical: ScrollBarReading(value: 0.5, minimum: 0, maximum: 1, contentLength: .infinity)
        )
        let catalog = ScrollAreaCatalog.collect(window: window, pointer: nil, focus: nil)
        guard let area = onlyArea(catalog) else { return }
        XCTAssertEqual(area.travelUp, 1)
        XCTAssertEqual(area.travelDown, 1)
        XCTAssertNil(area.contentHeight)
    }

    func testUnusableBarsAndScrollAreasWithoutBarsAreOmitted() {
        let window = axNode(
            role: "AXWindow",
            children: [
                axNode(role: "AXScrollArea"),
                axNode(vertical: ScrollBarReading(value: .nan, minimum: 0, maximum: 1, contentLength: nil)),
                axNode(vertical: ScrollBarReading(value: 0, minimum: 5, maximum: 5, contentLength: nil)),
                axNode(role: "AXGroup", vertical: ScrollBarReading(value: 0.2, minimum: 0, maximum: 1, contentLength: nil)),
            ]
        )
        let catalog = ScrollAreaCatalog.collect(window: window, pointer: nil, focus: nil)
        XCTAssertTrue(catalog.ready)
        guard let area = onlyArea(catalog) else { return }
        XCTAssertEqual(area.identifier, "3")
        XCTAssertEqual(area.depth, 1)
        XCTAssertEqual(area.travelDown, 1)
        XCTAssertEqual(catalog.structural.map(\.identifier), ["0"])
        XCTAssertEqual(catalog.structural.map(\.role), ["AXScrollArea"])
    }

    func testWebAreaWithoutAScrollBarIsAStructuralWheelTarget() {
        let window = axNode(
            role: "AXWindow",
            frame: ElementFrame(x: 0, y: 0, width: 400, height: 300),
            children: [
                axNode(role: "AXWebArea", frame: ElementFrame(x: 0, y: 40, width: 400, height: 260)),
                axNode(role: "AXTextArea", frame: ElementFrame(x: 0, y: 0, width: 10, height: 10)),
            ]
        )
        let catalog = ScrollAreaCatalog.collect(window: window, pointer: nil, focus: nil)
        XCTAssertTrue(catalog.areas.isEmpty)
        XCTAssertEqual(catalog.structural.map(\.identifier), ["0"])
        XCTAssertEqual(catalog.structural.first?.role, "AXWebArea")
        XCTAssertEqual(catalog.structural.first?.travelUp, 1)
        XCTAssertEqual(catalog.structural.first?.frame, ActuatorRect(x: 0, y: 40, width: 400, height: 260))
    }

    func testNestedAreasKeepPathIdentifiers() {
        let window = axNode(
            children: [
                axNode(
                    vertical: ScrollBarReading(value: 0, minimum: 0, maximum: 1, contentLength: nil),
                    children: [
                        axNode(horizontal: ScrollBarReading(value: 0, minimum: 0, maximum: 1, contentLength: nil)),
                    ]
                ),
            ]
        )
        let catalog = ScrollAreaCatalog.collect(window: window, pointer: ActuatorPoint(x: 1, y: 1), focus: nil)
        XCTAssertTrue(catalog.ready)
        XCTAssertEqual(catalog.areas.map(\.identifier), ["0", "0/0"])
        XCTAssertEqual(catalog.areas.map(\.depth), [1, 2])
        guard let outer = catalog.areas.first else { return }
        XCTAssertTrue(outer.containsPointer)
    }

    func testAZeroFrameIsSkipped() {
        let window = axNode(
            children: [
                axNode(
                    frame: ElementFrame(x: 0, y: 0, width: 0, height: 20),
                    vertical: ScrollBarReading(value: 0, minimum: 0, maximum: 1, contentLength: nil)
                ),
            ]
        )
        let catalog = ScrollAreaCatalog.collect(window: window, pointer: nil, focus: nil)
        XCTAssertTrue(catalog.ready)
        XCTAssertTrue(catalog.areas.isEmpty)
    }

    func testThePointerOnTheInclusiveEdgeCounts() {
        let window = axNode(
            frame: ElementFrame(x: 0, y: 0, width: 10, height: 10),
            vertical: ScrollBarReading(value: 0, minimum: 0, maximum: 1, contentLength: nil)
        )
        let inside = ScrollAreaCatalog.collect(window: window, pointer: ActuatorPoint(x: 10, y: 10), focus: nil)
        guard let insideArea = onlyArea(inside) else { return }
        XCTAssertTrue(insideArea.containsPointer)
        let outside = ScrollAreaCatalog.collect(window: window, pointer: ActuatorPoint(x: 10.1, y: 10), focus: nil)
        guard let outsideArea = onlyArea(outside) else { return }
        XCTAssertFalse(outsideArea.containsPointer)
    }

    func testTruncationDropsEveryArea() {
        let truncatedChild = axNode(
            vertical: ScrollBarReading(value: 0, minimum: 0, maximum: 1, contentLength: nil),
            childrenTruncated: true
        )
        let catalog = ScrollAreaCatalog.collect(window: truncatedChild, pointer: nil, focus: nil)
        XCTAssertFalse(catalog.ready)
        XCTAssertTrue(catalog.areas.isEmpty)

        let hidden = axNode(
            children: [
                axNode(vertical: ScrollBarReading(value: 0, minimum: 0, maximum: 1, contentLength: nil)),
            ]
        )
        let capped = ScrollAreaCatalog.collect(
            window: hidden,
            pointer: nil,
            focus: nil,
            limits: TreeWalkLimits(maxNodes: 1, maxDepth: 32)
        )
        XCTAssertFalse(capped.ready)
        XCTAssertTrue(capped.areas.isEmpty)
    }

    func testRetargetRecomputesFlagsWithoutChangingTravel() {
        var area = pageArea()
        area.containsPointer = true
        area.isFocusContainer = false
        let moved = ScrollAreaCatalog.retarget(
            [area],
            pointer: ActuatorPoint(x: 400, y: 400),
            focus: pagePointer
        )
        XCTAssertEqual(moved.count, 1)
        XCTAssertFalse(moved[0].containsPointer)
        XCTAssertTrue(moved[0].isFocusContainer)
        XCTAssertEqual(moved[0].travelDown, area.travelDown)
        XCTAssertEqual(moved[0].identifier, area.identifier)
        let cleared = ScrollAreaCatalog.retarget([area], pointer: nil, focus: nil)
        XCTAssertFalse(cleared[0].containsPointer)
        XCTAssertFalse(cleared[0].isFocusContainer)
        XCTAssertTrue(ScrollAreaCatalog.retarget([], pointer: pagePointer, focus: pagePointer).isEmpty)
    }

    func testBuilderUsesTheCenterOfTheFocusedFrame() {
        let frame = ElementFrame(x: 10, y: 4, width: 30, height: 8)
        XCTAssertEqual(
            ScrollAreaCatalog.focusPoint(of: frame),
            ActuatorPoint(x: 25, y: 8)
        )
        XCTAssertNil(ScrollAreaCatalog.focusPoint(of: nil))
        XCTAssertNil(ScrollAreaCatalog.focusPoint(of: ElementFrame(x: 0, y: 0, width: 0, height: 4)))
        XCTAssertNil(ScrollAreaCatalog.focusPoint(of: ElementFrame(x: .nan, y: 0, width: 4, height: 4)))

        let built = CommandSnapshotBuilder.make(
            window: .unavailable,
            focusedFrame: frame,
            firstInput: .none
        )
        XCTAssertFalse(built.scrollCatalogReady)
        XCTAssertTrue(built.scrollAreas.isEmpty)
        XCTAssertEqual(built.firstInput, .none)
        XCTAssertEqual(built.focusPoint, ActuatorPoint(x: 25, y: 8))

        let window = axNode(vertical: ScrollBarReading(value: 0, minimum: 0, maximum: 1, contentLength: nil))
        let ready = CommandSnapshotBuilder.make(
            window: .value(window),
            focusedFrame: frame,
            firstInput: .found(sampleInput(path: [4]))
        )
        XCTAssertTrue(ready.scrollCatalogReady)
        XCTAssertEqual(ready.scrollAreas.count, 1)
        XCTAssertEqual(ready.firstInput, .found(sampleInput(path: [4])))
        XCTAssertEqual(ready.focusPoint, ActuatorPoint(x: 25, y: 8))
    }

    func testCatalogSourceStatesTheHitRule() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimSystem/ScrollAreaCatalog.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("A node with no usable scroll bar is not a target"))
        XCTAssertTrue(text.contains("Truncation drops every area"))
        XCTAssertTrue(text.contains("contentLength"))
        XCTAssertEqual(ScrollTargetIdentity.identifier(path: []), "root")
        XCTAssertEqual(ScrollTargetIdentity.identifier(path: [0, 2]), "0/2")
        for token in ["import AppKit", "import CoreGraphics", "AXUIElement", "CGEvent", "URLSession", "print("] {
            XCTAssertFalse(text.contains(token), token)
        }
    }
}

private let pagePointer = ActuatorPoint(x: 20, y: 30)

private func sessionArea(
    _ identifier: String,
    frame: ActuatorRect,
    depth: Int = 1,
    travelUp: Double = 0,
    travelDown: Double = 0,
    role: String? = nil,
    textInput: Bool = false
) -> ScrollArea {
    ScrollArea(
        identifier: identifier,
        frame: frame,
        depth: depth,
        containsPointer: false,
        isFocusContainer: false,
        visibleWidth: frame.width,
        visibleHeight: frame.height,
        travelLeft: 0,
        travelDown: travelDown,
        travelUp: travelUp,
        travelRight: 0,
        contentWidth: nil,
        contentHeight: frame.height + travelUp + travelDown,
        role: role,
        isTextInput: textInput
    )
}

private func composerFocus() -> CachedFocus {
    CachedFocus(
        editability: .editable,
        bundleIdentifier: "com.tencent.xinWeChat",
        elementIdentity: "composer",
        frame: FocusFrame(x: 0, y: 520, width: 800, height: 80),
        role: "AXTextArea"
    )
}

private func composerSession(
    areas: [ScrollArea],
    ready: Bool = true,
    pointer: ActuatorPoint?
) -> SessionFixture {
    let fixture = makeSession(
        bundle: "com.tencent.xinWeChat",
        areas: areas,
        ready: ready,
        focus: nil,
        pointer: pointer
    )
    fixture.pipeline.cache.replace(composerFocus())
    return fixture
}

private func pageArea() -> ScrollArea {
    ScrollArea(
        identifier: "page",
        frame: ActuatorRect(x: 0, y: 0, width: 200, height: 200),
        depth: 1,
        containsPointer: false,
        isFocusContainer: false,
        visibleWidth: 200,
        visibleHeight: 200,
        travelLeft: 1000,
        travelDown: 1000,
        travelUp: 1000,
        travelRight: 1000,
        contentWidth: 2000,
        contentHeight: 2000
    )
}

private func aimedPage() -> [ScrollArea] {
    ScrollAreaCatalog.retarget([pageArea()], pointer: pagePointer, focus: pagePointer)
}

private func sampleInput(path: [Int]) -> EditableInputTarget {
    EditableInputTarget(
        role: "AXTextField",
        frame: ElementFrame(x: 1, y: 2, width: 30, height: 16),
        path: path
    )
}

private func axNode(
    role: String? = nil,
    frame: ElementFrame? = ElementFrame(x: 0, y: 0, width: 100, height: 80),
    vertical: ScrollBarReading? = nil,
    horizontal: ScrollBarReading? = nil,
    children: [AccessibilityElement] = [],
    childrenTruncated: Bool = false
) -> AccessibilityElement {
    AccessibilityElement(
        role: role,
        frame: frame,
        children: children,
        childrenTruncated: childrenTruncated,
        verticalScroll: vertical,
        horizontalScroll: horizontal
    )
}

private struct DirectActuation {
    var outcome: ActuatorOutcome
    var effects: [ActuatorEffect]
}

private func direct(
    _ action: Action,
    bundle: String,
    areas: [ScrollArea],
    pointer: ActuatorPoint?
) -> DirectActuation {
    let poster = PostedEffects()
    let outcome = ActionActuator(poster: poster).perform(
        action,
        context: ActuationContext(bundleIdentifier: bundle, pointer: pointer, scrollAreas: areas)
    )
    return DirectActuation(outcome: outcome, effects: poster.effects)
}

private struct SessionFixture {
    var pipeline: FocusPipeline
    var reader: CountingReader
    var poster: PostedEffects
    var pointer: FixedPointer
    var focuser: PathFocuser
    var session: NormalCommandSession
}

private func makeSession(
    bundle: String,
    areas: [ScrollArea]? = nil,
    ready: Bool = true,
    first: EditableInputQuery = .none,
    focus: ActuatorPoint? = pagePointer,
    pointer: ActuatorPoint? = pagePointer,
    window: ActuatorRect? = nil,
    banner: HintMissBanner? = nil,
    bundles: @escaping @Sendable () -> [String] = { [] },
    deferral: (any WorkScheduling)? = nil
) -> SessionFixture {
    let clock = ManualKeyClock()
    let interpreter = EventInterpreter(
        clock: clock,
        cache: CachedFocus(editability: .notEditable, bundleIdentifier: bundle)
    )
    let reader = CountingReader(bundle: bundle)
    let pipeline = FocusPipeline(decider: interpreter, reader: reader, signals: IdleSignals())
    pipeline.cache.replace(CachedFocus(editability: .notEditable, bundleIdentifier: bundle))
    let poster = PostedEffects()
    let point = FixedPointer(point: pointer)
    let focuser = PathFocuser()
    reader.latch = focuser
    let snapshots = LockedCommandSnapshot(
        snapshot: CommandSnapshot(
            scrollAreas: areas ?? [pageArea()],
            scrollCatalogReady: ready,
            firstInput: first,
            focusPoint: focus,
            windowFrame: window
        )
    )
    let session = NormalCommandSession(
        pipeline: pipeline,
        decider: interpreter,
        actuator: ActionActuator(poster: poster, deferral: deferral),
        snapshots: snapshots,
        pointer: point,
        focuser: focuser,
        banner: banner,
        visionBundles: bundles,
        deferral: deferral
    )
    return SessionFixture(
        pipeline: pipeline,
        reader: reader,
        poster: poster,
        pointer: point,
        focuser: focuser,
        session: session
    )
}

private func sampleKey(
    keyCode: UInt16,
    flags: UInt64 = 0,
    unicode: String,
    sourceUserData: Int64 = 0
) -> SystemKeyRecord {
    SystemKeyRecord(
        kind: .keyDown,
        keyCode: keyCode,
        modifierFlags: flags,
        unicode: unicode,
        sourceUserData: sourceUserData
    )
}

private final class PostedEffects: ActuatorPosting, @unchecked Sendable {
    private(set) var effects: [ActuatorEffect] = []

    func post(_ effect: ActuatorEffect) {
        effects.append(effect)
    }
}

private final class FixedPointer: PointerReading, @unchecked Sendable {
    var point: ActuatorPoint?
    private(set) var reads = 0

    init(point: ActuatorPoint?) {
        self.point = point
    }

    func currentPointer() -> ActuatorPoint? {
        reads += 1
        return point
    }
}

private final class PathFocuser: InputFocusing, @unchecked Sendable {
    var accept = true
    private(set) var accepted = false
    private(set) var paths: [[Int]] = []

    func focusInput(path: [Int]) -> Bool {
        paths.append(path)
        guard accept else {
            return false
        }
        accepted = true
        return true
    }
}

private final class CountingReader: AccessibilityReading, @unchecked Sendable {
    var bundle: String
    var editableAfterAccept = true
    var latch: PathFocuser?
    private(set) var focusedReads = 0
    private(set) var windowReads = 0

    init(bundle: String) {
        self.bundle = bundle
    }

    func readFocusedElement() -> AccessibilityRead<AccessibilityElement> {
        focusedReads += 1
        if latch?.accepted == true, editableAfterAccept {
            return .value(AccessibilityElement(role: "AXTextField"))
        }
        return .value(AccessibilityElement(role: "AXWebArea"))
    }

    func readFrontmostBundleIdentifier() -> AccessibilityRead<String> {
        .value(bundle)
    }

    func readFrontmostWindow(maxNodes: Int, maxDepth: Int) -> AccessibilityRead<AccessibilityElement> {
        _ = maxNodes
        _ = maxDepth
        windowReads += 1
        return .unavailable
    }
}

private final class IdleSignals: FocusChangeSignaling, @unchecked Sendable {
    func start(_ handler: @escaping @Sendable () -> Void) {
        _ = handler
    }

    func stop() {}
}

private func onlyArea(
    _ catalog: ScrollCatalog,
    file: StaticString = #filePath,
    line: UInt = #line
) -> ScrollArea? {
    guard catalog.areas.count == 1 else {
        XCTFail(
            "expected 1 scroll area, ready=\(catalog.ready), count=\(catalog.areas.count)",
            file: file,
            line: line
        )
        return nil
    }
    return catalog.areas[0]
}

private func repoRoot(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// With a scheduler, the key hook decides and returns. Nothing that talks to
/// another process runs before it has returned.
extension NormalCommandSessionTests {
    func testDeferredScrollIsSwallowedNowAndPostedLater() {
        let later = ManualWork()
        let fixture = makeSession(bundle: "com.apple.Safari", deferral: later)
        let performance = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(performance.delivery, .swallow)
        XCTAssertEqual(performance.swallowReason, .actuator)
        XCTAssertTrue(fixture.poster.effects.isEmpty, "posting must not happen inside the hook")
        XCTAssertEqual(fixture.reader.focusedReads, 0)
        XCTAssertEqual(fixture.reader.windowReads, 0)
        later.runPending()
        XCTAssertEqual(fixture.poster.effects.count, 1)
    }

    func testDeferredGIEntersInsertNowAndFocusesLater() {
        let later = ManualWork()
        let fixture = makeSession(
            bundle: "com.apple.Notes",
            first: .found(sampleInput(path: [0, 3])),
            deferral: later
        )
        _ = fixture.session.handleKeyDown(KeyEvent("g"))
        let performance = fixture.session.handleKeyDown(KeyEvent("i"))
        XCTAssertEqual(performance.delivery, .swallow)
        XCTAssertEqual(performance.mode, .insert, "the next typed letter must already be text")
        XCTAssertEqual(performance.focusedPath, [0, 3])
        XCTAssertEqual(fixture.focuser.paths, [], "the accessibility write must not run inside the hook")
        XCTAssertEqual(fixture.reader.focusedReads, 0)
        let typed = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(typed.delivery, .passThrough)

        later.runPending()
        XCTAssertEqual(fixture.focuser.paths, [[0, 3]])
        XCTAssertEqual(fixture.reader.focusedReads, 1)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        XCTAssertEqual(fixture.pipeline.wiring.handleKeyDown(KeyEvent("k")).delivery, .passThrough)
    }

    func testDeferredGIClicksTheFieldWhenTheFocusWriteIsRefused() {
        let later = ManualWork()
        let fixture = makeSession(
            bundle: "com.apple.Notes",
            first: .found(sampleInput(path: [2])),
            deferral: later
        )
        fixture.focuser.accept = false
        _ = fixture.session.handleKeyDown(KeyEvent("g"))
        let performance = fixture.session.handleKeyDown(KeyEvent("i"))
        XCTAssertEqual(performance.mode, .insert)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        let lines = ModeTrace.capture {
            later.runPending()
        }
        XCTAssertEqual(fixture.poster.effects, [
            .mouseClick(point: ActuatorPoint(x: 16, y: 10), button: .left, modifiers: []),
        ])
        XCTAssertTrue(lines.contains { $0.contains("gi decision=click") && $0.contains("reason=ax-focus-failed") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("timing stage=gi ms=") }, "\(lines)")
    }

    func testTapAdapterAsksForAFocusReadAfterAClickAndAfterAnUnknownKey() {
        let fixture = makeSession(bundle: "com.apple.Safari")
        let followUp = FollowUpLog()
        let adapter = SessionTapAdapter(
            session: fixture.session,
            observer: SilentObserver(),
            followUp: followUp,
            focus: fixture.pipeline.cache
        )
        _ = adapter.handleSystemRecord(sampleKey(keyCode: 0x26, unicode: "j"))
        XCTAssertEqual(followUp.events, [], "a known focus needs no extra read")

        _ = adapter.handleSystemRecord(SystemKeyRecord(
            kind: .other, keyCode: 0, modifierFlags: 0, unicode: "", pointerX: 10, pointerY: 20
        ))
        XCTAssertEqual(followUp.events, ["click"])

        fixture.pipeline.cache.replace(CachedFocus(editability: .unknown, bundleIdentifier: "com.apple.Safari"))
        _ = fixture.pipeline.wiring.publishCachedFocus()
        let passed = adapter.handleSystemRecord(sampleKey(keyCode: 0x26, unicode: "j"))
        XCTAssertEqual(passed.delivery, .passThrough)
        XCTAssertEqual(followUp.events, ["click", "unknown-key"])

        _ = adapter.handleSystemRecord(sampleKey(
            keyCode: 0x26, unicode: "j", sourceUserData: SynthesizedEventMark.userData
        ))
        XCTAssertEqual(followUp.events, ["click", "unknown-key"], "our own events are not the user")
    }

    func testTapAdapterLogsHowLongASwallowedKeyTook() {
        let fixture = makeSession(bundle: "com.apple.Safari")
        let adapter = SessionTapAdapter(session: fixture.session, observer: SilentObserver())
        let lines = ModeTrace.capture {
            _ = adapter.handleSystemRecord(sampleKey(keyCode: 0x26, unicode: "j"))
        }
        XCTAssertTrue(lines.contains { $0.hasPrefix("timing stage=tap ms=") && $0.contains("delivery=swallow") }, "\(lines)")
    }
}

private final class FollowUpLog: TapFollowUp, @unchecked Sendable {
    private(set) var events: [String] = []

    func pointerClicked() {
        events.append("click")
    }

    func keyWhileFocusUnknown() {
        events.append("unknown-key")
    }
}

private final class SilentObserver: RuntimeObserving, @unchecked Sendable {
    func runtimeDidHandle(_ decision: EventDecision?) {
        _ = decision
    }
}

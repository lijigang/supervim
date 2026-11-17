import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// Focus reads and window enumeration behind a fake accessibility tree.
/// The event hook must keep using the cache. Safari, Notes, and WeChat are not claimed here.
final class AXScannerTests: XCTestCase {
    func testEditabilityFollowsTheAttributeRoleAndKeyboardOwner() {
        var problems: [String] = []
        for sample in editabilitySamples {
            let element = AccessibilityElement(
                role: sample.role,
                subrole: sample.subrole,
                editableAttribute: sample.editable
            )
            let got = FocusClassification.editability(of: element)
            if got != sample.expected {
                problems.append("\(sample.label): \(got) != \(sample.expected)")
            }
        }
        XCTAssertEqual(problems, [])
    }

    func testWalkLimitsClampANonPositiveBudget() {
        XCTAssertEqual(
            TreeWalkLimits(maxNodes: 0, maxDepth: -3),
            TreeWalkLimits(maxNodes: 1, maxDepth: 0)
        )
        XCTAssertEqual(TreeWalkLimits.standard, TreeWalkLimits(maxNodes: 2_000, maxDepth: 32))
    }

    /// WeChat and Grok keep the caret in the composer. Esc must stay Normal
    /// until the focused element actually changes, `i` is pressed, or the
    /// pointer clicks back into that same composer.
    func testEscapedComposerStaysNormalUntilFocusEntersANewInput() {
        let composer = AccessibilityElement(
            role: "AXTextArea",
            editableAttribute: true,
            identity: "composer",
            frame: ElementFrame(x: 0, y: 520, width: 800, height: 80)
        )
        let search = AccessibilityElement(
            role: "AXTextField",
            subrole: "AXSearchField",
            editableAttribute: true,
            identity: "search",
            frame: ElementFrame(x: 200, y: 8, width: 240, height: 28)
        )
        let held = makeFocusFixture()
        held.reader.focused = .value(composer)
        held.reader.bundle = .value("com.tencent.xinWeChat")

        XCTAssertEqual(held.pipeline.scanner.noteFocusChanged().mode, .insert)
        let escape = held.pipeline.wiring.handleKeyDown(KeyEvent(identity: .escape))
        XCTAssertEqual(escape.mode, .normal)
        XCTAssertEqual(escape.delivery, .swallow)
        XCTAssertEqual(held.pipeline.scanner.noteFocusChanged().mode, .normal)
        let up = held.pipeline.wiring.handleKeyDown(KeyEvent("k"))
        XCTAssertEqual(up.mode, .normal)
        XCTAssertEqual(up.delivery, .swallow)
        XCTAssertEqual(up.actions, [CommandMap().action(for: .scrollUp)])
        XCTAssertEqual(
            held.interpreter.updateCache(
                CachedFocus(editability: .unknown, bundleIdentifier: "com.tencent.xinWeChat")
            ).mode,
            .normal
        )

        held.reader.focused = .value(AccessibilityElement(role: "AXWebArea", identity: "history"))
        XCTAssertEqual(held.pipeline.scanner.noteFocusChanged().mode, .normal)
        held.reader.focused = .value(search)
        XCTAssertEqual(held.pipeline.scanner.noteFocusChanged().mode, .insert)

        let typed = makeFocusFixture()
        typed.reader.focused = .value(composer)
        typed.reader.bundle = .value("com.tencent.xinWeChat")
        _ = typed.pipeline.scanner.noteFocusChanged()
        _ = typed.pipeline.wiring.handleKeyDown(KeyEvent(identity: .escape))
        let insert = typed.pipeline.wiring.handleKeyDown(KeyEvent("i"))
        XCTAssertEqual(insert.mode, .insert)
        XCTAssertEqual(insert.delivery, .swallow)
        XCTAssertEqual(typed.pipeline.wiring.handleKeyDown(KeyEvent("k")).delivery, .passThrough)

        let clicked = makeFocusFixture()
        clicked.reader.focused = .value(composer)
        clicked.reader.bundle = .value("com.tencent.xinWeChat")
        _ = clicked.pipeline.scanner.noteFocusChanged()
        _ = clicked.pipeline.wiring.handleKeyDown(KeyEvent(identity: .escape))
        let outside = clicked.interpreter.acceptPointerClick(x: 40, y: 40)
        XCTAssertEqual(outside.mode, .normal)
        let inside = clicked.interpreter.acceptPointerClick(x: 120, y: 540)
        XCTAssertEqual(inside.mode, .insert)
    }

    func testEditableFocusEntersInsertAndPassesTheKeyWithoutWalkingTheWindow() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(inputElement())
        fixture.reader.bundle = .value("com.apple.Safari")

        let decision = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(
            fixture.pipeline.cache.currentFocus(),
            CachedFocus(
                editability: .editable,
                bundleIdentifier: "com.apple.Safari",
                frame: FocusFrame(x: 20, y: 20, width: 120, height: 24),
                role: "AXTextField"
            )
        )
        XCTAssertEqual(decision.delivery, .passThrough)
        XCTAssertEqual(decision.mode, .insert)
        XCTAssertTrue(decision.actions.isEmpty)
        XCTAssertNil(decision.overlay)
        XCTAssertEqual(fixture.interpreter.mode, .insert)
        XCTAssertEqual(fixture.reader.focusedReads, 1)
        XCTAssertEqual(fixture.reader.bundleReads, 1)
        XCTAssertEqual(fixture.reader.windowReads, 0)
        let typed = fixture.pipeline.wiring.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(typed.delivery, .passThrough)
        XCTAssertEqual(typed.mode, .insert)
        XCTAssertTrue(typed.actions.isEmpty)
        XCTAssertEqual(fixture.reader.focusedReads, 1)
        XCTAssertEqual(fixture.reader.windowReads, 0)
    }

    func testNotEditableFocusScrollsAndDoesNotWalkTheWindow() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(AccessibilityElement(role: "AXWebArea"))
        fixture.reader.bundle = .value("com.apple.Safari")

        let decision = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(decision.mode, .normal)
        XCTAssertEqual(fixture.reader.windowReads, 0)
        let scroll = fixture.pipeline.wiring.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(scroll.delivery, .swallow)
        XCTAssertEqual(scroll.mode, .normal)
        XCTAssertEqual(scroll.actions, [CommandMap().action(for: .scrollDown)])
        XCTAssertEqual(fixture.reader.windowReads, 0)
        XCTAssertEqual(fixture.reader.focusedReads, 1)
    }

    func testUnavailableFocusStaysUnknownAndPassesTheCommand() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .unavailable
        fixture.reader.bundle = .value("com.apple.Safari")

        let decision = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(
            fixture.pipeline.cache.currentFocus(),
            CachedFocus(editability: .unknown, bundleIdentifier: "com.apple.Safari")
        )
        XCTAssertEqual(decision.mode, .normal)
        XCTAssertEqual(decision.delivery, .passThrough)
        let hint = fixture.pipeline.wiring.handleKeyDown(KeyEvent("f"))
        XCTAssertEqual(hint.delivery, .passThrough)
        XCTAssertEqual(hint.mode, .normal)
        XCTAssertTrue(hint.actions.isEmpty)
        XCTAssertNil(hint.overlay)
        XCTAssertEqual(fixture.reader.windowReads, 0)
    }

    func testMissingBundleIdentifierDoesNotEnterInsert() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(inputElement())
        fixture.reader.bundle = .unavailable

        _ = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(
            fixture.pipeline.cache.currentFocus(),
            CachedFocus(
                editability: .editable,
                bundleIdentifier: "",
                frame: FocusFrame(x: 20, y: 20, width: 120, height: 24),
                role: "AXTextField"
            )
        )
        XCTAssertEqual(fixture.interpreter.mode, .normal)
        let typed = fixture.pipeline.wiring.handleKeyDown(KeyEvent("a"))
        XCTAssertEqual(typed.delivery, .passThrough)
        XCTAssertEqual(typed.mode, .normal)
        XCTAssertTrue(typed.actions.isEmpty)
    }

    func testWhitespaceBundleIsStoredRawAndDoesNotEnterInsert() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(inputElement())
        fixture.reader.bundle = .value("   ")

        _ = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(fixture.pipeline.cache.currentFocus().bundleIdentifier, "   ")
        XCTAssertEqual(fixture.pipeline.cache.currentFocus().editability, .editable)
        XCTAssertEqual(fixture.interpreter.mode, .normal)
        XCTAssertEqual(fixture.pipeline.wiring.handleKeyDown(KeyEvent("j")).delivery, .passThrough)
    }

    func testBundleIdentifierKeepsSurroundingSpaceForTheSettingsTrim() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(inputElement())
        fixture.reader.bundle = .value(" com.apple.Safari ")

        _ = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(fixture.pipeline.cache.currentFocus().bundleIdentifier, " com.apple.Safari ")
        XCTAssertEqual(fixture.interpreter.mode, .insert)
    }

    func testExcludedAppDoesNotEnterInsertWhenTheFieldIsEditable() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(inputElement())
        fixture.reader.bundle = .value("com.apple.Terminal")

        _ = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(fixture.pipeline.cache.currentFocus().editability, .editable)
        XCTAssertEqual(fixture.interpreter.mode, .normal)
        let typed = fixture.pipeline.wiring.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(typed.delivery, .passThrough)
        XCTAssertTrue(typed.actions.isEmpty)
    }

    func testConflictingTextAttributePassesTheCommand() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(inputElement(editable: false))
        fixture.reader.bundle = .value("com.apple.Safari")

        _ = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(fixture.pipeline.cache.currentFocus().editability, .unknown)
        let hint = fixture.pipeline.wiring.handleKeyDown(KeyEvent("f"))
        XCTAssertEqual(hint.delivery, .passThrough)
        XCTAssertEqual(hint.mode, .normal)
        XCTAssertNil(hint.overlay)
    }

    func testMenuFocusPassesKeys() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(AccessibilityElement(role: "AXMenuItem", actions: ["AXPress"]))
        fixture.reader.bundle = .value("com.apple.Safari")

        _ = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(fixture.pipeline.cache.currentFocus().editability, .unknown)
        let typed = fixture.pipeline.wiring.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(typed.delivery, .passThrough)
        XCTAssertTrue(typed.actions.isEmpty)
        XCTAssertEqual(fixture.interpreter.mode, .normal)
    }

    func testPopUpButtonEntersInsert() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(AccessibilityElement(role: "AXPopUpButton"))
        fixture.reader.bundle = .value("com.apple.Safari")

        _ = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(fixture.interpreter.mode, .insert)
        XCTAssertEqual(fixture.pipeline.wiring.handleKeyDown(KeyEvent("j")).delivery, .passThrough)
    }

    func testFocusedGroupDoesNotSearchItsChildren() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(
            AccessibilityElement(
                role: "AXGroup",
                frame: ElementFrame(x: 0, y: 0, width: 400, height: 300),
                children: [inputElement()]
            )
        )
        fixture.reader.bundle = .value("com.apple.Safari")

        _ = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(fixture.pipeline.cache.currentFocus().editability, .notEditable)
        XCTAssertEqual(fixture.interpreter.mode, .normal)
        XCTAssertEqual(fixture.reader.windowReads, 0)
        XCTAssertEqual(fixture.pipeline.wiring.handleKeyDown(KeyEvent("j")).actions, [CommandMap().action(for: .scrollDown)])
    }

    func testActivationSignalUpdatesFocusWithoutWalkingTheWindow() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .unavailable
        fixture.reader.bundle = .value("com.apple.Safari")
        fixture.pipeline.scanner.start()
        XCTAssertEqual(fixture.reader.focusedReads, 1)
        XCTAssertEqual(fixture.reader.windowReads, 0)
        XCTAssertEqual(fixture.pipeline.cache.currentFocus().editability, .unknown)

        fixture.reader.focused = .value(inputElement())
        fixture.signals.emit()

        XCTAssertEqual(fixture.interpreter.mode, .insert)
        XCTAssertEqual(fixture.reader.focusedReads, 2)
        XCTAssertEqual(fixture.reader.bundleReads, 2)
        XCTAssertEqual(fixture.reader.windowReads, 0)
        XCTAssertEqual(fixture.signals.starts, 1)
    }

    func testRepeatedStartDoesNotStackSignalsOrReread() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(inputElement())
        fixture.reader.bundle = .value("com.apple.Safari")
        fixture.pipeline.scanner.start()
        fixture.pipeline.scanner.start()

        XCTAssertEqual(fixture.signals.starts, 2)
        XCTAssertEqual(fixture.reader.focusedReads, 1)
        fixture.signals.emit()
        XCTAssertEqual(fixture.reader.focusedReads, 2)
        XCTAssertEqual(fixture.reader.windowReads, 0)
    }

    func testStopDropsLaterSignalsUntilStartedAgain() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(AccessibilityElement(role: "AXButton"))
        fixture.reader.bundle = .value("com.apple.Safari")
        fixture.pipeline.scanner.start()
        fixture.pipeline.scanner.stop()
        fixture.reader.focused = .value(inputElement())
        fixture.signals.emit()

        XCTAssertEqual(fixture.signals.stops, 1)
        XCTAssertEqual(fixture.reader.focusedReads, 1)
        XCTAssertEqual(fixture.interpreter.mode, .normal)

        fixture.pipeline.scanner.start()
        XCTAssertEqual(fixture.interpreter.mode, .insert)
        XCTAssertEqual(fixture.reader.focusedReads, 2)
        XCTAssertEqual(fixture.reader.windowReads, 0)
    }

    func testRefreshFocusUsesTheFocusedElementOnly() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(inputElement())
        fixture.reader.bundle = .value("com.apple.Safari")

        let focus = fixture.pipeline.wiring.refreshFocus()

        XCTAssertEqual(
            focus,
            CachedFocus(
                editability: .editable,
                bundleIdentifier: "com.apple.Safari",
                frame: FocusFrame(x: 20, y: 20, width: 120, height: 24),
                role: "AXTextField"
            )
        )
        XCTAssertEqual(fixture.interpreter.mode, .insert)
        XCTAssertEqual(fixture.reader.windowReads, 0)
        XCTAssertEqual(fixture.reader.focusedReads, 1)
    }

    func testEditableSignalEndsHintAndPassesTheKey() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(AccessibilityElement(role: "AXWebArea"))
        fixture.reader.bundle = .value("com.apple.Safari")
        _ = fixture.pipeline.scanner.noteFocusChanged()
        let opened = fixture.pipeline.wiring.handleKeyDown(KeyEvent("f"))
        XCTAssertEqual(opened.mode, .hint(.plain))

        fixture.reader.focused = .value(inputElement())
        let decision = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(
            decision,
            EventDecision(
                delivery: .passThrough,
                mode: .insert,
                overlay: .endHint,
                modeEffects: [.endHint]
            )
        )
        let typed = fixture.pipeline.wiring.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(typed.delivery, .passThrough)
        XCTAssertEqual(typed.mode, .insert)
        XCTAssertEqual(fixture.reader.windowReads, 0)
    }

    func testManualInsertSurvivesANotEditableFocusReport() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(AccessibilityElement(role: "AXButton"))
        fixture.reader.bundle = .value("com.apple.Safari")
        _ = fixture.pipeline.scanner.noteFocusChanged()
        let inserted = fixture.pipeline.wiring.handleKeyDown(KeyEvent("i"))
        XCTAssertEqual(inserted.mode, .insert)

        let decision = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(decision.mode, .insert)
        XCTAssertEqual(fixture.interpreter.mode, .insert)
        let typed = fixture.pipeline.wiring.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(typed.delivery, .passThrough)
        XCTAssertEqual(typed.mode, .insert)
    }

    func testAutomaticInsertReturnsToNormalWhenTheFieldGoesAway() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(inputElement())
        fixture.reader.bundle = .value("com.apple.Safari")
        _ = fixture.pipeline.scanner.noteFocusChanged()
        XCTAssertEqual(fixture.interpreter.mode, .insert)

        fixture.reader.focused = .value(AccessibilityElement(role: "AXWebArea"))
        let decision = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(decision.mode, .normal)
        XCTAssertEqual(decision.delivery, .passThrough)
        XCTAssertTrue(decision.modeEffects.isEmpty)
        let scroll = fixture.pipeline.wiring.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(scroll.delivery, .swallow)
        XCTAssertEqual(scroll.actions, [CommandMap().action(for: .scrollDown)])
    }

    func testSameEditableReportLeavesInsertInPlace() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(inputElement())
        fixture.reader.bundle = .value("com.apple.Safari")
        _ = fixture.pipeline.scanner.noteFocusChanged()

        let decision = fixture.pipeline.scanner.noteFocusChanged()

        XCTAssertEqual(decision.mode, .insert)
        XCTAssertNil(decision.overlay)
        XCTAssertTrue(decision.modeEffects.isEmpty)
        XCTAssertEqual(fixture.reader.windowReads, 0)
    }

    func testClickableElementsFollowTreeOrderAndKeepTheChildPath() {
        let fixture = makeFocusFixture()
        let link = AccessibilityElement(
            role: "AXLink",
            actions: ["AXPress"],
            frame: ElementFrame(x: 10, y: 10, width: 40, height: 16)
        )
        let nested = AccessibilityElement(
            role: "AXButton",
            subrole: "AXCloseButton",
            frame: ElementFrame(x: 30, y: 30, width: 16, height: 16)
        )
        fixture.reader.window = .value(
            windowElement(children: [
                AccessibilityElement(role: "AXStaticText", frame: ElementFrame(x: 10, y: 40, width: 80, height: 12)),
                link,
                AccessibilityElement(role: "AXGroup", children: [nested]),
            ])
        )

        let query = fixture.pipeline.scanner.clickableElements()

        XCTAssertEqual(
            query,
            .elements(
                ClickableSnapshot(
                    elements: [
                        ClickableElement(
                            role: "AXLink",
                            actions: ["AXPress"],
                            frame: ElementFrame(x: 10, y: 10, width: 40, height: 16),
                            path: [1]
                        ),
                        ClickableElement(
                            role: "AXButton",
                            subrole: "AXCloseButton",
                            frame: ElementFrame(x: 30, y: 30, width: 16, height: 16),
                            path: [2, 0]
                        ),
                    ],
                    truncated: false
                )
            )
        )
        XCTAssertEqual(fixture.reader.windowReads, 1)
        XCTAssertEqual(fixture.reader.focusedReads, 0)
        XCTAssertEqual(fixture.interpreter.mode, .normal)
        XCTAssertEqual(fixture.pipeline.cache.currentFocus(), .unknown)
    }

    func testClickableElementsIncludeVimiumControlsAndPressedCustomNodes() {
        let fixture = makeFocusFixture()
        let roles = [
            "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
            "AXComboBox", "AXMenuButton", "AXMenuItem", "AXTextField", "AXTextArea",
            "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXColorWell", "AXTab",
        ]
        var children: [AccessibilityElement] = roles.enumerated().map { index, role in
            AccessibilityElement(
                role: role,
                frame: ElementFrame(x: 10, y: Double(index) * 20, width: 40, height: 16)
            )
        }
        children.append(
            AccessibilityElement(
                role: "AXGroup",
                subrole: "AXSearchField",
                frame: ElementFrame(x: 10, y: 400, width: 80, height: 20)
            )
        )
        children.append(
            AccessibilityElement(
                role: "AXTextField",
                subrole: "AXSecureTextField",
                frame: ElementFrame(x: 10, y: 430, width: 80, height: 20)
            )
        )
        children.append(
            AccessibilityElement(
                role: "AXCustomThing",
                actions: ["AXPress"],
                frame: ElementFrame(x: 10, y: 460, width: 20, height: 20)
            )
        )
        children.append(
            AccessibilityElement(
                role: "AXImage",
                actions: ["AXConfirm"],
                frame: ElementFrame(x: 10, y: 490, width: 20, height: 20)
            )
        )
        children.append(
            AccessibilityElement(
                role: "AXStaticText",
                actions: ["AXPick"],
                frame: ElementFrame(x: 10, y: 520, width: 40, height: 12)
            )
        )
        children.append(
            AccessibilityElement(
                role: "AXCustomThing",
                actions: ["AXRaise"],
                frame: ElementFrame(x: 10, y: 550, width: 20, height: 20)
            )
        )
        children.append(
            AccessibilityElement(
                role: "AXImage",
                frame: ElementFrame(x: 10, y: 580, width: 20, height: 20)
            )
        )
        fixture.reader.window = .value(windowElement(children: children))

        guard case .elements(let snapshot) = fixture.pipeline.scanner.clickableElements() else {
            return XCTFail("expected elements")
        }

        XCTAssertFalse(snapshot.truncated)
        XCTAssertEqual(
            snapshot.elements.map(\.role),
            roles + ["AXGroup", "AXTextField", "AXCustomThing", "AXImage", "AXStaticText"]
        )
        XCTAssertEqual(snapshot.elements.map(\.path), (0..<(roles.count + 5)).map { [$0] })
        XCTAssertEqual(snapshot.elements[roles.count].subrole, "AXSearchField")
        XCTAssertEqual(snapshot.elements[roles.count + 1].subrole, "AXSecureTextField")
        XCTAssertEqual(snapshot.elements[roles.count + 2].actions, ["AXPress"])
        XCTAssertEqual(snapshot.elements[roles.count + 3].actions, ["AXConfirm"])
        XCTAssertEqual(snapshot.elements[roles.count + 4].actions, ["AXPick"])
    }

    func testGroupWithPressActionIsClickable() {
        let fixture = makeFocusFixture()
        fixture.reader.window = .value(
            windowElement(children: [
                AccessibilityElement(
                    role: "AXGroup",
                    actions: ["AXPress"],
                    frame: ElementFrame(x: 12, y: 40, width: 180, height: 28)
                ),
                AccessibilityElement(
                    role: "AXGroup",
                    frame: ElementFrame(x: 12, y: 80, width: 180, height: 28)
                ),
            ])
        )
        guard case .elements(let snapshot) = fixture.pipeline.scanner.clickableElements() else {
            return XCTFail("expected elements")
        }
        XCTAssertEqual(snapshot.elements.map(\.role), ["AXGroup"])
        XCTAssertEqual(snapshot.elements.map(\.actions), [["AXPress"]])
        XCTAssertEqual(snapshot.elements.map(\.path), [[0]])
    }

    func testCollapsedWindowIsRereadAfterAccessibilityIsEnabled() {
        let reader = ExpandingAccessibilityReader()
        let signals = ScriptedFocusSignals()
        let interpreter = EventInterpreter(clock: ManualKeyClock())
        let pipeline = FocusPipeline(decider: interpreter, reader: reader, signals: signals)
        reader.bundle = "com.tencent.xinWeChat"

        guard case .elements(let snapshot) = pipeline.scanner.clickableElements() else {
            return XCTFail("expected elements")
        }
        XCTAssertEqual(reader.expansions, [.manual])
        XCTAssertEqual(snapshot.elements.map(\.role), ["AXButton"])
        XCTAssertEqual(reader.windowReads, 2)
    }

    func testPressActionMakesContainerRolesClickable() {
        let fixture = makeFocusFixture()
        let roles = [
            "AXWindow", "AXApplication", "AXScrollArea", "AXWebArea", "AXGroup",
            "AXList", "AXOutline", "AXTable", "AXToolbar", "AXTabGroup",
            "AXSplitGroup", "AXScrollBar", "AXSheet", "AXDialog", "AXSystemDialog",
            "AXMenu", "AXMenuBar", "AXRow", "AXLayoutArea", "AXBrowser",
        ]
        let children = roles.map { role in
            AccessibilityElement(
                role: role,
                actions: ["AXPress"],
                frame: ElementFrame(x: 4, y: 4, width: 40, height: 20)
            )
        }
        fixture.reader.window = .value(
            windowElement(children: children, actions: ["AXPress"])
        )

        guard case .elements(let snapshot) = fixture.pipeline.scanner.clickableElements() else {
            return XCTFail("expected elements")
        }
        XCTAssertEqual(snapshot.elements.compactMap(\.role), roles)
    }

    func testFramesOutsideTheWindowOrWithoutAreaAreDropped() {
        let fixture = makeFocusFixture()
        let inside = ElementFrame(x: 90, y: 90, width: 20, height: 20)
        fixture.reader.window = .value(
            windowElement(
                frame: ElementFrame(x: 100, y: 100, width: 100, height: 100),
                children: [
                    AccessibilityElement(role: "AXButton", frame: inside),
                    AccessibilityElement(role: "AXButton", frame: ElementFrame(x: 200, y: 200, width: 10, height: 10)),
                    AccessibilityElement(role: "AXButton", frame: ElementFrame(x: 100, y: 0, width: 10, height: 10)),
                    AccessibilityElement(role: "AXLink", frame: ElementFrame(x: 80, y: 80, width: 30, height: 30)),
                    AccessibilityElement(role: "AXButton", frame: ElementFrame(x: 110, y: 110, width: 0, height: 10)),
                    AccessibilityElement(role: "AXButton", frame: ElementFrame(x: 110, y: 110, width: -4, height: 10)),
                    AccessibilityElement(role: "AXButton"),
                ]
            )
        )

        guard case .elements(let snapshot) = fixture.pipeline.scanner.clickableElements() else {
            return XCTFail("expected elements")
        }

        XCTAssertEqual(snapshot.elements.map(\.path), [[0], [3]])
        XCTAssertEqual(snapshot.elements.map(\.frame), [
            inside,
            ElementFrame(x: 80, y: 80, width: 30, height: 30),
        ])
        XCTAssertFalse(snapshot.truncated)
    }

    func testMissingWindowFrameKeepsNonEmptyElementFrames() {
        let fixture = makeFocusFixture()
        fixture.reader.window = .value(
            windowElement(
                frame: nil,
                children: [
                    AccessibilityElement(role: "AXLink", frame: ElementFrame(x: 5_000, y: 5_000, width: 8, height: 8)),
                    AccessibilityElement(role: "AXLink", frame: ElementFrame(x: 0, y: 0, width: 0, height: 8)),
                ]
            )
        )

        guard case .elements(let snapshot) = fixture.pipeline.scanner.clickableElements() else {
            return XCTFail("expected elements")
        }
        XCTAssertEqual(snapshot.elements.map(\.path), [[0]])
    }

    func testEnumerationDoesNotReplaceTheFocusCache() {
        let fixture = makeFocusFixture()
        fixture.reader.focused = .value(AccessibilityElement(role: "AXButton"))
        fixture.reader.bundle = .value("com.apple.Safari")
        _ = fixture.pipeline.scanner.noteFocusChanged()
        fixture.reader.window = .value(windowElement(children: [inputElement()]))

        _ = fixture.pipeline.scanner.clickableElements()
        _ = fixture.pipeline.scanner.firstEditableInput()

        XCTAssertEqual(
            fixture.pipeline.cache.currentFocus(),
            CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.Safari", role: "AXButton")
        )
        XCTAssertEqual(fixture.interpreter.mode, .normal)
        XCTAssertEqual(fixture.reader.focusedReads, 1)
        XCTAssertEqual(fixture.reader.windowReads, 2)
        XCTAssertEqual(fixture.pipeline.wiring.handleKeyDown(KeyEvent("j")).delivery, .swallow)
    }

    func testEnumerationPassesTheWalkBudgetAndSkipsFocusWhenTheWindowIsMissing() {
        let limits = TreeWalkLimits(maxNodes: 7, maxDepth: 3)
        let fixture = makeFocusFixture(limits: limits)
        fixture.reader.window = .unavailable

        XCTAssertEqual(fixture.pipeline.scanner.clickableElements(), .unavailable)
        XCTAssertEqual(fixture.pipeline.scanner.firstEditableInput(), .unavailable)
        XCTAssertEqual(fixture.reader.lastWindowMaxNodes, 7)
        XCTAssertEqual(fixture.reader.lastWindowMaxDepth, 3)
        XCTAssertEqual(fixture.reader.windowReads, 2)
        XCTAssertEqual(fixture.reader.focusedReads, 0)
        XCTAssertEqual(fixture.pipeline.cache.currentFocus(), .unknown)
        XCTAssertEqual(fixture.interpreter.mode, .normal)
    }

    func testFirstEditableInputIsTheFirstVisibleFieldInTreeOrder() {
        let fixture = makeFocusFixture()
        let hidden = inputElement(frame: ElementFrame(x: 2_000, y: 2_000, width: 30, height: 16))
        let rejected = inputElement(editable: false)
        let nested = inputElement(frame: ElementFrame(x: 12, y: 12, width: 40, height: 18))
        let later = inputElement(role: "AXTextArea", frame: ElementFrame(x: 12, y: 80, width: 40, height: 40))
        fixture.reader.window = .value(
            windowElement(children: [
                AccessibilityElement(role: "AXButton", frame: ElementFrame(x: 12, y: 40, width: 20, height: 20)),
                hidden,
                rejected,
                AccessibilityElement(role: "AXGroup", children: [nested]),
                later,
            ])
        )

        XCTAssertEqual(
            fixture.pipeline.scanner.firstEditableInput(),
            .found(
                EditableInputTarget(
                    role: "AXTextField",
                    frame: ElementFrame(x: 12, y: 12, width: 40, height: 18),
                    path: [3, 0]
                )
            )
        )
    }

    func testFirstEditableInputAcceptsContentEditableAndSearchSubrole() {
        let fixture = makeFocusFixture()
        fixture.reader.window = .value(
            windowElement(children: [
                AccessibilityElement(
                    role: "AXGroup",
                    editableAttribute: true,
                    frame: ElementFrame(x: 8, y: 8, width: 100, height: 40)
                ),
                AccessibilityElement(
                    subrole: "AXSearchField",
                    frame: ElementFrame(x: 8, y: 60, width: 100, height: 24)
                ),
            ])
        )

        XCTAssertEqual(
            fixture.pipeline.scanner.firstEditableInput(),
            .found(
                EditableInputTarget(
                    role: "AXGroup",
                    frame: ElementFrame(x: 8, y: 8, width: 100, height: 40),
                    path: [0]
                )
            )
        )
    }

    func testFirstEditableInputIsNoneWhenNothingVisibleCanBeEdited() {
        let fixture = makeFocusFixture()
        fixture.reader.window = .value(
            windowElement(children: [
                AccessibilityElement(role: "AXButton", frame: ElementFrame(x: 8, y: 8, width: 20, height: 20)),
                inputElement(frame: ElementFrame(x: 9_000, y: 9_000, width: 20, height: 12)),
                inputElement(frame: nil),
            ])
        )

        XCTAssertEqual(fixture.pipeline.scanner.firstEditableInput(), .none)
        XCTAssertEqual(fixture.interpreter.mode, .normal)
        XCTAssertEqual(fixture.reader.focusedReads, 0)
    }

    func testFirstEditableInputIsUnavailableWhenTheCapHidesEveryField() {
        let fixture = makeFocusFixture(limits: TreeWalkLimits(maxNodes: 2, maxDepth: 8))
        fixture.reader.window = .value(
            windowElement(children: [
                AccessibilityElement(role: "AXButton", frame: ElementFrame(x: 4, y: 4, width: 12, height: 12)),
                inputElement(),
            ])
        )

        XCTAssertEqual(fixture.pipeline.scanner.firstEditableInput(), .unavailable)
    }

    func testFirstEditableInputKeepsAFieldFoundBeforeTheCap() {
        let fixture = makeFocusFixture(limits: TreeWalkLimits(maxNodes: 2, maxDepth: 8))
        fixture.reader.window = .value(
            windowElement(children: [
                inputElement(frame: ElementFrame(x: 6, y: 6, width: 30, height: 14)),
                AccessibilityElement(role: "AXButton", frame: ElementFrame(x: 6, y: 40, width: 12, height: 12)),
            ])
        )

        XCTAssertEqual(
            fixture.pipeline.scanner.firstEditableInput(),
            .found(
                EditableInputTarget(
                    role: "AXTextField",
                    frame: ElementFrame(x: 6, y: 6, width: 30, height: 14),
                    path: [0]
                )
            )
        )
    }

    func testEarlierTruncatedContainerBlocksALaterField() {
        let fixture = makeFocusFixture()
        fixture.reader.window = .value(
            windowElement(children: [
                AccessibilityElement(role: "AXGroup", childrenTruncated: true),
                inputElement(),
            ])
        )

        XCTAssertEqual(fixture.pipeline.scanner.firstEditableInput(), .unavailable)
    }

    func testTruncationAfterTheFirstFieldStillReturnsThatField() {
        let fixture = makeFocusFixture()
        fixture.reader.window = .value(
            windowElement(children: [
                inputElement(frame: ElementFrame(x: 6, y: 6, width: 24, height: 12)),
                AccessibilityElement(role: "AXGroup", childrenTruncated: true),
            ])
        )

        guard case .found(let target) = fixture.pipeline.scanner.firstEditableInput() else {
            return XCTFail("expected the first field")
        }
        XCTAssertEqual(target.path, [0])
    }

    func testClickableWalkReportsANodeCap() {
        let fixture = makeFocusFixture(limits: TreeWalkLimits(maxNodes: 2, maxDepth: 8))
        fixture.reader.window = .value(
            windowElement(children: [
                AccessibilityElement(role: "AXLink", frame: ElementFrame(x: 2, y: 2, width: 10, height: 10)),
                AccessibilityElement(role: "AXButton", frame: ElementFrame(x: 2, y: 20, width: 10, height: 10)),
            ])
        )

        XCTAssertEqual(
            fixture.pipeline.scanner.clickableElements(),
            .elements(
                ClickableSnapshot(
                    elements: [
                        ClickableElement(
                            role: "AXLink",
                            frame: ElementFrame(x: 2, y: 2, width: 10, height: 10),
                            path: [0]
                        ),
                    ],
                    truncated: true
                )
            )
        )
    }

    func testClickableWalkReportsADepthCap() {
        let fixture = makeFocusFixture(limits: TreeWalkLimits(maxNodes: 20, maxDepth: 1))
        fixture.reader.window = .value(
            windowElement(children: [
                AccessibilityElement(
                    role: "AXGroup",
                    children: [
                        AccessibilityElement(role: "AXLink", frame: ElementFrame(x: 2, y: 2, width: 8, height: 8)),
                    ]
                ),
            ])
        )

        XCTAssertEqual(
            fixture.pipeline.scanner.clickableElements(),
            .elements(ClickableSnapshot(elements: [], truncated: true))
        )
    }

    func testClickableWalkStopsAtTheExactBudgetWhenNothingRemains() {
        let fixture = makeFocusFixture(limits: TreeWalkLimits(maxNodes: 2, maxDepth: 4))
        fixture.reader.window = .value(
            windowElement(children: [
                AccessibilityElement(role: "AXLink", frame: ElementFrame(x: 1, y: 1, width: 6, height: 6)),
            ])
        )

        guard case .elements(let snapshot) = fixture.pipeline.scanner.clickableElements() else {
            return XCTFail("expected elements")
        }
        XCTAssertEqual(snapshot.elements.count, 1)
        XCTAssertFalse(snapshot.truncated)
    }

    func testChildrenTruncatedFlagIsVisibleOnTheClickableSnapshot() {
        let fixture = makeFocusFixture()
        fixture.reader.window = .value(
            windowElement(
                children: [
                    AccessibilityElement(role: "AXLink", frame: ElementFrame(x: 1, y: 1, width: 8, height: 8)),
                ],
                childrenTruncated: true
            )
        )

        guard case .elements(let snapshot) = fixture.pipeline.scanner.clickableElements() else {
            return XCTFail("expected elements")
        }
        XCTAssertEqual(snapshot.elements.count, 1)
        XCTAssertTrue(snapshot.truncated)
    }

    func testUnconnectedScannerStoresTheCacheWithoutFeedingAMode() {
        let cache = LockedFocusCache()
        let reader = ScriptedAccessibilityReader()
        reader.focused = .value(inputElement())
        reader.bundle = .value("com.apple.Safari")
        let scanner = AXScanner(reader: reader, signals: ScriptedFocusSignals(), cache: cache)

        let decision = scanner.noteFocusChanged()

        XCTAssertEqual(
            cache.currentFocus(),
            CachedFocus(
                editability: .editable,
                bundleIdentifier: "com.apple.Safari",
                frame: FocusFrame(x: 20, y: 20, width: 120, height: 24),
                role: "AXTextField"
            )
        )
        XCTAssertEqual(decision, EventDecision(delivery: .passThrough, mode: .normal))
        XCTAssertEqual(reader.windowReads, 0)
        XCTAssertEqual(reader.focusedReads, 1)
    }

    func testElementCopiesDoNotShareLaterEdits() {
        let child = inputElement()
        let original = windowElement(children: [child])
        var copy = original
        copy.children = []
        XCTAssertEqual(original.children.count, 1)
        XCTAssertEqual(copy.children.count, 0)
    }

    func testPortableScannerSourceDoesNotTouchTheSystem() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimSystem/AXScanner.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        for token in [
            "import AppKit",
            "import ApplicationServices",
            "import CoreGraphics",
            "import Accessibility",
            "AXUIElement",
            "AXObserver",
            "CGEvent",
            "URLSession",
            "os_log",
            "Logger(",
            "NSLog",
            "print(",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
        for token in ["readFocusedElement", "readFrontmostWindow", "noteFocusChanged", "clickableElements", "firstEditableInput"] {
            XCTAssertTrue(text.contains(token), token)
        }
    }

    func testMacOSAdapterObservesFocusAndDoesNotScanFromTheFocusedRead() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimSystem/AXApplicationReader.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("#if canImport(ApplicationServices)"))
        XCTAssertTrue(text.contains("AXIsProcessTrusted"))
        XCTAssertTrue(text.contains("unverified"))
        XCTAssertTrue(text.contains("AXFocusedUIElementChanged"))
        XCTAssertTrue(text.contains("didActivateApplicationNotification"))
        XCTAssertTrue(text.contains("kAXChildrenAttribute") || text.contains("\"AXChildren\""))
        for token in [
            "AXIsProcessTrustedWithOptions",
            "kAXTrustedCheckOptionPrompt",
            "URLSession",
            "print(",
            "os_log",
            "NSLog",
            "CGEvent",
            "handleKeyDown",
            "handleSystemRecord",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
        guard let start = text.range(of: "func readFocusedElement"),
              let end = text.range(of: "func readFrontmostBundleIdentifier") else {
            return XCTFail("focused read must stay a separate function ahead of the bundle read")
        }
        let body = text[start.lowerBound..<end.lowerBound]
        XCTAssertFalse(body.contains("AXChildren"))
        XCTAssertFalse(body.contains("readFrontmostWindow"))
    }

    func testCoreAndHookSourcesDoNotWalkAccessibility() throws {
        let core = repoRoot().appendingPathComponent("Sources/SupervimCore")
        let files = try FileManager.default.contentsOfDirectory(at: core, includingPropertiesForKeys: nil)
        for url in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for token in ["import AppKit", "import ApplicationServices", "AXUIElement", "CGEvent"] {
                XCTAssertFalse(text.contains(token), "\(url.lastPathComponent) \(token)")
            }
        }
        let hook = try String(
            contentsOf: repoRoot().appendingPathComponent("Sources/SupervimSystem/EventTap.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(hook.contains("readFrontmostWindow"))
        XCTAssertFalse(hook.contains("AXUIElement"))
        XCTAssertEqual(hook.components(separatedBy: "scanFocus(").count - 1, 2)
        let app = try appTargetSource()
        for token in ["AXUIElement", "AXScanner", "AXObserver", "scanFocus(", "EventTap"] {
            XCTAssertFalse(app.contains(token), token)
        }
    }
}

private struct EditabilitySample {
    var label: String
    var role: String?
    var subrole: String?
    var editable: Bool?
    var expected: FocusEditability
}

private let editabilitySamples: [EditabilitySample] = [
    EditabilitySample(label: "text field", role: "AXTextField", subrole: nil, editable: nil, expected: .editable),
    EditabilitySample(label: "text area", role: "AXTextArea", subrole: nil, editable: nil, expected: .editable),
    EditabilitySample(label: "combo box", role: "AXComboBox", subrole: nil, editable: nil, expected: .editable),
    EditabilitySample(label: "pop up", role: "AXPopUpButton", subrole: nil, editable: nil, expected: .editable),
    EditabilitySample(label: "search subrole", role: nil, subrole: "AXSearchField", editable: nil, expected: .editable),
    EditabilitySample(label: "secure subrole", role: "AXTextField", subrole: "AXSecureTextField", editable: nil, expected: .editable),
    EditabilitySample(label: "editable group", role: "AXGroup", subrole: nil, editable: true, expected: .editable),
    EditabilitySample(label: "editable unknown role", role: "AXCustomThing", subrole: nil, editable: true, expected: .editable),
    EditabilitySample(label: "editable button", role: "AXButton", subrole: nil, editable: true, expected: .editable),
    EditabilitySample(label: "text field marked not editable", role: "AXTextField", subrole: nil, editable: false, expected: .unknown),
    EditabilitySample(label: "pop up marked not editable", role: "AXPopUpButton", subrole: nil, editable: false, expected: .unknown),
    EditabilitySample(label: "search marked not editable", role: nil, subrole: "AXSearchField", editable: false, expected: .unknown),
    EditabilitySample(label: "button", role: "AXButton", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "link", role: "AXLink", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "checkbox", role: "AXCheckBox", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "radio", role: "AXRadioButton", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "static text", role: "AXStaticText", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "image", role: "AXImage", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "window", role: "AXWindow", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "group", role: "AXGroup", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "web area", role: "AXWebArea", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "scroll area", role: "AXScrollArea", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "list", role: "AXList", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "application", role: "AXApplication", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "toolbar", role: "AXToolbar", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "slider", role: "AXSlider", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "menu button", role: "AXMenuButton", subrole: nil, editable: nil, expected: .notEditable),
    EditabilitySample(label: "button marked not editable", role: "AXButton", subrole: nil, editable: false, expected: .notEditable),
    EditabilitySample(label: "web area marked not editable", role: "AXWebArea", subrole: nil, editable: false, expected: .notEditable),
    EditabilitySample(label: "unknown role", role: "AXCustomThing", subrole: nil, editable: nil, expected: .unknown),
    EditabilitySample(label: "unknown role marked not editable", role: "AXCustomThing", subrole: nil, editable: false, expected: .notEditable),
    EditabilitySample(label: "empty element", role: nil, subrole: nil, editable: nil, expected: .unknown),
    EditabilitySample(label: "lowercased role", role: "axtextfield", subrole: nil, editable: nil, expected: .unknown),
    EditabilitySample(label: "menu", role: "AXMenu", subrole: nil, editable: nil, expected: .unknown),
    EditabilitySample(label: "menu item", role: "AXMenuItem", subrole: nil, editable: nil, expected: .unknown),
    EditabilitySample(label: "menu bar", role: "AXMenuBar", subrole: nil, editable: nil, expected: .unknown),
    EditabilitySample(label: "menu bar item", role: "AXMenuBarItem", subrole: nil, editable: nil, expected: .unknown),
    EditabilitySample(label: "editable menu item", role: "AXMenuItem", subrole: nil, editable: true, expected: .unknown),
    EditabilitySample(label: "menu item marked not editable", role: "AXMenuItem", subrole: nil, editable: false, expected: .unknown),
    EditabilitySample(label: "sheet", role: "AXSheet", subrole: nil, editable: nil, expected: .unknown),
    EditabilitySample(label: "dialog", role: "AXDialog", subrole: nil, editable: nil, expected: .unknown),
    EditabilitySample(label: "system dialog", role: "AXSystemDialog", subrole: nil, editable: nil, expected: .unknown),
    EditabilitySample(label: "search subrole on a button", role: "AXButton", subrole: "AXSearchField", editable: nil, expected: .editable),
]

private struct FocusFixture {
    var interpreter: EventInterpreter<ManualKeyClock>
    var reader: ScriptedAccessibilityReader
    var signals: ScriptedFocusSignals
    var pipeline: FocusPipeline
}

private func makeFocusFixture(limits: TreeWalkLimits = .standard) -> FocusFixture {
    let reader = ScriptedAccessibilityReader()
    let signals = ScriptedFocusSignals()
    let interpreter = EventInterpreter(clock: ManualKeyClock())
    let pipeline = FocusPipeline(
        decider: interpreter,
        reader: reader,
        signals: signals,
        limits: limits
    )
    return FocusFixture(
        interpreter: interpreter,
        reader: reader,
        signals: signals,
        pipeline: pipeline
    )
}

private func inputElement(
    role: String = "AXTextField",
    subrole: String? = nil,
    editable: Bool? = nil,
    frame: ElementFrame? = ElementFrame(x: 20, y: 20, width: 120, height: 24),
    actions: [String] = [],
    children: [AccessibilityElement] = []
) -> AccessibilityElement {
    AccessibilityElement(
        role: role,
        subrole: subrole,
        actions: actions,
        editableAttribute: editable,
        frame: frame,
        children: children
    )
}

private func windowElement(
    frame: ElementFrame? = ElementFrame(x: 0, y: 0, width: 800, height: 600),
    children: [AccessibilityElement] = [],
    childrenTruncated: Bool = false,
    actions: [String] = []
) -> AccessibilityElement {
    AccessibilityElement(
        role: "AXWindow",
        actions: actions,
        frame: frame,
        children: children,
        childrenTruncated: childrenTruncated
    )
}

private final class ExpandingAccessibilityReader: AccessibilityReading, @unchecked Sendable {
    var bundle = ""
    private(set) var expansions: [AccessibilityTreeExpansion] = []
    private(set) var windowReads = 0
    private var opened = false

    func readFocusedElement() -> AccessibilityRead<AccessibilityElement> {
        .unavailable
    }

    func readFrontmostBundleIdentifier() -> AccessibilityRead<String> {
        .value(bundle)
    }

    func readFrontmostWindow(maxNodes: Int, maxDepth: Int) -> AccessibilityRead<AccessibilityElement> {
        _ = maxNodes
        _ = maxDepth
        windowReads += 1
        if !opened {
            return .value(AccessibilityElement(role: "AXWindow", frame: ElementFrame(x: 0, y: 0, width: 800, height: 600)))
        }
        return .value(
            AccessibilityElement(
                role: "AXWindow",
                frame: ElementFrame(x: 0, y: 0, width: 800, height: 600),
                children: [
                    AccessibilityElement(
                        role: "AXButton",
                        frame: ElementFrame(x: 20, y: 40, width: 120, height: 28)
                    ),
                ]
            )
        )
    }

    func expandAccessibilityTree(allowEnhanced: Bool) -> AccessibilityTreeExpansion {
        XCTAssertTrue(allowEnhanced)
        opened = true
        expansions.append(.manual)
        return .manual
    }
}

private final class ScriptedAccessibilityReader: AccessibilityReading, @unchecked Sendable {
    var focused: AccessibilityRead<AccessibilityElement> = .unavailable
    var bundle: AccessibilityRead<String> = .unavailable
    var window: AccessibilityRead<AccessibilityElement> = .unavailable
    private(set) var focusedReads = 0
    private(set) var bundleReads = 0
    private(set) var windowReads = 0
    private(set) var lastWindowMaxNodes: Int?
    private(set) var lastWindowMaxDepth: Int?

    func readFocusedElement() -> AccessibilityRead<AccessibilityElement> {
        focusedReads += 1
        return focused
    }

    func readFrontmostBundleIdentifier() -> AccessibilityRead<String> {
        bundleReads += 1
        return bundle
    }

    func readFrontmostWindow(maxNodes: Int, maxDepth: Int) -> AccessibilityRead<AccessibilityElement> {
        windowReads += 1
        lastWindowMaxNodes = maxNodes
        lastWindowMaxDepth = maxDepth
        return window
    }
}

private final class ScriptedFocusSignals: FocusChangeSignaling, @unchecked Sendable {
    private var handler: (@Sendable () -> Void)?
    private(set) var starts = 0
    private(set) var stops = 0

    func start(_ handler: @escaping @Sendable () -> Void) {
        starts += 1
        self.handler = handler
    }

    func stop() {
        stops += 1
        handler = nil
    }

    func emit() {
        handler?()
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

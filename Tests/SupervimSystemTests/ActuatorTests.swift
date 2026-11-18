import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// Task 9. A recording poster checks action kind and parameters.
/// These tests do not move the pointer, post a CGEvent, or press a real control.
final class ActuatorTests: XCTestCase {
    func testBrowserAllowlistIsTheSingleDecisionList() {
        XCTAssertEqual(PromisedApplications.browserBundleIdentifiers, promisedBrowsers)
    }

    func testBrowserBundleIdentifiersAppearInOneSourceFile() throws {
        let needle = "com.brave.Browser"
        let hits = try sourceFiles(under: repoRoot().appendingPathComponent("Sources")).reduce(0) { count, url in
            let text = try String(contentsOf: url, encoding: .utf8)
            return count + text.components(separatedBy: needle).count - 1
        }
        XCTAssertEqual(hits, 1)
    }

    func testSynthesizedMarkIsTheSingleNonZeroLiteral() throws {
        XCTAssertEqual(SynthesizedEventMark.userData, 0x5356_4D31)
        XCTAssertNotEqual(SynthesizedEventMark.userData, 0)
        let needle = "0x5356_4D31"
        let hits = try sourceFiles(under: repoRoot().appendingPathComponent("Sources")).reduce(0) { count, url in
            let text = try String(contentsOf: url, encoding: .utf8)
            return count + text.components(separatedBy: needle).count - 1
        }
        XCTAssertEqual(hits, 1)
    }

    func testPlainClickWithAccessibilityPressDoesNotSynthesizeAMouseEvent() {
        let poster = RecordingActuator()
        let outcome = clickOutcome(
            ClickRequest(
                point: actuatorPoint(4, 8),
                kind: .plain,
                elementID: "go",
                canAccessibilityPress: true
            ),
            poster: poster
        )
        XCTAssertEqual(outcome, .performed([.accessibilityPress(elementID: "go", fallback: actuatorPoint(4, 8))]))
        XCTAssertEqual(poster.effects, [.accessibilityPress(elementID: "go", fallback: actuatorPoint(4, 8))])
    }

    func testPlainClickWithoutPressUsesTheLeftButton() {
        let poster = RecordingActuator()
        let point = actuatorPoint(12, 34)
        let outcome = clickOutcome(ClickRequest(point: point, kind: .plain), poster: poster)
        XCTAssertEqual(outcome, .performed([
            .mouseClick(point: point, button: .left, modifiers: []),
        ]))
        XCTAssertEqual(poster.effects, [
            .mouseClick(point: point, button: .left, modifiers: []),
        ])
    }

    func testEmptyAccessibilityTargetFallsBackToALeftClick() {
        let poster = RecordingActuator()
        let point = actuatorPoint(1, 2)
        let missing = clickOutcome(
            ClickRequest(point: point, kind: .plain, elementID: nil, canAccessibilityPress: true),
            poster: poster
        )
        let blank = clickOutcome(
            ClickRequest(point: point, kind: .plain, elementID: "  ", canAccessibilityPress: true),
            poster: poster
        )
        let click = ActuatorEffect.mouseClick(point: point, button: .left, modifiers: [])
        XCTAssertEqual(missing, .performed([click]))
        XCTAssertEqual(blank, .performed([click]))
        XCTAssertEqual(poster.effects, [click, click])
    }

    func testCommandClickIsALeftClickWithCommandAndNotAContextMenu() {
        let poster = RecordingActuator()
        let point = actuatorPoint(9, 9)
        let outcome = clickOutcome(
            ClickRequest(
                point: point,
                kind: .command,
                elementID: "link",
                canAccessibilityPress: true
            ),
            poster: poster
        )
        let click = ActuatorEffect.mouseClick(point: point, button: .left, modifiers: .command)
        XCTAssertEqual(outcome, .performed([click]))
        XCTAssertEqual(poster.effects, [click])
    }

    func testNonFiniteClickIsPassedThrough() {
        let poster = RecordingActuator()
        let outcome = clickOutcome(
            ClickRequest(point: actuatorPoint(Double.nan, 1), kind: .command),
            poster: poster
        )
        XCTAssertEqual(outcome, .passedThrough)
        XCTAssertEqual(poster.effects, [])
        let infinite = clickOutcome(
            ClickRequest(point: actuatorPoint(1, Double.infinity), kind: .plain),
            poster: poster
        )
        XCTAssertEqual(infinite, .passedThrough)
        XCTAssertEqual(poster.effects, [])
    }

    func testBeginHintDoesNotClick() {
        let poster = RecordingActuator()
        let context = pageContext(bundle: "com.apple.Safari")
        for action in [Action.beginHint(.plain), Action.beginHint(.command)] {
            let outcome = outcomeOf(action, context: context, poster: poster)
            XCTAssertEqual(outcome, .notActuatorWork)
        }
        XCTAssertEqual(poster.effects, [])
    }

    func testModeActionsAreNotActuatorWork() {
        let poster = RecordingActuator()
        let context = pageContext(bundle: "com.apple.Safari")
        let actions: [Action] = [
            .showHelp,
            .focusFirstInput,
            .passNextKey,
            .escape,
            .enterInsert,
        ]
        for action in actions {
            XCTAssertEqual(outcomeOf(action, context: context, poster: poster), .notActuatorWork)
        }
        XCTAssertEqual(poster.effects, [])
    }

    func testPointerStepScrollUsesSignedWheelPixels() {
        let poster = RecordingActuator()
        let pointer = actuatorPoint(20, 30)
        let context = pageContext(bundle: "com.apple.TextEdit", pointer: pointer)
        let cases: [(ScrollDirection, Int, Int)] = [
            (.down, 0, -60),
            (.up, 0, 60),
            (.left, -60, 0),
            (.right, 60, 0),
        ]
        for (direction, horizontal, vertical) in cases {
            let local = RecordingActuator()
            let amount = ScrollAmount.points(CommandMap.scrollStepPoints)
            let outcome = outcomeOf(
                .scroll(direction: direction, amount: amount),
                context: context,
                poster: local
            )
            let effect = ActuatorEffect.pointerScroll(
                targetID: "page",
                direction: direction,
                amount: amount,
                location: pointer,
                horizontal: horizontal,
                vertical: vertical
            )
            XCTAssertEqual(outcome, .performed([effect]), "\(direction)")
            XCTAssertEqual(local.effects, [effect])
        }
        XCTAssertEqual(poster.effects, [])
    }

    func testHalfPageUsesTheVisibleAxisAndRoundsAwayFromZero() {
        let pointer = actuatorPoint(20, 30)
        let area = scrollRegion(
            "page",
            containsPointer: true,
            visibleWidth: 3,
            visibleHeight: 801,
            travelLeft: 50,
            travelDown: 50,
            travelUp: 50,
            travelRight: 50
        )
        let context = actuation("com.apple.TextEdit", pointer: pointer, areas: [area])
        let down = RecordingActuator()
        let downAmount = ScrollAmount.fractionOfPage(
            numerator: CommandMap.halfPageNumerator,
            denominator: CommandMap.halfPageDenominator
        )
        XCTAssertEqual(
            outcomeOf(.scroll(direction: .down, amount: downAmount), context: context, poster: down),
            .performed([
                .pointerScroll(
                    targetID: "page",
                    direction: .down,
                    amount: downAmount,
                    location: pointer,
                    horizontal: 0,
                    vertical: -401
                ),
            ])
        )
        let left = RecordingActuator()
        let leftAmount = ScrollAmount.fractionOfPage(numerator: 1, denominator: 2)
        XCTAssertEqual(
            outcomeOf(.scroll(direction: .left, amount: leftAmount), context: context, poster: left),
            .performed([
                .pointerScroll(
                    targetID: "page",
                    direction: .left,
                    amount: leftAmount,
                    location: pointer,
                    horizontal: -2,
                    vertical: 0
                ),
            ])
        )
    }

    func testTinyVisibleHalfPageStillMovesOnePoint() {
        let pointer = actuatorPoint(1, 1)
        let area = scrollRegion(
            "page",
            frame: ActuatorRect(x: 0, y: 0, width: 2, height: 2),
            containsPointer: true,
            visibleWidth: 1,
            visibleHeight: 1,
            travelDown: 10
        )
        let context = actuation("com.apple.TextEdit", pointer: pointer, areas: [area])
        let poster = RecordingActuator()
        let amount = ScrollAmount.fractionOfPage(numerator: 1, denominator: 2)
        XCTAssertEqual(
            outcomeOf(.scroll(direction: .down, amount: amount), context: context, poster: poster),
            .performed([
                .pointerScroll(
                    targetID: "page",
                    direction: .down,
                    amount: amount,
                    location: pointer,
                    horizontal: 0,
                    vertical: -1
                ),
            ])
        )
    }

    func testEdgeScrollSetsTheBarEvenWhenThePointerIsOverTheArea() {
        let context = pageContext(bundle: "com.apple.Safari")
        let topBars = ScriptedEdgeBars(queued: [edgeBar(0.4, settable: true)], stick: true)
        let topPoster = RecordingActuator()
        let top = ActionActuator(poster: topPoster, edgeBars: topBars).perform(
            .scroll(direction: .up, amount: .edge),
            context: context
        )
        XCTAssertEqual(top, .performed([
            .scrollBarEdge(targetID: "page", direction: .up, value: 0),
        ]))
        XCTAssertEqual(topBars.writes, [0])
        let bottomBars = ScriptedEdgeBars(queued: [edgeBar(0.4, settable: true)], stick: true)
        let bottomPoster = RecordingActuator()
        let bottom = ActionActuator(poster: bottomPoster, edgeBars: bottomBars).perform(
            .scroll(direction: .down, amount: .edge),
            context: context
        )
        XCTAssertEqual(bottom, .performed([
            .scrollBarEdge(targetID: "page", direction: .down, value: 1),
        ]))
        XCTAssertEqual(bottomBars.writes, [1])
        for effect in topPoster.effects + bottomPoster.effects {
            if case .pointerScroll = effect {
                XCTFail("a settable bar that stays at the edge is not a wheel: \(effect)")
            }
            if case .shortcut = effect {
                XCTFail("edge scroll must not type a key: \(effect)")
            }
        }
    }

    /// `j` still wheels 60 points at the pointer. `G` on an `AXWebArea` must
    /// use that same area and wheel a long way at its center. Setting the
    /// scrollbar is not a scroll in Safari, Chrome, Arc, or Electron.
    func testWebAreaEdgeScrollWheelsTheSameTargetAtItsCenter() {
        let pointer = actuatorPoint(20, 30)
        var page = scrollRegion(
            "page",
            frame: ActuatorRect(x: 0, y: 0, width: 200, height: 200),
            containsPointer: true,
            isFocusContainer: true,
            travelDown: 1000,
            travelUp: 1000
        )
        page.role = "AXWebArea"
        let context = actuation("com.apple.Safari", pointer: pointer, areas: [page])
        let stepped = RecordingActuator()
        XCTAssertEqual(
            outcomeOf(.scroll(direction: .down, amount: .points(60)), context: context, poster: stepped),
            .performed([
                .pointerScroll(
                    targetID: "page",
                    direction: .down,
                    amount: .points(60),
                    location: pointer,
                    horizontal: 0,
                    vertical: -60
                ),
            ])
        )
        let half = RecordingActuator()
        let halfAmount = ScrollAmount.fractionOfPage(numerator: 1, denominator: 2)
        XCTAssertEqual(
            outcomeOf(.scroll(direction: .down, amount: halfAmount), context: context, poster: half),
            .performed([
                .pointerScroll(
                    targetID: "page",
                    direction: .down,
                    amount: halfAmount,
                    location: pointer,
                    horizontal: 0,
                    vertical: -100
                ),
            ])
        )
        let edge = RecordingActuator()
        let outcome = outcomeOf(.scroll(direction: .down, amount: .edge), context: context, poster: edge)
        guard case .performed(let effects) = outcome, let first = effects.first else {
            return XCTFail("expected wheels, got \(outcome)")
        }
        guard case .pointerScroll(let target, let direction, _, let location, let horizontal, let vertical) = first else {
            return XCTFail("gg/G must wheel the j/k target, got \(effects)")
        }
        XCTAssertEqual(target, "page")
        XCTAssertEqual(direction, .down)
        // The pointer is already over the page, so the wheels go where it is.
        XCTAssertEqual(location, pointer)
        XCTAssertEqual(horizontal, 0)
        XCTAssertLessThan(vertical, -1000)
        for effect in effects {
            if case .shortcut = effect {
                XCTFail("edge scroll must not type Home or End: \(effect)")
            }
            if case .focusScroll = effect {
                XCTFail("AXValue on a web scrollbar is not the scroll: \(effect)")
            }
        }
    }

    func testPointerAreaBeatsTheFocusedArea() {
        let pointer = actuatorPoint(5, 5)
        let side = scrollRegion("side", depth: 1, containsPointer: true, travelDown: 40)
        let document = scrollRegion(
            "doc",
            frame: ActuatorRect(x: 300, y: 0, width: 400, height: 400),
            depth: 9,
            isFocusContainer: true,
            visibleHeight: 100,
            travelDown: 400,
            contentHeight: 900
        )
        let context = actuation("com.apple.Safari", pointer: pointer, areas: [document, side])
        let poster = RecordingActuator()
        let outcome = outcomeOf(
            .scroll(direction: .down, amount: .points(60)),
            context: context,
            poster: poster
        )
        XCTAssertEqual(outcome, .performed([
            .pointerScroll(
                targetID: "side",
                direction: .down,
                amount: .points(60),
                location: pointer,
                horizontal: 0,
                vertical: -60
            ),
        ]))
    }

    func testPointerAreaAtItsEdgeFallsThroughToTheAncestorUnderThePointer() {
        let pointer = actuatorPoint(5, 5)
        let inner = scrollRegion("inner", depth: 4, containsPointer: true, travelDown: 0)
        let outer = scrollRegion("outer", depth: 1, containsPointer: true, travelDown: 80)
        let context = actuation("com.apple.Safari", pointer: pointer, areas: [inner, outer])
        let poster = RecordingActuator()
        XCTAssertEqual(
            outcomeOf(.scroll(direction: .down, amount: .points(60)), context: context, poster: poster),
            .performed([
                .pointerScroll(
                    targetID: "outer",
                    direction: .down,
                    amount: .points(60),
                    location: pointer,
                    horizontal: 0,
                    vertical: -60
                ),
            ])
        )
    }

    func testFocusAreaIsUsedWhenThePointerIsOutsideTheWindow() {
        let pointer = actuatorPoint(-900, 5)
        let side = scrollRegion("side", depth: 3, travelDown: 1)
        let document = scrollRegion(
            "doc",
            frame: ActuatorRect(x: 400, y: 400, width: 100, height: 100),
            depth: 2,
            isFocusContainer: true,
            visibleHeight: 100,
            travelDown: 200,
            contentHeight: 1000
        )
        var context = actuation("com.apple.Safari", pointer: pointer, areas: [side, document])
        context.windowFrame = ActuatorRect(x: 0, y: 0, width: 800, height: 600)
        let poster = RecordingActuator()
        XCTAssertEqual(
            outcomeOf(.scroll(direction: .down, amount: .points(60)), context: context, poster: poster),
            .performed([
                .pointerMove(to: actuatorPoint(450, 450)),
                .pointerScroll(
                    targetID: "doc",
                    direction: .down,
                    amount: .points(60),
                    location: actuatorPoint(450, 450),
                    horizontal: 0,
                    vertical: -60
                ),
            ])
        )
    }

    func testAnAreaThatFitsUnderThePointerDoesNotTakeTheWheelFromItsPane() {
        // Content that fits has no travel either way. The wheel still goes
        // where the pointer is, and the window names the target.
        let pointer = actuatorPoint(5, 5)
        let stuck = scrollRegion("stuck", depth: 3, containsPointer: true, travelDown: 0)
        var context = actuation("com.apple.Safari", pointer: pointer, areas: [stuck])
        context.windowFrame = ActuatorRect(x: 0, y: 0, width: 800, height: 600)
        let poster = RecordingActuator()
        XCTAssertEqual(
            outcomeOf(.scroll(direction: .down, amount: .points(60)), context: context, poster: poster),
            .performed([
                .pointerScroll(
                    targetID: "window",
                    direction: .down,
                    amount: .points(60),
                    location: pointer,
                    horizontal: 0,
                    vertical: -60
                ),
            ])
        )
    }

    func testHalfPageWithoutAPointerMovesToTheFocusedAreaAndUsesItsVisibleSize() {
        let document = scrollRegion(
            "doc",
            isFocusContainer: true,
            visibleWidth: 80,
            visibleHeight: 200,
            travelLeft: 100,
            travelUp: 100,
            contentWidth: 280,
            contentHeight: 1000
        )
        let context = actuation("com.apple.Safari", pointer: nil, areas: [document])
        let poster = RecordingActuator()
        let amount = ScrollAmount.fractionOfPage(numerator: 1, denominator: 2)
        let center = actuatorPoint(100, 100)
        XCTAssertEqual(
            outcomeOf(.scroll(direction: .up, amount: amount), context: context, poster: poster),
            .performed([
                .pointerMove(to: center),
                .pointerScroll(
                    targetID: "doc", direction: .up, amount: amount, location: center, horizontal: 0, vertical: 100
                ),
            ])
        )
        let horizontal = RecordingActuator()
        XCTAssertEqual(
            outcomeOf(.scroll(direction: .left, amount: amount), context: context, poster: horizontal),
            .performed([
                .pointerMove(to: center),
                .pointerScroll(
                    targetID: "doc", direction: .left, amount: amount, location: center, horizontal: -40, vertical: 0
                ),
            ])
        )
    }

    func testOnlyAScrollWithNothingToAimAtPassesThrough() {
        let poster = RecordingActuator()
        let empty = outcomeOf(
            .scroll(direction: .down, amount: .points(60)),
            context: actuation("com.apple.Safari"),
            poster: poster
        )
        XCTAssertEqual(empty, .passedThrough)
        XCTAssertEqual(poster.effects, [])

        // A page whose snapshot says "already at the bottom" still gets the
        // wheel: the snapshot is older than the last scroll.
        let stale = outcomeOf(
            .scroll(direction: .down, amount: .points(60)),
            context: pageContext(bundle: "com.apple.Safari", travelDown: 0),
            poster: poster
        )
        XCTAssertEqual(stale, .performed([
            .pointerScroll(
                targetID: "page",
                direction: .down,
                amount: .points(60),
                location: actuatorPoint(20, 30),
                horizontal: 0,
                vertical: -60
            ),
        ]))
    }

    func testPointerFlagOutsideTheFrameIsRejected() {
        let area = scrollRegion(
            "page",
            frame: ActuatorRect(x: 10, y: 10, width: 10, height: 10),
            containsPointer: true,
            travelDown: 100
        )
        let poster = RecordingActuator()
        let outside = outcomeOf(
            .scroll(direction: .down, amount: .points(60)),
            context: actuation("com.apple.Safari", pointer: actuatorPoint(0, 0), areas: [area]),
            poster: poster
        )
        XCTAssertEqual(outside, .performed([
            .pointerScroll(
                targetID: "window",
                direction: .down,
                amount: .points(60),
                location: actuatorPoint(0, 0),
                horizontal: 0,
                vertical: -60
            ),
        ]))
        let boundary = scrollRegion(
            "edge",
            frame: ActuatorRect(x: 0, y: 0, width: 10, height: 10),
            containsPointer: true,
            travelDown: 100
        )
        let onEdge = outcomeOf(
            .scroll(direction: .down, amount: .points(60)),
            context: actuation("com.apple.Safari", pointer: actuatorPoint(10, 10), areas: [boundary]),
            poster: poster
        )
        XCTAssertEqual(onEdge, .performed([
            .pointerScroll(
                targetID: "edge",
                direction: .down,
                amount: .points(60),
                location: actuatorPoint(10, 10),
                horizontal: 0,
                vertical: -60
            ),
        ]))
    }

    func testNilPointerDoesNotTrustTheContainsPointerFlag() {
        let area = scrollRegion("page", containsPointer: true, isFocusContainer: false, travelDown: 80)
        let poster = RecordingActuator()
        let center = actuatorPoint(100, 100)
        XCTAssertEqual(
            outcomeOf(
                .scroll(direction: .down, amount: .points(60)),
                context: actuation("com.apple.Safari", pointer: nil, areas: [area]),
                poster: poster
            ),
            .performed([
                .pointerMove(to: center),
                .pointerScroll(
                    targetID: "page", direction: .down, amount: .points(60), location: center, horizontal: 0, vertical: -60
                ),
            ])
        )
    }

    func testEqualDepthUsesIdentifierOrder() {
        let pointer = actuatorPoint(4, 4)
        let later = scrollRegion("b", depth: 2, containsPointer: true, travelDown: 10)
        let earlier = scrollRegion("a", depth: 2, containsPointer: true, travelDown: 10)
        let context = actuation("com.apple.Safari", pointer: pointer, areas: [later, earlier])
        let poster = RecordingActuator()
        let outcome = outcomeOf(
            .scroll(direction: .down, amount: .points(60)),
            context: context,
            poster: poster
        )
        guard case .performed(let effects) = outcome, case .pointerScroll(let targetID, _, _, _, _, _) = effects.first else {
            return XCTFail("expected a pointer scroll, got \(outcome)")
        }
        XCTAssertEqual(targetID, "a")
    }

    func testNegativeTravelCannotMoveAndASmallRemainderStillUsesTheFullStep() {
        let pointer = actuatorPoint(4, 4)
        let negative = scrollRegion("neg", depth: 3, containsPointer: true, travelDown: -5)
        let remainder = scrollRegion("bit", depth: 1, containsPointer: true, travelDown: 0.1)
        let context = actuation("com.apple.Safari", pointer: pointer, areas: [negative, remainder])
        let poster = RecordingActuator()
        XCTAssertEqual(
            outcomeOf(.scroll(direction: .down, amount: .points(60)), context: context, poster: poster),
            .performed([
                .pointerScroll(
                    targetID: "bit",
                    direction: .down,
                    amount: .points(60),
                    location: pointer,
                    horizontal: 0,
                    vertical: -60
                ),
            ])
        )
    }

    func testUnsafeScrollAmountsPassThrough() {
        let poster = RecordingActuator()
        let context = pageContext(bundle: "com.apple.Safari")
        let amounts: [ScrollAmount] = [
            .points(0),
            .points(-1),
            .points(Int(Int32.max) + 1),
            .fractionOfPage(numerator: 0, denominator: 2),
            .fractionOfPage(numerator: 1, denominator: 0),
            .fractionOfPage(numerator: -1, denominator: 2),
        ]
        for amount in amounts {
            XCTAssertEqual(
                outcomeOf(.scroll(direction: .down, amount: amount), context: context, poster: poster),
                .passedThrough,
                "\(amount)"
            )
        }
        XCTAssertEqual(poster.effects, [])
        let maxPoster = RecordingActuator()
        XCTAssertEqual(
            outcomeOf(
                .scroll(direction: .up, amount: .points(Int(Int32.max))),
                context: context,
                poster: maxPoster
            ),
            .performed([
                .pointerScroll(
                    targetID: "page",
                    direction: .up,
                    amount: .points(Int(Int32.max)),
                    location: actuatorPoint(20, 30),
                    horizontal: 0,
                    vertical: Int(Int32.max)
                ),
            ])
        )
    }

    func testZeroVisibleFractionSkipsTheArea() {
        let pointer = actuatorPoint(4, 4)
        let broken = scrollRegion(
            "broken",
            depth: 2,
            containsPointer: true,
            visibleHeight: 0,
            travelDown: 50
        )
        let poster = RecordingActuator()
        XCTAssertEqual(
            outcomeOf(
                .scroll(direction: .down, amount: .fractionOfPage(numerator: 1, denominator: 2)),
                context: actuation("com.apple.Safari", pointer: pointer, areas: [broken]),
                poster: poster
            ),
            .passedThrough
        )
        let point = RecordingActuator()
        XCTAssertEqual(
            outcomeOf(
                .scroll(direction: .down, amount: .points(60)),
                context: actuation("com.apple.Safari", pointer: pointer, areas: [broken]),
                poster: point
            ),
            .performed([
                .pointerScroll(
                    targetID: "broken",
                    direction: .down,
                    amount: .points(60),
                    location: pointer,
                    horizontal: 0,
                    vertical: -60
                ),
            ])
        )
    }

    func testFocusedAreaWithoutAPointerTakesWheelsAfterAPointerMove() {
        let document = scrollRegion(
            "doc",
            isFocusContainer: true,
            visibleHeight: 100,
            travelDown: 500,
            contentHeight: nil
        )
        let center = actuatorPoint(100, 100)
        let poster = RecordingActuator()
        XCTAssertEqual(
            outcomeOf(
                .scroll(direction: .down, amount: .points(60)),
                context: actuation("com.apple.Safari", areas: [document]),
                poster: poster
            ),
            .performed([
                .pointerMove(to: center),
                .pointerScroll(
                    targetID: "doc", direction: .down, amount: .points(60), location: center, horizontal: 0, vertical: -60
                ),
            ])
        )
        let edge = RecordingActuator()
        let edgeOutcome = outcomeOf(
            .scroll(direction: .down, amount: .edge),
            context: actuation("com.apple.Safari", areas: [document]),
            poster: edge
        )
        guard case .performed(let effects) = edgeOutcome else {
            return XCTFail("expected wheels, got \(edgeOutcome)")
        }
        XCTAssertEqual(effects.first, .pointerMove(to: center))
        XCTAssertEqual(effects.count, EdgeScroll.unobservedBursts + 1)
        guard case .pointerScroll(let target, _, _, let location, let horizontal, let vertical) = effects.last else {
            return XCTFail("expected a center wheel, got \(effects)")
        }
        XCTAssertEqual(target, "doc")
        XCTAssertEqual(location, center)
        XCTAssertEqual(horizontal, 0)
        XCTAssertEqual(vertical, -EdgeScroll.wheelPixels)
        XCTAssertEqual(edge.effects, effects)
    }

    func testFindCloseNewAndReloadPostInAnyApp() {
        let commands: [KeyCommand] = [.find, .close, .create, .reload]
        for command in commands {
            guard case .sendShortcut(let combo) = CommandMap().action(for: command) else {
                return XCTFail("\(command) should be one shortcut")
            }
            for bundle in ["com.apple.TextEdit", "com.apple.Safari", ""] {
                let poster = RecordingActuator()
                let outcome = outcomeOf(
                    .sendShortcut(combo),
                    context: actuation(bundle),
                    poster: poster
                )
                XCTAssertEqual(outcome, .performed([.shortcut(combo)]), "\(command) \(bundle)")
                XCTAssertEqual(poster.effects, [.shortcut(combo)])
            }
        }
    }

    func testHistoryTabsAndCopyURLArePromisedOnlyForTheAllowlist() {
        let commands: [KeyCommand] = [.historyBack, .historyForward, .previousTab, .nextTab, .copyURL]
        for command in commands {
            let action = CommandMap().action(for: command)
            for bundle in promisedBrowsers {
                let poster = RecordingActuator()
                let outcome = outcomeOf(action, context: actuation(bundle), poster: poster)
                guard case .performed(let effects) = outcome else {
                    return XCTFail("\(command) in \(bundle) got \(outcome)")
                }
                XCTAssertFalse(effects.isEmpty)
                XCTAssertEqual(poster.effects, effects)
                XCTAssertTrue(effects.allSatisfy { effect in
                    if case .shortcut = effect { return true }
                    return false
                })
            }
            for bundle in ["com.apple.TextEdit", "org.mozilla.firefox", "com.operasoftware.Opera", "", "com.apple.Safari ", "Com.apple.Safari"] {
                let poster = RecordingActuator()
                XCTAssertEqual(
                    outcomeOf(action, context: actuation(bundle), poster: poster),
                    .passedThrough,
                    "\(command) \(bundle)"
                )
                XCTAssertEqual(poster.effects, [], "\(command) \(bundle)")
            }
        }
    }

    func testCopyURLPostsCommandLThenCommandCOnlyAsAPair() {
        let poster = RecordingActuator()
        let outcome = outcomeOf(
            CommandMap().action(for: .copyURL),
            context: actuation("com.google.Chrome"),
            poster: poster
        )
        let locate = KeyCombo("l", modifiers: .command)
        let copy = KeyCombo("c", modifiers: .command)
        XCTAssertEqual(outcome, .performed([.shortcut(locate), .shortcut(copy)]))
        XCTAssertEqual(poster.effects, [.shortcut(locate), .shortcut(copy)])

        let lone = RecordingActuator()
        XCTAssertEqual(
            outcomeOf(.sendShortcut(locate), context: actuation("com.apple.Notes"), poster: lone),
            .performed([.shortcut(locate)])
        )
    }

    func testRejectedSequenceDoesNotPostTheFirstShortcut() {
        let poster = RecordingActuator()
        XCTAssertEqual(
            outcomeOf(CommandMap().action(for: .copyURL), context: actuation("com.apple.Notes"), poster: poster),
            .passedThrough
        )
        XCTAssertEqual(poster.effects, [])
    }

    func testSequenceWithNonActuatorWorkPostsNothing() {
        let poster = RecordingActuator()
        let action = Action.sequence([
            .sendShortcut(KeyCombo("f", modifiers: .command)),
            .showHelp,
        ])
        XCTAssertEqual(
            outcomeOf(action, context: actuation("com.apple.Safari"), poster: poster),
            .notActuatorWork
        )
        XCTAssertEqual(poster.effects, [])
    }

    func testRestrictedSequencePassesThroughEveryStepOutsideTheAllowlist() {
        let poster = RecordingActuator()
        let action = Action.sequence([
            .sendShortcut(KeyCombo("[", modifiers: .command)),
            .scroll(direction: .down, amount: .points(60)),
        ])
        XCTAssertEqual(
            outcomeOf(action, context: pageContext(bundle: "com.apple.Notes"), poster: poster),
            .passedThrough
        )
        XCTAssertEqual(poster.effects, [])
        let allowed = RecordingActuator()
        let outcome = outcomeOf(action, context: pageContext(bundle: "com.apple.Safari"), poster: allowed)
        guard case .performed(let effects) = outcome else {
            return XCTFail("expected both steps, got \(outcome)")
        }
        XCTAssertEqual(effects.count, 2)
        XCTAssertEqual(allowed.effects, effects)
    }

    func testSequencePostsNothingWhenALaterScrollHasNoTarget() {
        let poster = RecordingActuator()
        let action = Action.sequence([
            .sendShortcut(KeyCombo("f", modifiers: .command)),
            .scroll(direction: .down, amount: .points(60)),
        ])
        XCTAssertEqual(
            outcomeOf(action, context: actuation("com.apple.Notes"), poster: poster),
            .passedThrough
        )
        XCTAssertEqual(poster.effects, [])
    }

    func testUncomputableFractionsAndRangesPassThrough() {
        let pointer = actuatorPoint(4, 4)
        let half = ScrollAmount.fractionOfPage(numerator: 1, denominator: 2)
        let cases: [ScrollArea] = [
            scrollRegion("inf", containsPointer: true, visibleHeight: .infinity, travelDown: 10),
            scrollRegion("tiny", containsPointer: true, visibleHeight: 0.4, travelDown: 10),
            scrollRegion(
                "huge",
                containsPointer: true,
                visibleHeight: Double(Int32.max) * 4,
                travelDown: 10
            ),
        ]
        for area in cases {
            let poster = RecordingActuator()
            XCTAssertEqual(
                outcomeOf(
                    .scroll(direction: .down, amount: half),
                    context: actuation("com.apple.Safari", pointer: pointer, areas: [area]),
                    poster: poster
                ),
                .passedThrough,
                area.identifier
            )
            XCTAssertEqual(poster.effects, [], area.identifier)
        }
    }

    func testUnknownShortcutCharacterPassesThrough() {
        let poster = RecordingActuator()
        XCTAssertEqual(
            outcomeOf(
                .sendShortcut(KeyCombo("é", modifiers: .command)),
                context: actuation("com.apple.Safari"),
                poster: poster
            ),
            .passedThrough
        )
        XCTAssertEqual(
            outcomeOf(
                .sendShortcut(KeyCombo("F", modifiers: .command)),
                context: actuation("com.apple.Safari"),
                poster: poster
            ),
            .passedThrough
        )
        XCTAssertEqual(poster.effects, [])
    }

    func testEveryDefaultActionIsPerformedPassedOrLeftAlone() {
        let scrollable = pageContext(bundle: "ignored")
        for binding in CommandMap().bindings {
            for bundle in ["com.apple.Safari", "com.apple.Notes"] {
                var context = scrollable
                context.bundleIdentifier = bundle
                let poster = RecordingActuator()
                let outcome = outcomeOf(binding.action, context: context, poster: poster)
                let restricted: Set<String> = ["H", "L", "J", "K", "yy"]
                switch binding.action {
                case .scroll(_, .edge):
                    guard case .performed(let effects) = outcome,
                          effects.count == EdgeScroll.unobservedBursts
                    else {
                        return XCTFail("\(binding.keys) should wheel to the edge, got \(outcome)")
                    }
                    XCTAssertEqual(poster.effects, effects)
                    XCTAssertTrue(effects.allSatisfy { effect in
                        if case .pointerScroll = effect { return true }
                        return false
                    })
                case .scroll:
                    guard case .performed(let effects) = outcome, effects.count == 1 else {
                        return XCTFail("\(binding.keys) should scroll, got \(outcome)")
                    }
                    XCTAssertEqual(poster.effects, effects)
                case .sendShortcut, .sequence:
                    if restricted.contains(binding.keys) && !promisedBrowsers.contains(bundle) {
                        XCTAssertEqual(outcome, .passedThrough, binding.keys)
                        XCTAssertEqual(poster.effects, [])
                    } else {
                        guard case .performed(let effects) = outcome, !effects.isEmpty else {
                            return XCTFail("\(binding.keys) in \(bundle) got \(outcome)")
                        }
                        XCTAssertEqual(poster.effects, effects)
                    }
                case .beginHint, .showHelp, .focusFirstInput, .passNextKey, .escape, .enterInsert:
                    XCTAssertEqual(outcome, .notActuatorWork, binding.keys)
                    XCTAssertEqual(poster.effects, [])
                }
            }
        }
    }

    func testHitRuleIsWrittenNextToTheSelector() throws {
        let text = try String(contentsOf: actuatorSource, encoding: .utf8)
        XCTAssertTrue(text.contains("Scroll hit rule."))
        XCTAssertTrue(text.contains("large wheel events at the area's center"))
        XCTAssertTrue(text.contains("do not send Home, End, or Command+arrow"))
        XCTAssertFalse(text.contains("A wheel event is not used for an edge"))
        XCTAssertTrue(text.contains("contains the pointer"))
        XCTAssertTrue(text.contains("isFocusContainer"))
        XCTAssertFalse(text.contains("case right"))
        XCTAssertFalse(text.contains("rightMouse"))
        for token in ["import AppKit", "import CoreGraphics", "CGEvent", "AXUIElement", "URLSession", "print("] {
            XCTAssertFalse(text.contains(token), token)
        }
    }

    func testCoreGraphicsPosterIsGuardedMarksEventsAndDoesNotRightClick() throws {
        let text = try String(contentsOf: coreGraphicsSource, encoding: .utf8)
        XCTAssertTrue(text.contains("#if canImport(CoreGraphics) && canImport(ApplicationServices)"))
        XCTAssertTrue(text.contains("SynthesizedEventMark.userData"))
        XCTAssertTrue(text.contains("eventSourceUserData"))
        XCTAssertTrue(text.contains("kAXPressAction"))
        XCTAssertTrue(text.contains("AXUIElementIsAttributeSettable"))
        XCTAssertTrue(text.contains("scrollBarEdge"))
        XCTAssertFalse(text.contains("kVK_Home"))
        XCTAssertFalse(text.contains("kVK_End"))
        XCTAssertTrue(text.contains("AXUIElementPerformAction"))
        XCTAssertTrue(text.contains(".leftMouseDown"))
        XCTAssertTrue(text.contains(".leftMouseUp"))
        XCTAssertTrue(text.contains(".pixel"))
        XCTAssertTrue(text.contains(".keyDown"))
        XCTAssertTrue(text.contains(".keyUp"))
        XCTAssertFalse(text.contains("rightMouse"))
        XCTAssertFalse(text.contains("kCGMouseButtonRight"))
        XCTAssertFalse(text.contains("mouseButton: .right"))
        for token in ["URLSession", "os_log", "NSLog", "print("] {
            XCTAssertFalse(text.contains(token), token)
        }
    }

    func testPlaceholderDoesNotPerformActions() throws {
        let text = try appTargetSource()
        for token in ["ActionActuator", "CGEventActuator", "AXUIElement"] {
            XCTAssertFalse(text.contains(token), token)
        }
    }

    func testContentScrollSkipsTheInputAndAimsTheWheelAtTheChosenCenter() {
        let input = ActuatorRect(x: 0, y: 500, width: 200, height: 40)
        let composer = contentArea(
            "composer",
            frame: input,
            depth: 3,
            travelUp: 10,
            role: "AXScrollArea",
            textInput: true
        )
        let history = contentArea(
            "history",
            frame: ActuatorRect(x: 0, y: 0, width: 200, height: 480),
            depth: 1,
            travelUp: 80,
            role: "AXScrollArea"
        )
        let sidebar = contentArea(
            "sidebar",
            frame: ActuatorRect(x: 0, y: 0, width: 40, height: 480),
            depth: 2,
            travelUp: 20,
            travelDown: 20,
            travelLeft: 5,
            travelRight: 5,
            role: "AXWebArea"
        )
        let stuck = contentArea(
            "stuck",
            frame: ActuatorRect(x: 0, y: 0, width: 900, height: 900),
            travelUp: 0,
            role: "AXWebArea"
        )
        let overHistory = ContentScroll.aim(
            areas: [composer, history, sidebar],
            pointer: actuatorPoint(20, 20),
            excludedFrame: input,
            direction: .up
        )
        XCTAssertEqual(overHistory?.area.identifier, "sidebar")
        XCTAssertEqual(overHistory?.location, actuatorPoint(20, 240))

        let overComposer = ContentScroll.aim(
            areas: [composer, history],
            pointer: actuatorPoint(20, 520),
            excludedFrame: input,
            direction: .up
        )
        XCTAssertEqual(overComposer?.area.identifier, "history")
        XCTAssertEqual(overComposer?.location, actuatorPoint(100, 240))

        let parent = contentArea(
            "parent",
            frame: ActuatorRect(x: 0, y: 0, width: 400, height: 600),
            depth: 1,
            travelDown: 30,
            role: "AXWebArea"
        )
        let nested = ContentScroll.aim(
            areas: [composer, parent],
            pointer: actuatorPoint(20, 520),
            excludedFrame: input,
            direction: .down
        )
        XCTAssertEqual(nested?.area.identifier, "parent")

        XCTAssertNil(
            ContentScroll.aim(
                areas: [composer, stuck],
                pointer: nil,
                excludedFrame: input,
                direction: .up
            )
        )
        let sideways = ContentScroll.aim(
            areas: [sidebar],
            pointer: nil,
            excludedFrame: nil,
            direction: .left
        )
        XCTAssertEqual(sideways?.area.identifier, "sidebar")
        XCTAssertEqual(
            ContentScroll.aim(
                areas: [sidebar],
                pointer: actuatorPoint(1, 1),
                excludedFrame: nil,
                direction: .right
            )?.area.identifier,
            "sidebar"
        )
        let tieA = contentArea("b", frame: ActuatorRect(x: 0, y: 0, width: 10, height: 10), travelUp: 1, role: "AXGroup")
        let tieB = contentArea("a", frame: ActuatorRect(x: 30, y: 0, width: 10, height: 10), travelUp: 1, role: "AXGroup")
        XCTAssertEqual(
            ContentScroll.aim(areas: [tieA, tieB], pointer: nil, excludedFrame: nil, direction: .up)?.area.identifier,
            "a"
        )
    }

    func testEdgeScrollNamesAndLogLine() {
        XCTAssertEqual(EdgeScroll.names(for: .up).sequence, "gg")
        XCTAssertEqual(EdgeScroll.names(for: .up).command, "scrollToTop")
        XCTAssertEqual(EdgeScroll.names(for: .down).sequence, "G")
        XCTAssertEqual(EdgeScroll.names(for: .down).command, "scrollToBottom")
        XCTAssertEqual(EdgeScroll.names(for: .left).sequence, "edge-left")
        XCTAssertEqual(EdgeScroll.names(for: .right).command, "scrollToRightEdge")
        let line = EdgeScroll.logLine(
            sequence: "gg",
            command: "scrollToTop",
            role: "AXWebArea",
            target: "page",
            strategy: "wheel",
            result: "atEdge"
        )
        XCTAssertEqual(
            line,
            "scroll-edge sequence=gg command=scrollToTop role=AXWebArea target=page strategy=wheel result=atEdge"
        )
    }

    func testUnsettableWebBarWheelsUntilTheEdgeOrTheBurstEnds() {
        let reaching = ScriptedEdgeBars(queued: [
            edgeBar(0.2, settable: false),
            edgeBar(0.6, settable: false),
            edgeBar(1, settable: false),
        ])
        var wheels: [(Int, Int)] = []
        let reached = EdgeScroll.perform(
            targetID: "page",
            direction: .down,
            role: "AXWebArea",
            sequence: "G",
            command: "scrollToBottom",
            bars: reaching
        ) { horizontal, vertical in
            wheels.append((horizontal, vertical))
        }
        XCTAssertEqual(wheels.count, 2)
        XCTAssertEqual(wheels.map(\.0), [0, 0])
        XCTAssertEqual(wheels.map(\.1), [-EdgeScroll.wheelPixels, -EdgeScroll.wheelPixels])
        XCTAssertEqual(reached.strategy, "wheel")
        XCTAssertEqual(reached.result, "atEdge")
        XCTAssertEqual(reached.logLine, EdgeScroll.logLine(
            sequence: "G",
            command: "scrollToBottom",
            role: "AXWebArea",
            target: "page",
            strategy: "wheel",
            result: "atEdge"
        ))
        XCTAssertTrue(reaching.writes.isEmpty)

        let stuck = ScriptedEdgeBars(queued: [edgeBar(0.2, settable: false)])
        var stuckWheels = 0
        let unobserved = EdgeScroll.perform(
            targetID: "page",
            direction: .up,
            role: "",
            sequence: "gg",
            command: "scrollToTop",
            bars: stuck
        ) { _, _ in
            stuckWheels += 1
        }
        XCTAssertEqual(stuckWheels, EdgeScroll.unobservedBursts)
        XCTAssertEqual(unobserved.result, "unobserved")
        XCTAssertEqual(unobserved.role, "-")
        XCTAssertEqual(unobserved.strategy, "wheel")
    }

    func testSettableBarThatDoesNotStickWheelsUntilTheValueStops() {
        let bars = ScriptedEdgeBars(
            queued: [
                edgeBar(0.4, settable: true),
                edgeBar(0.7, settable: true),
                edgeBar(0.7, settable: true),
            ],
            current: edgeBar(0.4, settable: true)
        )
        var wheels = 0
        let report = EdgeScroll.perform(
            targetID: "page",
            direction: .down,
            role: "AXScrollArea",
            sequence: "G",
            command: "scrollToBottom",
            bars: bars
        ) { _, _ in
            wheels += 1
        }
        XCTAssertEqual(bars.writes, [1])
        XCTAssertEqual(wheels, 2)
        XCTAssertEqual(report.strategy, "wheel")
        XCTAssertEqual(report.result, "moved")

        let dropped = ScriptedEdgeBars(
            queued: [edgeBar(0.2, settable: true), edgeBar(0.6, settable: true), nil],
            current: edgeBar(0.2, settable: true)
        )
        var droppedWheels = 0
        let moved = EdgeScroll.perform(
            targetID: "doc",
            direction: .up,
            role: "AXScrollArea",
            sequence: "gg",
            command: "scrollToTop",
            bars: dropped
        ) { _, _ in
            droppedWheels += 1
        }
        XCTAssertEqual(dropped.writes, [0])
        XCTAssertEqual(droppedWheels, 2)
        XCTAssertEqual(moved.result, "moved")

        let vanished = ScriptedEdgeBars(
            queued: [edgeBar(0.2, settable: true), nil],
            current: edgeBar(0.2, settable: true)
        )
        var vanishedWheels = 0
        let unchanged = EdgeScroll.perform(
            targetID: "doc",
            direction: .down,
            role: "AXScrollArea",
            sequence: "G",
            command: "scrollToBottom",
            bars: vanished
        ) { _, _ in
            vanishedWheels += 1
        }
        XCTAssertEqual(vanished.writes, [1])
        XCTAssertEqual(vanishedWheels, 1)
        XCTAssertEqual(unchanged.result, "unchanged")
    }

    func testMissingOrUselessBarPostsABoundedCenterWheelAndNoKeys() {
        var missing = 0
        var horizontal = 0
        let report = EdgeScroll.perform(
            targetID: "page",
            direction: .left,
            role: nil,
            sequence: "edge-left",
            command: "scrollToLeftEdge",
            bars: nil
        ) { x, y in
            missing += 1
            horizontal = x
            XCTAssertEqual(y, 0)
        }
        XCTAssertEqual(missing, EdgeScroll.unobservedBursts)
        XCTAssertEqual(horizontal, -EdgeScroll.wheelPixels)
        XCTAssertEqual(report.result, "unobserved")
        XCTAssertEqual(report.role, "-")

        let useless = ScriptedEdgeBars(queued: [
            EdgeBar(value: .nan, minimum: 0, maximum: 1, settable: true),
        ])
        var uselessWheels = 0
        let fallback = EdgeScroll.perform(
            targetID: "page",
            direction: .right,
            role: "AXWebArea",
            sequence: "edge-right",
            command: "scrollToRightEdge",
            bars: useless
        ) { x, y in
            uselessWheels += 1
            XCTAssertEqual(x, EdgeScroll.wheelPixels)
            XCTAssertEqual(y, 0)
        }
        XCTAssertEqual(uselessWheels, EdgeScroll.unobservedBursts)
        XCTAssertTrue(useless.writes.isEmpty)
        XCTAssertEqual(fallback.strategy, "wheel")

        let parked = ScriptedEdgeBars(queued: [edgeBar(0, settable: false)])
        var parkedWheels = 0
        let already = EdgeScroll.perform(
            targetID: "page",
            direction: .up,
            role: "AXWebArea",
            sequence: "gg",
            command: "scrollToTop",
            bars: parked
        ) { _, _ in
            parkedWheels += 1
        }
        XCTAssertEqual(parkedWheels, 0)
        XCTAssertTrue(parked.writes.isEmpty)
        XCTAssertEqual(already.strategy, "scrollBarValue")
        XCTAssertEqual(already.result, "alreadyAtEdge")
        XCTAssertEqual(already.value, 0)
    }

    func testSettableBarThatKeepsMovingStopsAtTheBurstCap() {
        let bars = ClimbingEdgeBars()
        var wheels = 0
        let report = EdgeScroll.perform(
            targetID: "page",
            direction: .down,
            role: "AXScrollArea",
            sequence: "G",
            command: "scrollToBottom",
            bars: bars
        ) { _, _ in
            wheels += 1
        }
        XCTAssertEqual(bars.writes, [10])
        XCTAssertEqual(wheels, EdgeScroll.maxBursts)
        XCTAssertEqual(report.result, "moved")
        XCTAssertEqual(report.strategy, "wheel")
    }

    func testFrameContainsTheInclusiveBoundary() {
        let frame = ActuatorRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertTrue(frame.contains(actuatorPoint(0, 0)))
        XCTAssertTrue(frame.contains(actuatorPoint(10, 10)))
        XCTAssertFalse(frame.contains(actuatorPoint(10.1, 10)))
        XCTAssertFalse(ActuatorRect(x: 0, y: 0, width: 0, height: 10).contains(actuatorPoint(0, 0)))
        XCTAssertFalse(frame.contains(actuatorPoint(Double.nan, 0)))
    }
}

private let promisedBrowsers = [
    "com.apple.Safari",
    "com.google.Chrome",
    "org.chromium.Chromium",
    "com.microsoft.edgemac",
    "com.brave.Browser",
    "company.thebrowser.Browser",
    "com.vivaldi.Vivaldi",
]

private let actuatorSource = repoRoot().appendingPathComponent("Sources/SupervimSystem/Actuator.swift")
private let coreGraphicsSource = repoRoot().appendingPathComponent("Sources/SupervimSystem/CGEventActuator.swift")

private func contentArea(
    _ identifier: String,
    frame: ActuatorRect,
    depth: Int = 1,
    travelUp: Double = 0,
    travelDown: Double = 0,
    travelLeft: Double = 0,
    travelRight: Double = 0,
    role: String? = nil,
    textInput: Bool = false
) -> ScrollArea {
    var area = scrollRegion(
        identifier,
        frame: frame,
        depth: depth,
        travelLeft: travelLeft,
        travelDown: travelDown,
        travelUp: travelUp,
        travelRight: travelRight
    )
    area.role = role
    area.isTextInput = textInput
    return area
}

private func edgeBar(
    _ value: Double,
    settable: Bool,
    minimum: Double = 0,
    maximum: Double = 1
) -> EdgeBar {
    EdgeBar(value: value, minimum: minimum, maximum: maximum, settable: settable)
}

private final class ScriptedEdgeBars: EdgeScrollBars, @unchecked Sendable {
    var queued: [EdgeBar?]
    var current: EdgeBar?
    var stick: Bool
    private(set) var writes: [Double] = []

    init(queued: [EdgeBar?] = [], current: EdgeBar? = nil, stick: Bool = false) {
        self.queued = queued
        self.current = current
        self.stick = stick
    }

    func bar(elementID: String, direction: ScrollDirection) -> EdgeBar? {
        _ = (elementID, direction)
        if !queued.isEmpty {
            return queued.removeFirst()
        }
        return current
    }

    func writeBar(elementID: String, direction: ScrollDirection, value: Double) -> Double? {
        _ = (elementID, direction)
        writes.append(value)
        if stick {
            current?.value = value
            return value
        }
        return current?.value
    }
}

private final class ClimbingEdgeBars: EdgeScrollBars, @unchecked Sendable {
    private var value = 0.2
    private(set) var writes: [Double] = []

    func bar(elementID: String, direction: ScrollDirection) -> EdgeBar? {
        _ = (elementID, direction)
        let bar = EdgeBar(value: value, minimum: 0, maximum: 10, settable: true)
        value += 0.01
        return bar
    }

    func writeBar(elementID: String, direction: ScrollDirection, value: Double) -> Double? {
        _ = (elementID, direction)
        writes.append(value)
        return 0.2
    }
}

private func actuatorPoint(_ x: Double, _ y: Double) -> ActuatorPoint {
    ActuatorPoint(x: x, y: y)
}

private func actuation(
    _ bundleIdentifier: String,
    pointer: ActuatorPoint? = nil,
    areas: [ScrollArea] = []
) -> ActuationContext {
    ActuationContext(bundleIdentifier: bundleIdentifier, pointer: pointer, scrollAreas: areas)
}

private func scrollRegion(
    _ identifier: String,
    frame: ActuatorRect = ActuatorRect(x: 0, y: 0, width: 200, height: 200),
    depth: Int = 0,
    containsPointer: Bool = false,
    isFocusContainer: Bool = false,
    visibleWidth: Double = 200,
    visibleHeight: Double = 200,
    travelLeft: Double = 0,
    travelDown: Double = 0,
    travelUp: Double = 0,
    travelRight: Double = 0,
    contentWidth: Double? = nil,
    contentHeight: Double? = nil
) -> ScrollArea {
    ScrollArea(
        identifier: identifier,
        frame: frame,
        depth: depth,
        containsPointer: containsPointer,
        isFocusContainer: isFocusContainer,
        visibleWidth: visibleWidth,
        visibleHeight: visibleHeight,
        travelLeft: travelLeft,
        travelDown: travelDown,
        travelUp: travelUp,
        travelRight: travelRight,
        contentWidth: contentWidth,
        contentHeight: contentHeight
    )
}

private func pageContext(
    bundle: String,
    pointer: ActuatorPoint = actuatorPoint(20, 30),
    travelDown: Double = 1000
) -> ActuationContext {
    actuation(
        bundle,
        pointer: pointer,
        areas: [
            scrollRegion(
                "page",
                containsPointer: true,
                isFocusContainer: true,
                travelLeft: 1000,
                travelDown: travelDown,
                travelUp: 1000,
                travelRight: 1000,
                contentWidth: 2000,
                contentHeight: 2000
            ),
        ]
    )
}

private func outcomeOf(
    _ action: Action,
    context: ActuationContext,
    poster: RecordingActuator
) -> ActuatorOutcome {
    ActionActuator(poster: poster).perform(action, context: context)
}

private func clickOutcome(_ request: ClickRequest, poster: RecordingActuator) -> ActuatorOutcome {
    ActionActuator(poster: poster).click(request)
}

private final class RecordingActuator: ActuatorPosting, @unchecked Sendable {
    private(set) var effects: [ActuatorEffect] = []

    func post(_ effect: ActuatorEffect) {
        effects.append(effect)
    }
}

private func sourceFiles(under root: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
        return []
    }
    var files: [URL] = []
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        files.append(url)
    }
    return files
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

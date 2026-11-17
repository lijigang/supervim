import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// Hint labels, typed clicks, and cancellation behind a fake scanner and poster.
/// The event hook itself must not scan or draw.
final class HintOverlayTests: XCTestCase {
    func testRefreshReadsTheScannerAndBeginHintDoesNot() {
        let rig = makeRig(elements: [oneBox()])
        XCTAssertEqual(rig.querier.reads, 0)
        guard case .elements(let snapshot) = rig.controller.refreshClickables() else {
            return XCTFail("refresh should publish the scanner snapshot")
        }
        XCTAssertEqual(snapshot.elements, [oneBox()])
        XCTAssertEqual(rig.querier.reads, 1)

        rig.querier.query = .unavailable
        let begin = rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus)
        let shown = rig.controller.consume(begin)
        XCTAssertEqual(rig.querier.reads, 1)
        guard case .showing(let presentation) = shown else {
            return XCTFail("begin should use the cached snapshot, got \(shown)")
        }
        XCTAssertEqual(presentation.markers.map(\.text), ["A"])
        XCTAssertEqual(presentation.policy, .hintLabels)
    }

    func testBeginHintPresentsTransparentNonActivatingLabels() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        let shown = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        let presentation = OverlayPresentation(
            markers: [HintMarker(index: 0, text: "A", anchor: HintPoint(x: 10, y: 20))],
            policy: OverlayWindowPolicy.hintLabels
        )
        XCTAssertEqual(shown, .showing(presentation))
        XCTAssertEqual(rig.presenter.presentations, [presentation])
        XCTAssertEqual(rig.presenter.hides, 0)
        XCTAssertTrue(presentation.policy.isTransparent)
        XCTAssertTrue(presentation.policy.isNonActivating)
        XCTAssertTrue(presentation.policy.ignoresMouseEvents)
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.interpreter.mode, .hint(.plain))
    }

    func testTypingALabelClicksTheCenterAndLeavesHint() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        let typed = rig.interpreter.handleKeyDown(KeyEvent("a"), cache: safariFocus)
        XCTAssertEqual(typed.mode, .hint(.plain))
        XCTAssertEqual(typed.overlay, .hintKey(KeyEvent("a")))
        XCTAssertEqual(
            rig.controller.consume(typed),
            .activated(
                HintActivation(index: 0, click: .plain, point: HintPoint(x: 14, y: 23), identifier: "2/0"),
                .performed([plainClick(x: 14, y: 23)])
            )
        )
        XCTAssertEqual(rig.poster.effects, [plainClick(x: 14, y: 23)])
        XCTAssertEqual(rig.presenter.hides, 1)
        XCTAssertEqual(rig.interpreter.mode, .normal)
        XCTAssertEqual(
            rig.interpreter.handleKeyDown(KeyEvent("j"), cache: safariFocus).actions,
            [CommandMap().action(for: .scrollDown)]
        )
        XCTAssertEqual(rig.querier.reads, 1)
    }

    func testFCommandClicksWithCommandAndNotAContextMenu() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("F"), cache: safariFocus))
        let typed = rig.interpreter.handleKeyDown(KeyEvent("a"), cache: safariFocus)
        let effect = ActuatorEffect.mouseClick(
            point: ActuatorPoint(x: 14, y: 23),
            button: .left,
            modifiers: .command
        )
        XCTAssertEqual(
            rig.controller.consume(typed),
            .activated(
                HintActivation(index: 0, click: .command, point: HintPoint(x: 14, y: 23), identifier: "2/0"),
                .performed([effect])
            )
        )
        XCTAssertEqual(rig.poster.effects, [effect])
        XCTAssertEqual(rig.interpreter.mode, .normal)
        XCTAssertEqual(rig.presenter.hides, 1)
    }

    func testPartialInputUpdatesMarkersWithoutClicking() {
        let rig = makeRig(elements: tenBoxes())
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        let partial = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("a"), cache: safariFocus))
        XCTAssertEqual(partial, .showing(OverlayPresentation(
            markers: [
                HintMarker(index: 0, text: "AA", anchor: HintPoint(x: 0, y: 0)),
                HintMarker(index: 9, text: "AS", anchor: HintPoint(x: 270, y: 0)),
            ],
            policy: .hintLabels
        )))
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.presenter.hides, 0)
        XCTAssertEqual(rig.interpreter.mode, .hint(.plain))
        XCTAssertEqual(rig.presenter.presentations.count, 2)
    }

    func testInvalidInputCancelsWithoutClicking() {
        let rig = makeRig(elements: tenBoxes())
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("a"), cache: safariFocus))
        let bad = rig.interpreter.handleKeyDown(KeyEvent("q"), cache: safariFocus)
        XCTAssertEqual(bad.mode, .hint(.plain))
        XCTAssertEqual(rig.controller.consume(bad), .cancelled(.invalidInput))
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.presenter.hides, 1)
        XCTAssertEqual(rig.interpreter.mode, .normal)
        let stray = rig.controller.consume(EventDecision(
            delivery: .swallow,
            mode: .normal,
            overlay: .hintKey(KeyEvent("a"))
        ))
        XCTAssertEqual(stray, .inactive)
        XCTAssertEqual(rig.poster.effects, [])
    }

    func testEscapeHidesWithoutClicking() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        let escape = rig.interpreter.handleKeyDown(KeyEvent(identity: .escape), cache: safariFocus)
        XCTAssertEqual(escape.overlay, .endHint)
        XCTAssertEqual(escape.mode, .normal)
        XCTAssertEqual(rig.controller.consume(escape), .cancelled(.dismissed))
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.presenter.hides, 1)
        XCTAssertEqual(rig.interpreter.mode, .normal)
    }

    func testUnnamedKeyCancelsAndBackspaceFilters() {
        let rig = makeRig(elements: tenBoxes())
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("a"), cache: safariFocus))
        XCTAssertEqual(rig.presenter.presentations.last?.markers.count, 2)
        let delete = rig.interpreter.handleKeyDown(KeyEvent(identity: .unnamed), cache: safariFocus)
        let filtered = rig.controller.consume(delete, hintKeyCode: HintTyping.backspaceKeyCode)
        guard case .showing(let presentation) = filtered else {
            return XCTFail("delete should remove the typed character, got \(filtered)")
        }
        XCTAssertEqual(presentation.markers.count, 10)
        XCTAssertEqual(rig.poster.effects, [])

        let arrow = rig.interpreter.handleKeyDown(KeyEvent(identity: .unnamed), cache: safariFocus)
        XCTAssertEqual(rig.controller.consume(arrow, hintKeyCode: 0x7B), .cancelled(.invalidInput))
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.interpreter.mode, .normal)
    }

    func testBackspaceWithNoCodeStillCancelsWhenTheCharacterIsUnnamed() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        let unnamed = rig.interpreter.handleKeyDown(KeyEvent(identity: .unnamed), cache: safariFocus)
        XCTAssertEqual(rig.controller.consume(unnamed), .cancelled(.invalidInput))
        XCTAssertEqual(rig.poster.effects, [])
    }

    func testBeginWithoutRefreshCancelsAsUnavailable() {
        let rig = makeRig(elements: [oneBox()])
        let begin = rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus)
        XCTAssertEqual(rig.controller.consume(begin), .cancelled(.unavailable))
        XCTAssertEqual(rig.querier.reads, 0)
        XCTAssertEqual(rig.presenter.presentations, [])
        XCTAssertEqual(rig.presenter.hides, 1)
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.interpreter.mode, .normal)
    }

    func testEmptySnapshotCancelsWithoutAClick() {
        let rig = makeRig(elements: [])
        _ = rig.controller.refreshClickables()
        let begin = rig.interpreter.handleKeyDown(KeyEvent("F"), cache: safariFocus)
        XCTAssertEqual(rig.controller.consume(begin), .cancelled(.noTargets))
        XCTAssertEqual(rig.presenter.presentations, [])
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.interpreter.mode, .normal)
    }

    func testShowHelpDoesNotPresentOrClick() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        let help = rig.interpreter.handleKeyDown(KeyEvent("?"), cache: safariFocus)
        XCTAssertEqual(help.overlay, .showHelp)
        XCTAssertEqual(rig.controller.consume(help), .ignored)
        XCTAssertEqual(rig.presenter.presentations, [])
        XCTAssertEqual(rig.presenter.hides, 0)
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.interpreter.mode, .normal)
    }

    func testNoOverlayDecisionDoesNothing() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        let scrolled = rig.interpreter.handleKeyDown(KeyEvent("j"), cache: safariFocus)
        XCTAssertNil(scrolled.overlay)
        XCTAssertEqual(rig.controller.consume(scrolled), .unchanged)
        XCTAssertEqual(rig.presenter.presentations, [])
        XCTAssertEqual(rig.poster.effects, [])
    }

    func testEditableFocusEndsHintWithoutClickingTheCharacter() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        let typed = rig.interpreter.handleKeyDown(KeyEvent("a"), cache: editableFocus)
        XCTAssertEqual(typed.overlay, .endHint)
        XCTAssertEqual(typed.delivery, .passThrough)
        XCTAssertEqual(rig.controller.consume(typed), .cancelled(.dismissed))
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.interpreter.mode, .insert)
    }

    func testExcludedAppEndsHintWithoutClicking() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        let typed = rig.interpreter.handleKeyDown(KeyEvent("a"), cache: terminalFocus)
        XCTAssertEqual(typed.overlay, .endHint)
        XCTAssertEqual(typed.delivery, .passThrough)
        XCTAssertEqual(rig.controller.consume(typed), .cancelled(.dismissed))
        XCTAssertEqual(rig.poster.effects, [])
    }

    func testUnknownFocusEndsHintWithoutClicking() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        let typed = rig.interpreter.handleKeyDown(KeyEvent("a"), cache: unknownFocus)
        XCTAssertEqual(typed.overlay, .endHint)
        XCTAssertEqual(rig.controller.consume(typed), .cancelled(.dismissed))
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.interpreter.mode, .normal)
    }

    func testPauseHidesHintsWithoutClicking() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        let pause = rig.interpreter.handleKeyDown(
            KeyEvent("v", modifiers: [.control, .option]),
            cache: safariFocus
        )
        XCTAssertEqual(pause.overlay, .endHint)
        XCTAssertEqual(pause.mode, .paused)
        XCTAssertEqual(rig.controller.consume(pause), .cancelled(.dismissed))
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.presenter.hides, 1)
    }

    func testPlainClickStaysALeftClickWhenTheElementOffersPress() {
        var box = oneBox()
        box.actions = ["AXPress", "AXConfirm"]
        let rig = makeRig(elements: [box])
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("a"), cache: safariFocus))
        XCTAssertEqual(rig.poster.effects, [plainClick(x: 14, y: 23)])
    }

    func testCommandModifiedLetterKeepsTheArmedPlainClick() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        let chord = KeyEvent("a", modifiers: .command)
        let typed = rig.interpreter.handleKeyDown(chord, cache: safariFocus)
        XCTAssertEqual(typed.overlay, .hintKey(chord))
        _ = rig.controller.consume(typed)
        XCTAssertEqual(rig.poster.effects, [plainClick(x: 14, y: 23)])
        XCTAssertEqual(rig.interpreter.mode, .normal)
    }

    func testShiftedLetterSelectsTheSameLabel() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("A"), cache: safariFocus))
        XCTAssertEqual(rig.poster.effects, [plainClick(x: 14, y: 23)])
    }

    func testASecondHintReplacesTheMarkers() {
        let rig = makeRig(elements: [oneBox()])
        _ = rig.controller.refreshClickables()
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        rig.querier.query = .elements(ClickableSnapshot(elements: tenBoxes(), truncated: false))
        _ = rig.controller.refreshClickables()
        let again = rig.controller.consume(EventDecision(
            delivery: .swallow,
            mode: .hint(.command),
            overlay: .beginHint(.command)
        ))
        guard case .showing(let presentation) = again else {
            return XCTFail("a new hint should replace the old labels, got \(again)")
        }
        XCTAssertEqual(presentation.markers.count, 10)
        XCTAssertEqual(presentation.markers.first?.text, "AA")
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.querier.reads, 2)
    }

    func testUnusableCachedFramesAreNotLabeled() {
        let flat = ClickableElement(
            role: "AXButton",
            actions: ["AXPress"],
            frame: ElementFrame(x: 0, y: 0, width: 0, height: 4),
            path: [1]
        )
        let rig = makeRig(elements: [flat, oneBox()])
        _ = rig.controller.refreshClickables()
        let shown = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        guard case .showing(let presentation) = shown else {
            return XCTFail("only the usable element should be labeled, got \(shown)")
        }
        XCTAssertEqual(presentation.markers, [
            HintMarker(index: 0, text: "A", anchor: HintPoint(x: 10, y: 20)),
        ])
        XCTAssertEqual(rig.poster.effects, [])
    }

    func testTruncatedSnapshotStillLabelsOnlyTheElementsItHas() {
        let rig = makeRig(elements: [])
        rig.querier.query = .elements(ClickableSnapshot(elements: [oneBox()], truncated: true))
        _ = rig.controller.refreshClickables()
        let shown = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus))
        guard case .showing(let presentation) = shown else {
            return XCTFail("truncation is not a reason to hide the elements that were read")
        }
        XCTAssertEqual(presentation.markers.map(\.text), ["A"])
    }

    func testAppEntersReceivesAndCancelsHintsWithoutADecision() {
        let rig = makeRig(elements: tenBoxes())
        let hints: any HintOverlayControlling = rig.controller
        _ = hints.refreshClickables()
        _ = rig.interpreter.handleKeyDown(KeyEvent("F"), cache: safariFocus)
        XCTAssertEqual(rig.interpreter.mode, .hint(.command))
        guard case .showing(let presentation) = hints.enterHint(.command) else {
            return XCTFail("enterHint should show the cached labels")
        }
        XCTAssertEqual(presentation.markers.count, 10)
        XCTAssertEqual(presentation.policy, .hintLabels)
        XCTAssertEqual(rig.querier.reads, 1)
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.interpreter.mode, .hint(.command))

        let partial = hints.receiveHintKey(KeyEvent("a"))
        guard case .showing(let filtered) = partial else {
            return XCTFail("a prefix should stay inside the direct key method, got \(partial)")
        }
        XCTAssertEqual(filtered.markers.map(\.text), ["AA", "AS"])
        XCTAssertEqual(hints.cancelHint(), .cancelled(.dismissed))
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.presenter.hides, 1)
        XCTAssertEqual(rig.interpreter.mode, .normal)
    }

    func testDirectKeyCompletesACommandClick() {
        let rig = makeRig(elements: [oneBox()])
        let hints: any HintOverlayControlling = rig.controller
        _ = hints.refreshClickables()
        _ = rig.interpreter.handleKeyDown(KeyEvent("f"), cache: safariFocus)
        _ = hints.enterHint(.plain)
        let effect = plainClick(x: 14, y: 23)
        XCTAssertEqual(
            hints.receiveHintKey(KeyEvent("a"), keyCode: nil),
            .activated(
                HintActivation(index: 0, click: .plain, point: HintPoint(x: 14, y: 23), identifier: "2/0"),
                .performed([effect])
            )
        )
        XCTAssertEqual(rig.poster.effects, [effect])
        XCTAssertEqual(rig.interpreter.mode, .normal)
    }

    func testHintKeyWithoutASessionDoesNotClick() {
        let rig = makeRig(elements: [oneBox()])
        let result = rig.controller.consume(EventDecision(
            delivery: .swallow,
            mode: .hint(.plain),
            overlay: .hintKey(KeyEvent("a"))
        ))
        XCTAssertEqual(result, .inactive)
        XCTAssertEqual(rig.poster.effects, [])
        XCTAssertEqual(rig.presenter.hides, 0)
    }

    func testEventHookSourceDoesNotScanClickablesOrPresent() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimSystem/EventTap.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        for token in ["clickableElements(", "HintController", "HintSession", "orderFrontRegardless"] {
            XCTAssertFalse(text.contains(token), token)
        }
    }

    func testMenuProcessDoesNotStartTheOverlay() throws {
        let directory = repoRoot().appendingPathComponent("Sources/Supervim")
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty)
        XCTAssertFalse(files.contains("main.swift"))
        var text = ""
        for relative in files {
            text += try String(contentsOf: directory.appendingPathComponent(relative), encoding: .utf8)
        }
        for token in [
            "HintController",
            "HintOverlayControlling",
            "NonActivatingHintPanel",
            "enterHint(",
            "receiveHintKey(",
            "cancelHint(",
            "refreshClickables(",
            "CGEvent.tapCreate",
            "AXScanner",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
    }

    func testMacOSPanelSourceStaysTransparentAndNonActivating() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimSystem/HintOverlayWindow.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("#if canImport(AppKit)"))
        XCTAssertTrue(text.contains(".nonactivatingPanel"))
        XCTAssertTrue(text.contains("isOpaque = false"))
        XCTAssertTrue(text.contains("ignoresMouseEvents = true"))
        XCTAssertTrue(text.contains("backgroundColor = .clear"))
        XCTAssertTrue(text.contains("orderFrontRegardless"))
        XCTAssertFalse(text.contains("makeKeyAndOrderFront"))
        XCTAssertFalse(text.contains("NSApp.activate"))
        XCTAssertFalse(text.contains("orderFront("))
        XCTAssertFalse(text.contains("rightMouse"))
        for token in ["URLSession", "os_log", "NSLog", "print("] {
            XCTAssertFalse(text.contains(token), token)
        }
    }

    func testOverlaySourceDoesNotLogOrUseTheNetwork() throws {
        let overlay = repoRoot().appendingPathComponent("Sources/SupervimSystem/HintOverlay.swift")
        let session = repoRoot().appendingPathComponent("Sources/SupervimCore/HintSession.swift")
        for url in [overlay, session] {
            let text = try String(contentsOf: url, encoding: .utf8)
            for token in ["URLSession", "os_log", "Logger(", "NSLog", "print(", "rightMouse", "kCGMouseButtonRight"] {
                XCTAssertFalse(text.contains(token), "\(url.lastPathComponent) \(token)")
            }
        }
        let overlayText = try String(contentsOf: overlay, encoding: .utf8)
        XCTAssertTrue(overlayText.contains("canAccessibilityPress: false"))
    }
}

private let safariFocus = CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.Safari")
private let editableFocus = CachedFocus(editability: .editable, bundleIdentifier: "com.apple.Safari")
private let unknownFocus = CachedFocus(editability: .unknown, bundleIdentifier: "com.apple.Safari")
private let terminalFocus = CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.Terminal")

private struct HintRig {
    var querier: ScriptedClickables
    var presenter: CapturedOverlay
    var poster: ClickPoster
    var interpreter: EventInterpreter<ManualKeyClock>
    var controller: HintController
}

private func makeRig(elements: [ClickableElement]) -> HintRig {
    let querier = ScriptedClickables(query: .elements(ClickableSnapshot(elements: elements, truncated: false)))
    let presenter = CapturedOverlay()
    let poster = ClickPoster()
    let interpreter = EventInterpreter(clock: ManualKeyClock(), cache: safariFocus)
    let controller = HintController(
        querier: querier,
        presenter: presenter,
        actuator: ActionActuator(poster: poster),
        mode: interpreter
    )
    return HintRig(
        querier: querier,
        presenter: presenter,
        poster: poster,
        interpreter: interpreter,
        controller: controller
    )
}

private func oneBox() -> ClickableElement {
    ClickableElement(
        role: "AXButton",
        actions: ["AXPress"],
        frame: ElementFrame(x: 10, y: 20, width: 8, height: 6),
        path: [2, 0]
    )
}

private func tenBoxes() -> [ClickableElement] {
    (0..<10).map { index in
        ClickableElement(
            role: "AXLink",
            actions: ["AXPress"],
            frame: ElementFrame(x: Double(index) * 30, y: 0, width: 20, height: 10),
            path: [index]
        )
    }
}

private func repoRoot(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func plainClick(x: Double, y: Double) -> ActuatorEffect {
    .mouseClick(point: ActuatorPoint(x: x, y: y), button: .left, modifiers: [])
}

private final class ScriptedClickables: ClickableQuerying, @unchecked Sendable {
    var query: ClickableQuery
    private(set) var reads = 0

    init(query: ClickableQuery) {
        self.query = query
    }

    func clickableElements() -> ClickableQuery {
        reads += 1
        return query
    }
}

private final class CapturedOverlay: OverlayPresenting, @unchecked Sendable {
    private(set) var presentations: [OverlayPresentation] = []
    private(set) var hides = 0

    func present(_ presentation: OverlayPresentation) {
        presentations.append(presentation)
    }

    func hideOverlay() {
        hides += 1
    }
}

private final class ClickPoster: ActuatorPosting, @unchecked Sendable {
    private(set) var effects: [ActuatorEffect] = []

    func post(_ effect: ActuatorEffect) {
        effects.append(effect)
    }
}

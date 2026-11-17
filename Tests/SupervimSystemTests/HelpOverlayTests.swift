import XCTest
import SupervimCore
@testable import SupervimSystem

/// The help sheet is drawn on the same non-activating overlay as hint labels.
final class HelpOverlayTests: XCTestCase {
    func testShowPresentsTheCommandMapWithoutActivating() {
        let presenter = CapturedHelpPanel()
        let help = HelpController(presenter: presenter)
        guard case .shown(let presentation) = help.showHelp() else {
            return XCTFail("showHelp should present the page")
        }
        XCTAssertEqual(presentation.policy, .hintLabels)
        XCTAssertTrue(presentation.policy.isTransparent)
        XCTAssertTrue(presentation.policy.isNonActivating)
        XCTAssertTrue(presentation.policy.ignoresMouseEvents)
        XCTAssertEqual(presentation.page.entries.map(\.keys), CommandMap().bindings.map(\.keys))
        XCTAssertEqual(
            presentation.page.entries.first { $0.keys == "/" }?.line,
            "/  Find with the app shortcut  Command+F  differs from Vimium"
        )
        XCTAssertEqual(presenter.pages, [presentation])
        XCTAssertEqual(presenter.hides, 0)
        XCTAssertTrue(help.isHelpVisible)
        XCTAssertEqual(help.showHelp(), .unchanged)
        XCTAssertEqual(presenter.pages.count, 1)
    }

    func testClaimHelpTogglesAndConsumesTheQuestionMark() {
        let presenter = CapturedHelpPanel()
        let help = HelpController(presenter: presenter)
        let handler: any HelpCommandHandling = help
        XCTAssertTrue(handler.claimHelp())
        XCTAssertTrue(help.isHelpVisible)
        XCTAssertEqual(presenter.pages.count, 1)
        XCTAssertTrue(handler.claimHelp())
        XCTAssertFalse(help.isHelpVisible)
        XCTAssertEqual(presenter.hides, 1)
        XCTAssertEqual(help.hideHelp(), .unchanged)
        XCTAssertEqual(presenter.hides, 1)
    }

    func testAppCanToggleHelpWithoutAnEventHook() {
        let presenter = CapturedHelpPanel()
        let help: any HelpOverlayControlling = HelpController(presenter: presenter)
        guard case .shown(let presentation) = help.showHelp() else {
            return XCTFail("the app calls showHelp directly")
        }
        XCTAssertTrue(presentation.page.text.contains("Command+F"))
        XCTAssertTrue(help.isHelpVisible)
        XCTAssertEqual(help.toggleHelp(), .hidden)
        XCTAssertFalse(help.isHelpVisible)
        guard case .shown = help.toggleHelp() else {
            return XCTFail("toggling again should open help")
        }
        XCTAssertTrue(help.isHelpVisible)
    }

    func testQuestionMarkDecisionTogglesAndEscapeDismissesOnlyWhileVisible() {
        let presenter = CapturedHelpPanel()
        let help = HelpController(presenter: presenter)
        let opened = help.respond(to: KeyEvent("?"), decision: helpDecision())
        XCTAssertTrue(opened.consumesKey)
        guard case .shown = opened.result else {
            return XCTFail("a showHelp decision should open, got \(opened)")
        }
        let closed = help.respond(to: KeyEvent("?"), decision: helpDecision())
        XCTAssertEqual(closed.result, .hidden)
        XCTAssertTrue(closed.consumesKey)
        XCTAssertEqual(presenter.hides, 1)

        _ = help.respond(to: KeyEvent("?"), decision: helpDecision())
        let escaped = help.respond(
            to: KeyEvent(identity: .escape),
            decision: EventDecision(delivery: .passThrough, mode: .normal)
        )
        XCTAssertEqual(escaped.result, .hidden)
        XCTAssertTrue(escaped.consumesKey)
        XCTAssertFalse(help.isHelpVisible)

        let ignored = help.respond(
            to: KeyEvent(identity: .escape),
            decision: EventDecision(delivery: .passThrough, mode: .normal)
        )
        XCTAssertEqual(ignored.result, .unchanged)
        XCTAssertFalse(ignored.consumesKey)
        XCTAssertEqual(presenter.hides, 2)
    }

    func testClaimDismissalClosesOnEscapeAndLeavesOtherKeysAlone() {
        let presenter = CapturedHelpPanel()
        let help = HelpController(presenter: presenter)
        XCTAssertFalse(help.claimDismissal(KeyEvent(identity: .escape)))
        XCTAssertEqual(presenter.hides, 0)
        _ = help.claimHelp()
        XCTAssertFalse(help.claimDismissal(KeyEvent("j")))
        XCTAssertFalse(help.claimDismissal(KeyEvent(identity: .escape, modifiers: .command)))
        XCTAssertTrue(help.isHelpVisible)
        XCTAssertTrue(help.claimDismissal(KeyEvent(identity: .escape)))
        XCTAssertFalse(help.isHelpVisible)
        XCTAssertEqual(presenter.hides, 1)
        _ = help.showHelp()
        XCTAssertTrue(help.claimDismissal(KeyEvent("\u{1B}")))
        XCTAssertFalse(help.isHelpVisible)
    }

    func testRespondWithoutADecisionUsesTheSameChords() {
        let help = HelpController(presenter: CapturedHelpPanel())
        let opened = help.respond(to: KeyEvent("?", modifiers: .shift), decision: nil)
        XCTAssertTrue(opened.consumesKey)
        guard case .shown = opened.result else {
            return XCTFail("shift+? without a decision should open help")
        }
        let scrolled = help.respond(to: KeyEvent("j"), decision: nil)
        XCTAssertEqual(scrolled.result, .unchanged)
        XCTAssertFalse(scrolled.consumesKey)
        XCTAssertTrue(help.isHelpVisible)
        let commanded = help.respond(to: KeyEvent("?", modifiers: .command), decision: nil)
        XCTAssertEqual(commanded.result, .unchanged)
        XCTAssertFalse(commanded.consumesKey)
        let closed = help.respond(to: KeyEvent(identity: .escape), decision: nil)
        XCTAssertEqual(closed.result, .hidden)
        XCTAssertTrue(closed.consumesKey)
    }

    func testPassedThroughQuestionMarkAndHintKeysDoNotOpenHelp() {
        let help = HelpController(presenter: CapturedHelpPanel())
        let typed = help.respond(
            to: KeyEvent("?"),
            decision: EventDecision(delivery: .passThrough, mode: .insert)
        )
        XCTAssertEqual(typed.result, .unchanged)
        XCTAssertFalse(typed.consumesKey)
        let hintKey = KeyEvent("?")
        let hinted = help.respond(
            to: hintKey,
            decision: EventDecision(delivery: .swallow, mode: .hint(.plain), overlay: .hintKey(hintKey))
        )
        XCTAssertEqual(hinted.result, .unchanged)
        XCTAssertFalse(hinted.consumesKey)
        XCTAssertFalse(help.isHelpVisible)
    }

    func testBeginHintHidesHelpWithoutConsumingTheHintKey() {
        let presenter = CapturedHelpPanel()
        let help = HelpController(presenter: presenter)
        _ = help.showHelp()
        let started = help.respond(
            to: KeyEvent("f"),
            decision: EventDecision(
                delivery: .swallow,
                mode: .hint(.plain),
                actions: [.beginHint(.plain)],
                overlay: .beginHint(.plain)
            )
        )
        XCTAssertEqual(started.result, .hidden)
        XCTAssertFalse(started.consumesKey)
        XCTAssertFalse(help.isHelpVisible)
        XCTAssertEqual(presenter.hides, 1)

        let idle = help.respond(
            to: KeyEvent("f"),
            decision: EventDecision(
                delivery: .swallow,
                mode: .hint(.plain),
                overlay: .beginHint(.plain)
            )
        )
        XCTAssertEqual(idle.result, .unchanged)
        XCTAssertFalse(idle.consumesKey)
        XCTAssertEqual(presenter.hides, 1)
    }

    func testOtherCommandsLeaveTheOpenSheetInPlace() {
        let help = HelpController(presenter: CapturedHelpPanel())
        _ = help.showHelp()
        let scrolled = help.respond(
            to: KeyEvent("j"),
            decision: EventDecision(
                delivery: .swallow,
                mode: .normal,
                actions: [.scroll(direction: .down, amount: .points(60))]
            )
        )
        XCTAssertEqual(scrolled.result, .unchanged)
        XCTAssertFalse(scrolled.consumesKey)
        XCTAssertTrue(help.isHelpVisible)
    }

    func testControllerSourceDoesNotLogOrUseTheNetwork() throws {
        let url = helpSourcesRoot().appendingPathComponent("Sources/SupervimSystem/HelpOverlay.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        for token in [
            "URLSession",
            "os_log",
            "Logger(",
            "NSLog",
            "print(",
            "Actuator",
            "click(",
            "CGEvent",
            "AXUIElement",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
        XCTAssertTrue(text.contains("func claimHelp() -> Bool"))
        XCTAssertTrue(text.contains("HelpCommandHandling"))
    }

    func testPanelSourceDrawsHelpWithoutActivatingOrLogging() throws {
        let url = helpSourcesRoot().appendingPathComponent("Sources/SupervimSystem/HintOverlayWindow.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("#if canImport(AppKit)"))
        XCTAssertTrue(text.contains("func presentHelp"))
        XCTAssertTrue(text.contains("func hideHelp"))
        XCTAssertTrue(text.contains(".nonactivatingPanel"))
        XCTAssertTrue(text.contains("isOpaque = false"))
        XCTAssertTrue(text.contains("ignoresMouseEvents = true"))
        XCTAssertTrue(text.contains("orderFrontRegardless"))
        XCTAssertFalse(text.contains("makeKeyAndOrderFront"))
        XCTAssertFalse(text.contains("NSApp.activate"))
        XCTAssertFalse(text.contains("orderFront("))
        for token in ["URLSession", "os_log", "NSLog", "print("] {
            XCTAssertFalse(text.contains(token), token)
        }
    }

    func testSessionClaimsQuestionMarkAndEscapeClosesTheSheet() throws {
        let panel = SharedHelpPanel()
        let rig = try makeHelpSession(panel: panel)
        let opened = rig.session.handleKeyDown(KeyEvent("?"))
        XCTAssertEqual(opened.delivery, .swallow)
        XCTAssertEqual(opened.swallowReason, .overlay)
        XCTAssertEqual(opened.mode, .normal)
        XCTAssertTrue(rig.help.isHelpVisible)
        XCTAssertEqual(
            panel.helpPages.last?.page.entries.first { $0.keys == "/" }?.actionText,
            "Command+F"
        )
        XCTAssertTrue(panel.helpPages.last?.policy.isNonActivating == true)
        XCTAssertTrue(rig.poster.effects.isEmpty)

        let closed = rig.session.handleKeyDown(KeyEvent("?"))
        XCTAssertEqual(closed.delivery, .swallow)
        XCTAssertEqual(closed.swallowReason, .overlay)
        XCTAssertFalse(rig.help.isHelpVisible)
        XCTAssertEqual(panel.helpHides, 1)

        _ = rig.session.handleKeyDown(KeyEvent("?"))
        let escaped = rig.session.handleSystemRecord(
            SystemKeyRecord(kind: .keyDown, keyCode: 0x35, modifierFlags: 0, unicode: "\u{1B}")
        )
        XCTAssertEqual(escaped.delivery, .swallow)
        XCTAssertEqual(escaped.swallowReason, .overlay)
        XCTAssertFalse(rig.help.isHelpVisible)
        XCTAssertEqual(panel.helpHides, 2)

        let passed = rig.session.handleKeyDown(KeyEvent(identity: .escape))
        XCTAssertEqual(passed.delivery, .passThrough)
        XCTAssertNil(passed.swallowReason)
        XCTAssertEqual(panel.helpHides, 2)
    }

    func testStartingAHintHidesHelpOnTheSharedPanel() throws {
        let panel = SharedHelpPanel()
        let rig = try makeHelpSession(panel: panel, clickable: helpButton())
        _ = rig.session.handleKeyDown(KeyEvent("?"))
        XCTAssertTrue(rig.help.isHelpVisible)
        let hinted = rig.session.handleKeyDown(KeyEvent("f"))
        XCTAssertEqual(hinted.delivery, .swallow)
        XCTAssertEqual(hinted.mode, .hint(.plain))
        XCTAssertFalse(rig.help.isHelpVisible)
        XCTAssertEqual(panel.helpHides, 1)
        XCTAssertFalse(panel.markers.isEmpty)
        XCTAssertTrue(rig.poster.effects.isEmpty)
    }

    func testAppAssemblyClaimsHelpOnOneNonActivatingPanel() throws {
        let url = helpSourcesRoot().appendingPathComponent("Sources/SupervimSystem/MacHookAssembly.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(text.components(separatedBy: "NonActivatingHintPanel()").count - 1, 1)
        XCTAssertTrue(text.contains("let help = HelpController"))
        XCTAssertTrue(text.contains("presenter: panel"))
        XCTAssertTrue(text.contains("help: help"))
        let session = try String(
            contentsOf: helpSourcesRoot().appendingPathComponent("Sources/SupervimSystem/NormalCommandSession.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(session.components(separatedBy: "protocol HelpCommandHandling").count - 1, 1)
        XCTAssertTrue(session.contains("func dismissHelp(for event: KeyEvent) -> Bool"))
        XCTAssertTrue(session.contains("dismissHelp(for:"))
        XCTAssertTrue(session.contains("func yieldHelp()"))
        XCTAssertTrue(session.contains("yieldHelp()"))
        let helpSource = try String(
            contentsOf: helpSourcesRoot().appendingPathComponent("Sources/SupervimSystem/HelpOverlay.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(helpSource.contains("protocol HelpCommandHandling"))
    }

    func testMenuProcessDoesNotInstallHelp() throws {
        let directory = helpSourcesRoot().appendingPathComponent("Sources/Supervim")
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty)
        var text = ""
        for relative in files {
            text += try String(contentsOf: directory.appendingPathComponent(relative), encoding: .utf8)
        }
        for token in [
            "HelpController",
            "HelpOverlayControlling",
            "HelpCommandHandling",
            "claimHelp(",
            "presentHelp(",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
    }
}

private func helpDecision() -> EventDecision {
    EventDecision(
        delivery: .swallow,
        mode: .normal,
        actions: [.showHelp],
        overlay: .showHelp
    )
}

private func helpSourcesRoot(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private final class CapturedHelpPanel: HelpPresenting, @unchecked Sendable {
    private(set) var pages: [HelpPresentation] = []
    private(set) var hides = 0

    func presentHelp(_ presentation: HelpPresentation) {
        pages.append(presentation)
    }

    func hideHelp() {
        hides += 1
    }
}

private struct HelpRig {
    var session: NormalCommandSession
    var help: HelpController
    var poster: HelpClickPoster
}

private func makeHelpSession(panel: SharedHelpPanel, clickable: ClickableElement? = nil) throws -> HelpRig {
    let menu = try MenuBarController(
        repository: SettingsRepository(store: InMemorySettingsStore()),
        clock: ManualKeyClock(),
        frontmost: HelpFrontmost(identifier: "com.apple.Safari")
    )
    let pipeline = FocusPipeline(
        decider: menu.keyDecider,
        reader: HelpReader(),
        signals: HelpSignals()
    )
    pipeline.cache.replace(CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.Safari"))
    let poster = HelpClickPoster()
    let actuator = ActionActuator(poster: poster)
    let elements = clickable.map { [$0] } ?? []
    let hints = HintController(
        querier: pipeline.scanner,
        presenter: panel,
        actuator: actuator,
        mode: menu.keyDecider,
        cache: LockedClickableCache(
            query: .elements(ClickableSnapshot(elements: elements, truncated: false))
        )
    )
    let help = HelpController(presenter: panel)
    let session = NormalCommandSession(
        pipeline: pipeline,
        decider: menu.keyDecider,
        actuator: actuator,
        snapshots: LockedCommandSnapshot(snapshot: .unavailable),
        pointer: HelpPointer(),
        focuser: HelpFocuser(),
        hints: hints,
        help: help
    )
    return HelpRig(session: session, help: help, poster: poster)
}

private func helpButton() -> ClickableElement {
    ClickableElement(
        role: "AXButton",
        frame: ElementFrame(x: 10, y: 20, width: 8, height: 6),
        path: [0]
    )
}

private final class SharedHelpPanel: OverlayPresenting, HelpPresenting, @unchecked Sendable {
    private(set) var helpPages: [HelpPresentation] = []
    private(set) var helpHides = 0
    private(set) var markers: [[HintMarker]] = []

    func present(_ presentation: OverlayPresentation) {
        markers.append(presentation.markers)
    }

    func hideOverlay() {}

    func presentHelp(_ presentation: HelpPresentation) {
        helpPages.append(presentation)
    }

    func hideHelp() {
        helpHides += 1
    }
}

private final class HelpFrontmost: FrontmostBundleProviding, @unchecked Sendable {
    var identifier: String

    init(identifier: String) {
        self.identifier = identifier
    }

    func frontmostBundleIdentifier() -> String {
        identifier
    }
}

private final class HelpReader: AccessibilityReading, @unchecked Sendable {
    func readFocusedElement() -> AccessibilityRead<AccessibilityElement> {
        .value(AccessibilityElement(role: "AXWebArea"))
    }

    func readFrontmostBundleIdentifier() -> AccessibilityRead<String> {
        .value("com.apple.Safari")
    }

    func readFrontmostWindow(maxNodes: Int, maxDepth: Int) -> AccessibilityRead<AccessibilityElement> {
        _ = maxNodes
        _ = maxDepth
        return .unavailable
    }
}

private final class HelpSignals: FocusChangeSignaling, @unchecked Sendable {
    func start(_ handler: @escaping @Sendable () -> Void) {
        _ = handler
    }

    func stop() {}
}

private final class HelpClickPoster: ActuatorPosting, @unchecked Sendable {
    private(set) var effects: [ActuatorEffect] = []

    func post(_ effect: ActuatorEffect) {
        effects.append(effect)
    }
}

private final class HelpPointer: PointerReading, @unchecked Sendable {
    func currentPointer() -> ActuatorPoint? {
        nil
    }
}

private final class HelpFocuser: InputFocusing, @unchecked Sendable {
    func focusInput(path: [Int]) -> Bool {
        _ = path
        return false
    }
}

import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// Launch wiring: scanner first, then the hook, and only when both permissions exist.
/// The menu and the hook share one interpreter. f/F and ? pass through until a handler claims them.
final class SupervimRuntimeTests: XCTestCase {
    func testGrantedPermissionsStartFocusBeforeTheHook() {
        let log = StartLog()
        let runtime = SupervimRuntime(
            permissions: FixedHookPermission(accessibility: true, inputMonitoring: true),
            focus: log,
            hook: log
        )
        let started = runtime.start()
        XCTAssertEqual(log.events, ["focus", "hook"])
        XCTAssertTrue(started.monitoredFocus)
        XCTAssertTrue(started.installedHook)
    }

    func testAMissingPermissionStartsNothingAndDoesNotCrash() {
        let samples = [
            FixedHookPermission(accessibility: false, inputMonitoring: true),
            FixedHookPermission(accessibility: true, inputMonitoring: false),
            FixedHookPermission(accessibility: false, inputMonitoring: false),
        ]
        for sample in samples {
            let log = StartLog()
            let runtime = SupervimRuntime(permissions: sample, focus: log, hook: log)
            let started = runtime.start()
            XCTAssertEqual(log.events, [], "\(sample)")
            XCTAssertFalse(started.monitoredFocus)
            XCTAssertFalse(started.installedHook)
        }
    }

    func testHookInstallFailureLeavesTheProcessAlive() {
        let log = StartLog()
        log.failInstall = true
        let runtime = SupervimRuntime(
            permissions: FixedHookPermission(accessibility: true, inputMonitoring: true),
            focus: log,
            hook: log
        )
        let started = runtime.start()
        XCTAssertEqual(log.events, ["focus", "hook"])
        XCTAssertTrue(started.monitoredFocus)
        XCTAssertFalse(started.installedHook)
    }

    func testMenuPauseAndTheHookShareOneInterpreter() throws {
        let fixture = try makeShared()
        _ = try fixture.menu.perform(.pause)
        let passed = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(passed.delivery, .passThrough)
        XCTAssertEqual(passed.mode, .paused)
        XCTAssertEqual(fixture.menu.snapshot().statusTitle, "Paused")

        _ = try fixture.menu.perform(.resume)
        let chord = fixture.session.handleKeyDown(KeyEvent("v", modifiers: [.control, .option]))
        XCTAssertEqual(chord.delivery, .swallow)
        XCTAssertEqual(chord.swallowReason, .pause)
        try fixture.menu.noteExternalDecision()
        XCTAssertEqual(fixture.menu.snapshot().statusTitle, "Paused")
        XCTAssertEqual(try fixture.repository.load().isPaused, true)
    }

    func testAnExclusionAddedInTheMenuPassesHookKeys() throws {
        let fixture = try makeShared(bundle: "com.example.Notes")
        fixture.frontmost.identifier = "com.example.Notes"
        _ = try fixture.menu.addFrontmost()
        let passed = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(passed.delivery, .passThrough)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        XCTAssertEqual(fixture.menu.snapshot().statusTitle, "Normal")
    }

    func testScannerFocusUpdatesTheMenuMode() throws {
        let fixture = try makeShared()
        fixture.reader.reportEditable = true
        fixture.pipeline.scanner.start()
        XCTAssertEqual(fixture.menu.snapshot().statusTitle, "Insert")
        let typed = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(typed.delivery, .passThrough)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
    }

    func testUnclaimedHintAndHelpPassTheKey() throws {
        let fixture = try makeShared()
        let hint = fixture.session.handleKeyDown(KeyEvent("f"))
        XCTAssertEqual(hint.delivery, .passThrough)
        XCTAssertEqual(hint.mode, .normal)
        XCTAssertNil(hint.swallowReason)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        let scroll = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(scroll.delivery, .swallow)
        XCTAssertEqual(scroll.swallowReason, .actuator)
        XCTAssertFalse(fixture.poster.effects.isEmpty)

        let command = fixture.session.handleKeyDown(KeyEvent("F"))
        XCTAssertEqual(command.delivery, .passThrough)
        XCTAssertEqual(command.mode, .normal)

        let help = fixture.session.handleKeyDown(KeyEvent("?"))
        XCTAssertEqual(help.delivery, .passThrough)
        XCTAssertEqual(help.mode, .normal)
    }

    func testHintControllerShowsLabelsAndEndHintReturnsToNormal() throws {
        let presenter = MarkerSink()
        let fixture = try makeShared(presenter: presenter, clickable: sampleButton())
        let started = fixture.session.handleKeyDown(KeyEvent("f"))
        XCTAssertEqual(started.delivery, .swallow)
        XCTAssertEqual(started.mode, .hint(.plain))
        XCTAssertEqual(started.swallowReason, .overlay)
        XCTAssertEqual(fixture.menu.keyDecider.mode, .hint(.plain))
        XCTAssertEqual(presenter.shown.count, 1)
        XCTAssertEqual(presenter.hides, 0)
        XCTAssertTrue(fixture.poster.effects.isEmpty)
        let label = try XCTUnwrap(presenter.shown.last?.markers.first?.text).lowercased()
        let character = try XCTUnwrap(label.first)
        let activated = fixture.session.handleKeyDown(KeyEvent(character))
        XCTAssertEqual(activated.delivery, .swallow)
        XCTAssertEqual(activated.mode, .normal)
        XCTAssertEqual(fixture.menu.keyDecider.mode, .normal)
        XCTAssertEqual(fixture.menu.snapshot().statusTitle, "Normal")
        XCTAssertGreaterThanOrEqual(presenter.hides, 1)
        guard case .mouseClick(_, _, let modifiers) = fixture.poster.effects.last else {
            return XCTFail("expected a click, got \(fixture.poster.effects)")
        }
        XCTAssertFalse(modifiers.contains(.command))

        presenter.shown.removeAll()
        let command = fixture.session.handleKeyDown(KeyEvent("F"))
        XCTAssertEqual(command.mode, .hint(.command))
        let commandLabel = try XCTUnwrap(presenter.shown.last?.markers.first?.text).lowercased()
        let commandCharacter = try XCTUnwrap(commandLabel.first)
        let clicked = fixture.session.handleKeyDown(KeyEvent(commandCharacter))
        XCTAssertEqual(clicked.mode, .normal)
        guard case .mouseClick(_, _, let commandModifiers) = fixture.poster.effects.last else {
            return XCTFail("expected a command click, got \(fixture.poster.effects)")
        }
        XCTAssertTrue(commandModifiers.contains(.command))
    }

    func testEscapeCancelsHintThroughEndHint() throws {
        let presenter = MarkerSink()
        let fixture = try makeShared(presenter: presenter, clickable: sampleButton())
        _ = fixture.session.handleKeyDown(KeyEvent("f"))
        XCTAssertEqual(fixture.menu.keyDecider.mode, .hint(.plain))
        let cancelled = fixture.session.handleKeyDown(KeyEvent(identity: .escape))
        XCTAssertEqual(cancelled.delivery, .swallow)
        XCTAssertEqual(cancelled.mode, .normal)
        XCTAssertEqual(fixture.menu.keyDecider.mode, .normal)
        XCTAssertGreaterThanOrEqual(presenter.hides, 1)
        let scroll = fixture.session.handleKeyDown(KeyEvent("j"))
        XCTAssertEqual(scroll.delivery, .swallow)
        XCTAssertEqual(scroll.swallowReason, .actuator)
    }

    func testAClaimedHelpStaysSwallowed() throws {
        let help = HelpClaim()
        let fixture = try makeShared(help: help)
        let shown = fixture.session.handleKeyDown(KeyEvent("?"))
        XCTAssertEqual(shown.delivery, .swallow)
        XCTAssertEqual(shown.swallowReason, .overlay)
        XCTAssertEqual(shown.mode, .normal)
        XCTAssertEqual(help.claims, 1)
    }

    func testTapAdapterKeepsTheSessionDeliveryAndNotifies() throws {
        let fixture = try makeShared()
        let observer = CountObserver()
        let adapter = SessionTapAdapter(session: fixture.session, observer: observer)
        let outcome = adapter.handleSystemRecord(
            SystemKeyRecord(kind: .keyDown, keyCode: 0x26, modifierFlags: 0, unicode: "j")
        )
        XCTAssertEqual(outcome.delivery, .swallow)
        XCTAssertEqual(outcome.decision?.actions, [CommandMap().action(for: .scrollDown)])
        XCTAssertEqual(observer.count, 1)
        XCTAssertFalse(fixture.poster.effects.isEmpty)
    }

    func testMacHookAssemblyDoesNotPromptForPermission() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimSystem/MacHookAssembly.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("#if os(macOS)"))
        XCTAssertTrue(text.contains("AXIsProcessTrusted()"))
        XCTAssertTrue(text.contains("CGPreflightListenEventAccess()"))
        XCTAssertTrue(text.contains("scanner.start()"))
        XCTAssertTrue(text.contains("HintController"))
        // The window is walked on a queue of its own. The old assembly walked
        // it on the main run loop, which the key hook shared.
        XCTAssertTrue(text.contains("ContextRefresher("))
        XCTAssertTrue(text.contains("focusMayHaveChanged()"))
        XCTAssertTrue(text.contains("QueueWork(label: \"supervim.scan\""))
        XCTAssertTrue(text.contains("QueueWork(label: \"supervim.actuate\""))
        XCTAssertTrue(text.contains("scanning: scanWork"))
        XCTAssertTrue(text.contains("deferral: actWork"))
        XCTAssertTrue(text.contains("followUp: refresher"))
        XCTAssertTrue(text.contains("ModeChangeObserver("))
        for token in ["refreshClickables()", "readFrontmostWindow(", "firstEditableInput()", "DispatchQueue.main"] {
            XCTAssertFalse(text.contains(token), token)
        }
        XCTAssertTrue(text.contains("NonActivatingHintPanel"))
        XCTAssertTrue(text.contains("AXElementStore()"))
        XCTAssertTrue(text.contains("edgeBars: scrollElements"))
        XCTAssertTrue(text.contains("AXSystemReader(scrollElements: scrollElements, inputs: focuser)"))
        let runtime = try String(
            contentsOf: repoRoot().appendingPathComponent("Sources/SupervimSystem/SupervimRuntime.swift"),
            encoding: .utf8
        )
        let focus = runtime.range(of: "focus.start()")
        let install = runtime.range(of: "try hook.install()")
        XCTAssertNotNil(focus)
        XCTAssertNotNil(install)
        if let focus, let install {
            XCTAssertTrue(focus.lowerBound < install.lowerBound)
        }
        for token in [
            "CGRequestListenEventAccess",
            "AXIsProcessTrustedWithOptions",
            "kAXTrustedCheckOptionPrompt",
            "URLSession",
            "print(",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
        let app = try String(
            contentsOf: repoRoot().appendingPathComponent("Sources/Supervim/ExclusionSettingsPanel.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(app.contains("MenuHookAssembly"))
        XCTAssertTrue(app.contains(".start()"))
        for token in ["SMAppService", "ServiceManagement", "CGRequestListenEventAccess"] {
            XCTAssertFalse(app.contains(token), token)
        }
    }
}

private struct SharedFixture {
    var menu: MenuBarController<ManualKeyClock>
    var repository: SettingsRepository
    var frontmost: NamedFrontmost
    var reader: EditableReader
    var pipeline: FocusPipeline
    var poster: PostedEffects
    var session: NormalCommandSession
}

private func makeShared(
    bundle: String = "com.apple.Safari",
    presenter: MarkerSink? = nil,
    clickable: ClickableElement? = nil,
    help: HelpClaim? = nil
) throws -> SharedFixture {
    let store = InMemorySettingsStore()
    let repository = SettingsRepository(store: store)
    let frontmost = NamedFrontmost(identifier: bundle)
    let menu = try MenuBarController(
        repository: repository,
        clock: ManualKeyClock(),
        frontmost: frontmost
    )
    let reader = EditableReader(bundle: bundle)
    let pipeline = FocusPipeline(decider: menu.keyDecider, reader: reader, signals: QuietSignals())
    pipeline.cache.replace(CachedFocus(editability: .notEditable, bundleIdentifier: bundle))
    let poster = PostedEffects()
    let actuator = ActionActuator(poster: poster)
    let hints: HintController?
    if let presenter {
        let elements = clickable.map { [$0] } ?? []
        hints = HintController(
            querier: FixedClickables(elements: elements),
            presenter: presenter,
            actuator: actuator,
            mode: menu.keyDecider
        )
    } else {
        hints = nil
    }
    let session = NormalCommandSession(
        pipeline: pipeline,
        decider: menu.keyDecider,
        actuator: actuator,
        snapshots: LockedCommandSnapshot(
            snapshot: CommandSnapshot(
                scrollAreas: [sharedPage()],
                scrollCatalogReady: true,
                firstInput: .none,
                focusPoint: ActuatorPoint(x: 20, y: 30)
            )
        ),
        pointer: FixedPoint(point: ActuatorPoint(x: 20, y: 30)),
        focuser: NoFocus(),
        hints: hints,
        help: help
    )
    return SharedFixture(
        menu: menu,
        repository: repository,
        frontmost: frontmost,
        reader: reader,
        pipeline: pipeline,
        poster: poster,
        session: session
    )
}

private func sharedPage() -> ScrollArea {
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

private final class StartLog: FocusMonitoring, HookControlling, @unchecked Sendable {
    var events: [String] = []
    var failInstall = false

    func start() {
        events.append("focus")
    }

    func install() throws {
        events.append("hook")
        if failInstall {
            throw HookStartError.refused
        }
    }
}

private enum HookStartError: Error {
    case refused
}

private struct FixedHookPermission: HookPermissionReading, Equatable, Sendable {
    var accessibility: Bool
    var inputMonitoring: Bool

    func currentHookPermission() -> HookPermission {
        HookPermission(accessibility: accessibility, inputMonitoring: inputMonitoring)
    }
}

private final class NamedFrontmost: FrontmostBundleProviding, @unchecked Sendable {
    var identifier: String

    init(identifier: String) {
        self.identifier = identifier
    }

    func frontmostBundleIdentifier() -> String {
        identifier
    }
}

private final class EditableReader: AccessibilityReading, @unchecked Sendable {
    var bundle: String
    var reportEditable = false

    init(bundle: String) {
        self.bundle = bundle
    }

    func readFocusedElement() -> AccessibilityRead<AccessibilityElement> {
        if reportEditable {
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
        return .unavailable
    }
}

private final class QuietSignals: FocusChangeSignaling, @unchecked Sendable {
    func start(_ handler: @escaping @Sendable () -> Void) {
        _ = handler
    }

    func stop() {}
}

private final class PostedEffects: ActuatorPosting, @unchecked Sendable {
    private(set) var effects: [ActuatorEffect] = []

    func post(_ effect: ActuatorEffect) {
        effects.append(effect)
    }
}

private final class FixedPoint: PointerReading, @unchecked Sendable {
    var point: ActuatorPoint?

    init(point: ActuatorPoint?) {
        self.point = point
    }

    func currentPointer() -> ActuatorPoint? {
        point
    }
}

private final class NoFocus: InputFocusing, @unchecked Sendable {
    func focusInput(path: [Int]) -> Bool {
        _ = path
        return false
    }
}

private final class CountObserver: RuntimeObserving, @unchecked Sendable {
    private(set) var count = 0

    func runtimeDidHandle(_ decision: EventDecision?) {
        _ = decision
        count += 1
    }
}

private func sampleButton() -> ClickableElement {
    ClickableElement(
        role: "AXButton",
        frame: ElementFrame(x: 10, y: 20, width: 40, height: 16),
        path: [0]
    )
}

private final class MarkerSink: OverlayPresenting, @unchecked Sendable {
    var shown: [OverlayPresentation] = []
    private(set) var hides = 0

    func present(_ presentation: OverlayPresentation) {
        shown.append(presentation)
    }

    func hideOverlay() {
        hides += 1
    }
}

private final class HelpClaim: HelpCommandHandling, @unchecked Sendable {
    private(set) var claims = 0

    func claimHelp() -> Bool {
        claims += 1
        return true
    }

    func dismissHelp(for event: KeyEvent) -> Bool {
        _ = event
        return false
    }

    func yieldHelp() {}
}

private func repoRoot(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// The hint controller scans when `f` is pressed. This is that scan.
private final class FixedClickables: ClickableQuerying, @unchecked Sendable {
    private let elements: [ClickableElement]

    init(elements: [ClickableElement]) {
        self.elements = elements
    }

    func clickableElements() -> ClickableQuery {
        .elements(ClickableSnapshot(elements: elements, truncated: false))
    }
}

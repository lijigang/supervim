import Foundation
import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// `f` must not make the key hook wait for the accessibility scan.
final class HintAsyncTests: XCTestCase {
    func testEnterHintReturnsBeforeTheScanAndShowsLabelsAfterIt() {
        let rig = AsyncRig(elements: [button(0)])
        let begin = rig.interpreter.handleKeyDown(KeyEvent("f"), cache: focus)
        let result = rig.controller.consume(begin)
        XCTAssertEqual(result, .showing(OverlayPresentation(markers: [], policy: .hintLabels)))
        XCTAssertEqual(rig.querier.reads, 0, "the scan must not run inside the key hook")
        XCTAssertEqual(rig.presenter.shown.count, 0)
        XCTAssertEqual(rig.interpreter.mode, .hint(.plain))

        rig.work.runPending()
        XCTAssertEqual(rig.querier.reads, 1)
        XCTAssertEqual(rig.presenter.shown.last?.markers.map(\.text), ["F"])
        XCTAssertEqual(rig.interpreter.mode, .hint(.plain))
    }

    func testKeysTypedDuringTheScanAreReplayedInOrder() {
        let rig = AsyncRig(elements: (0..<30).map(button))
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: focus))
        rig.querier.onRead = { [controller = rig.controller] in
            // Arrives while the scan is still walking the window.
            _ = controller.receiveHintKey(KeyEvent("s"), keyCode: 0x01)
        }
        rig.work.runPending()
        XCTAssertEqual(rig.querier.reads, 1)
        XCTAssertEqual(rig.poster.effects.count, 1, "the buffered letter should complete a one-letter label")
        XCTAssertEqual(rig.interpreter.mode, .normal)
        XCTAssertEqual(rig.clicks.values.count, 1)
    }

    func testKeyBeforeTheScanStartsIsHeldAndNotDropped() {
        let rig = AsyncRig(elements: [button(0)])
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: focus))
        let early = rig.controller.receiveHintKey(KeyEvent("f"), keyCode: 0x03)
        XCTAssertEqual(early, .showing(OverlayPresentation(markers: [], policy: .hintLabels)))
        XCTAssertEqual(rig.poster.effects, [])
        rig.work.runPending()
        XCTAssertEqual(rig.poster.effects, [
            .mouseClick(point: ActuatorPoint(x: 10, y: 5), button: .left, modifiers: []),
        ])
        XCTAssertEqual(rig.interpreter.mode, .normal)
    }

    func testCancelDuringTheScanThrowsTheScanAway() {
        let rig = AsyncRig(elements: [button(0)])
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: focus))
        XCTAssertEqual(rig.controller.cancelHint(), .cancelled(.dismissed))
        XCTAssertEqual(rig.interpreter.mode, .normal)
        rig.work.runPending()
        XCTAssertEqual(rig.querier.reads, 0, "a cancelled hint should not even start its scan")
        XCTAssertEqual(rig.presenter.shown.count, 0)
        XCTAssertEqual(rig.interpreter.mode, .normal)
    }

    func testCancelWhileTheScanIsWalkingShowsNothing() {
        let rig = AsyncRig(elements: [button(0)])
        _ = rig.controller.consume(rig.interpreter.handleKeyDown(KeyEvent("f"), cache: focus))
        rig.querier.onRead = { [controller = rig.controller] in
            _ = controller.cancelHint()
        }
        rig.work.runPending()
        XCTAssertEqual(rig.querier.reads, 1)
        XCTAssertEqual(rig.presenter.shown.count, 0)
        XCTAssertEqual(rig.interpreter.mode, .normal)
    }

    func testASecondHintSupersedesTheScanInFlight() {
        let rig = AsyncRig(elements: [button(0)])
        _ = rig.controller.enterHint(.plain)
        _ = rig.controller.enterHint(.command)
        rig.work.runPending()
        XCTAssertEqual(rig.querier.reads, 1, "only the newest request scans")
        XCTAssertEqual(rig.presenter.shown.count, 1)
        _ = rig.controller.receiveHintKey(KeyEvent("f"), keyCode: 0x03)
        XCTAssertEqual(rig.poster.effects, [
            .mouseClick(point: ActuatorPoint(x: 10, y: 5), button: .left, modifiers: .command),
        ])
    }

    func testVisionStartsBeforeTheAccessibilityScanForListedApps() {
        let vision = OrderedVision()
        let rig = AsyncRig(elements: [button(0)], vision: vision, bundle: "com.tencent.xinWeChat")
        vision.querier = rig.querier
        vision.result = .targets([HintTarget(frame: HintRect(x: 300, y: 300, width: 40, height: 20))])
        _ = rig.controller.enterHint(.plain)
        rig.work.runPending()
        XCTAssertEqual(vision.readsWhenAsked, [0], "the screenshot should be under way while the tree is walked")
        XCTAssertEqual(vision.hitCounts, [0])
        XCTAssertEqual(rig.presenter.shown.last?.markers.count, 1)
    }

    func testVisionForOtherAppsWaitsForAnEmptyAccessibilityScan() {
        let vision = OrderedVision()
        let rig = AsyncRig(elements: [], vision: vision, bundle: "com.example.Canvas")
        vision.querier = rig.querier
        vision.result = .targets([HintTarget(frame: HintRect(x: 300, y: 300, width: 40, height: 20))])
        _ = rig.controller.enterHint(.plain)
        rig.work.runPending()
        XCTAssertEqual(vision.readsWhenAsked, [1])
        XCTAssertEqual(vision.hitCounts, [0])
        XCTAssertEqual(rig.presenter.shown.last?.markers.count, 1)
    }

    func testLateVisionResultShowsLabelsAndReplaysKeys() {
        let vision = OrderedVision()
        vision.holds = true
        let rig = AsyncRig(elements: [], vision: vision, bundle: "com.tencent.xinWeChat")
        vision.result = .targets([HintTarget(frame: HintRect(x: 300, y: 300, width: 40, height: 20))])
        _ = rig.controller.enterHint(.plain)
        rig.work.runPending()
        XCTAssertEqual(rig.presenter.shown.count, 0)
        _ = rig.controller.receiveHintKey(KeyEvent("f"), keyCode: 0x03)
        XCTAssertEqual(rig.poster.effects, [])
        vision.release()
        XCTAssertEqual(rig.poster.effects, [
            .mouseClick(point: ActuatorPoint(x: 320, y: 310), button: .left, modifiers: []),
        ])
        XCTAssertEqual(rig.interpreter.mode, .normal)
    }

    func testAVisionResultForACancelledHintIsIgnored() {
        let vision = OrderedVision()
        vision.holds = true
        let rig = AsyncRig(elements: [], vision: vision, bundle: "com.tencent.xinWeChat")
        vision.result = .targets([HintTarget(frame: HintRect(x: 300, y: 300, width: 40, height: 20))])
        _ = rig.controller.enterHint(.plain)
        rig.work.runPending()
        _ = rig.controller.cancelHint()
        vision.release()
        XCTAssertEqual(rig.presenter.shown.count, 0)
    }

    func testScanAndVisibleTimingsAreLogged() {
        let rig = AsyncRig(elements: [button(0)])
        let lines = ModeTrace.capture {
            _ = rig.controller.enterHint(.plain)
            rig.work.runPending()
        }
        XCTAssertTrue(lines.contains { $0.hasPrefix("timing stage=hint-scan ms=") && $0.contains("targets=1") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("timing stage=hint-visible ms=") && $0.contains("labels=1") }, "\(lines)")
    }

    func testActivationHandlerRunsAfterAClick() {
        let rig = AsyncRig(elements: [button(0)])
        rig.controller.onActivation { [clicks = rig.clicks] in
            clicks.add("handler")
        }
        _ = rig.controller.enterHint(.plain)
        rig.work.runPending()
        _ = rig.controller.receiveHintKey(KeyEvent("f"), keyCode: 0x03)
        XCTAssertEqual(rig.clicks.values, ["activated", "handler"])
    }

    private let focus = CachedFocus(editability: .notEditable, bundleIdentifier: "com.apple.Safari")

    private func button(_ index: Int) -> ClickableElement {
        ClickableElement(
            role: "AXButton",
            frame: ElementFrame(x: Double(index % 10) * 40, y: Double(index / 10) * 30, width: 20, height: 10),
            path: [index]
        )
    }
}

private final class AsyncRig {
    let querier: SlowClickables
    let presenter: ShownOverlay
    let poster: AsyncPoster
    let interpreter: EventInterpreter<ManualKeyClock>
    let controller: HintController
    let work = ManualWork()
    let clicks = Recorder()

    init(elements: [ClickableElement], vision: (any VisionHintServing)? = nil, bundle: String = "com.apple.Safari") {
        querier = SlowClickables(elements: elements)
        presenter = ShownOverlay()
        poster = AsyncPoster(log: clicks)
        interpreter = EventInterpreter(
            clock: ManualKeyClock(),
            cache: CachedFocus(editability: .notEditable, bundleIdentifier: bundle)
        )
        controller = HintController(
            querier: querier,
            presenter: presenter,
            actuator: ActionActuator(poster: poster),
            mode: interpreter,
            vision: vision,
            frontBundle: { bundle },
            scanning: work,
            visionBundles: { ["com.tencent.xinWeChat"] }
        )
    }
}

private final class SlowClickables: ClickableQuerying, @unchecked Sendable {
    private let elements: [ClickableElement]
    private let lock = NSLock()
    private var count = 0
    var onRead: (@Sendable () -> Void)?

    init(elements: [ClickableElement]) {
        self.elements = elements
    }

    var reads: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func clickableElements() -> ClickableQuery {
        lock.lock()
        count += 1
        lock.unlock()
        onRead?()
        return .elements(ClickableSnapshot(elements: elements, truncated: false))
    }
}

private final class ShownOverlay: OverlayPresenting, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [OverlayPresentation] = []

    var shown: [OverlayPresentation] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func present(_ presentation: OverlayPresentation) {
        lock.lock()
        stored.append(presentation)
        lock.unlock()
    }

    func hideOverlay() {}
}

private final class AsyncPoster: ActuatorPosting, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ActuatorEffect] = []
    private let log: Recorder

    init(log: Recorder) {
        self.log = log
    }

    var effects: [ActuatorEffect] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func post(_ effect: ActuatorEffect) {
        lock.lock()
        stored.append(effect)
        lock.unlock()
        log.add("activated")
    }
}

private final class OrderedVision: VisionHintServing, @unchecked Sendable {
    var result = VisionHintResult.empty
    var holds = false
    var querier: SlowClickables?
    private(set) var readsWhenAsked: [Int] = []
    private(set) var hitCounts: [Int] = []
    private var held: (@Sendable (VisionHintResult) -> Void)?

    func prepareHints(
        bundleIdentifier: String,
        axHitCount: Int,
        completion: @escaping @Sendable (VisionHintResult) -> Void
    ) {
        _ = bundleIdentifier
        readsWhenAsked.append(querier?.reads ?? -1)
        hitCounts.append(axHitCount)
        if holds {
            held = completion
        } else {
            completion(result)
        }
    }

    func release() {
        held?(result)
        held = nil
    }
}

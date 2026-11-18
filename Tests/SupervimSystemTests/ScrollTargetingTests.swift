import Foundation
import XCTest
@testable import SupervimCore
@testable import SupervimSystem

final class ScrollTargetingTests: XCTestCase {
    private let window = ActuatorRect(x: 0, y: 0, width: 1_000, height: 800)

    func testPointerOnTheToolbarMovesToThePageThatFillsTheWindow() {
        let page = area("page", ActuatorRect(x: 0, y: 80, width: 1_000, height: 720), role: "AXWebArea")
        let context = ActuationContext(
            bundleIdentifier: "com.google.Chrome",
            pointer: ActuatorPoint(x: 300, y: 20),
            windowFrame: window,
            structuralAreas: [page]
        )
        let aim = ScrollTargeting.aim(context: context, direction: .down)
        XCTAssertEqual(aim?.targetID, "page")
        XCTAssertEqual(aim?.source, .area)
        XCTAssertEqual(aim?.movesPointer, true)
        XCTAssertEqual(aim?.location, ActuatorPoint(x: 500, y: 440))
        XCTAssertEqual(
            ScrollTargeting.effects(context: context, direction: .down, amount: .fractionOfPage(numerator: 1, denominator: 2)),
            [
                .pointerMove(to: ActuatorPoint(x: 500, y: 440)),
                .pointerScroll(
                    targetID: "page",
                    direction: .down,
                    amount: .fractionOfPage(numerator: 1, denominator: 2),
                    location: ActuatorPoint(x: 500, y: 440),
                    horizontal: 0,
                    vertical: -360
                ),
            ]
        )
    }

    func testASmallAreaElsewhereDoesNotPullThePointerAway() {
        let list = area("list", ActuatorRect(x: 0, y: 0, width: 250, height: 800))
        let context = ActuationContext(
            bundleIdentifier: "com.tencent.xinWeChat",
            pointer: ActuatorPoint(x: 700, y: 300),
            scrollAreas: [list],
            windowFrame: window
        )
        let aim = ScrollTargeting.aim(context: context, direction: .up)
        XCTAssertEqual(aim?.source, .pointer)
        XCTAssertEqual(aim?.movesPointer, false)
        XCTAssertEqual(aim?.location, ActuatorPoint(x: 700, y: 300))
        XCTAssertEqual(aim?.targetID, "window")
    }

    func testTheDeepestScrollableAreaUnderThePointerNamesTheTarget() {
        let outer = area("outer", ActuatorRect(x: 0, y: 0, width: 1_000, height: 800), depth: 1)
        let inner = area("inner", ActuatorRect(x: 100, y: 100, width: 300, height: 300), depth: 4)
        var fits = area("fits", ActuatorRect(x: 120, y: 120, width: 100, height: 100), depth: 6)
        fits.travelUp = 0
        fits.travelDown = 0
        let context = ActuationContext(
            bundleIdentifier: "com.apple.Safari",
            pointer: ActuatorPoint(x: 150, y: 150),
            scrollAreas: [outer, inner, fits],
            windowFrame: window
        )
        let aim = ScrollTargeting.aim(context: context, direction: .down)
        XCTAssertEqual(aim?.targetID, "inner")
        XCTAssertEqual(aim?.source, .underPointer)
        XCTAssertEqual(aim?.movesPointer, false)
    }

    func testHorizontalScrollIgnoresAnAreaThatOnlyScrollsVertically() {
        let page = area("page", ActuatorRect(x: 0, y: 0, width: 1_000, height: 800))
        let context = ActuationContext(
            bundleIdentifier: "com.apple.Safari",
            pointer: ActuatorPoint(x: 150, y: 150),
            scrollAreas: [page],
            windowFrame: window
        )
        XCTAssertEqual(ScrollTargeting.aim(context: context, direction: .left)?.targetID, "window")
        XCTAssertEqual(ScrollTargeting.aim(context: context, direction: .down)?.targetID, "page")
    }

    func testHeldComposerNeverTakesTheWheel() {
        let composer = ActuatorRect(x: 0, y: 700, width: 1_000, height: 100)
        let base = ActuationContext(
            bundleIdentifier: "com.tencent.xinWeChat",
            pointer: ActuatorPoint(x: 500, y: 750),
            windowFrame: window,
            composerFrame: composer
        )
        let centered = ScrollTargeting.aim(context: base, direction: .up)
        XCTAssertEqual(centered?.source, .windowCenter)
        XCTAssertEqual(centered?.location, ActuatorPoint(x: 500, y: 400))
        XCTAssertEqual(centered?.movesPointer, true)

        var noWindow = base
        noWindow.windowFrame = nil
        XCTAssertNil(ScrollTargeting.aim(context: noWindow, direction: .up))

        var covered = base
        covered.composerFrame = window
        XCTAssertNil(ScrollTargeting.aim(context: covered, direction: .up))

        var elsewhere = base
        elsewhere.pointer = ActuatorPoint(x: 500, y: 200)
        XCTAssertEqual(ScrollTargeting.aim(context: elsewhere, direction: .up)?.source, .pointer)
    }

    func testAnEdgeScrollThatSetsTheBarLeavesThePointerAlone() {
        let page = area("page", ActuatorRect(x: 0, y: 80, width: 1_000, height: 720))
        let context = ActuationContext(
            bundleIdentifier: "com.apple.Notes",
            pointer: ActuatorPoint(x: -500, y: 20),
            scrollAreas: [page],
            windowFrame: window
        )
        let poster = TargetPoster()
        let bars = SettableBars()
        let actuator = ActionActuator(poster: poster, edgeBars: bars)
        let outcome = actuator.perform(.scroll(direction: .down, amount: .edge), context: context)
        XCTAssertEqual(outcome, .performed([.scrollBarEdge(targetID: "page", direction: .down, value: 1)]))
        XCTAssertEqual(poster.effects, [.scrollBarEdge(targetID: "page", direction: .down, value: 1)])
    }

    func testDeferredActuationPlansNowAndPostsLater() {
        let page = area("page", ActuatorRect(x: 0, y: 80, width: 1_000, height: 720))
        let context = ActuationContext(
            bundleIdentifier: "com.apple.Notes",
            pointer: ActuatorPoint(x: 500, y: 300),
            scrollAreas: [page],
            windowFrame: window
        )
        let poster = TargetPoster()
        let bars = SettableBars()
        let later = ManualWork()
        let actuator = ActionActuator(poster: poster, edgeBars: bars, deferral: later)

        let scrolled = actuator.perform(.scroll(direction: .down, amount: .points(60)), context: context)
        guard case .performed = scrolled else {
            return XCTFail("expected a planned scroll, got \(scrolled)")
        }
        let edge = actuator.perform(.scroll(direction: .down, amount: .edge), context: context)
        guard case .performed = edge else {
            return XCTFail("expected a planned edge scroll, got \(edge)")
        }
        let clicked = actuator.click(ClickRequest(
            point: ActuatorPoint(x: 5, y: 5),
            kind: .plain,
            elementID: "0/1",
            canAccessibilityPress: true
        ))
        XCTAssertEqual(clicked, .performed([.accessibilityPress(elementID: "0/1", fallback: ActuatorPoint(x: 5, y: 5))]))
        XCTAssertEqual(poster.effects, [])
        XCTAssertEqual(bars.reads, 0)

        later.runPending()
        XCTAssertEqual(poster.effects.count, 3)
        XCTAssertEqual(poster.effects[1], .scrollBarEdge(targetID: "page", direction: .down, value: 1))
        XCTAssertGreaterThan(bars.reads, 0)
        XCTAssertEqual(actuator.perform(.showHelp, context: context), .notActuatorWork)
        XCTAssertEqual(
            actuator.perform(.scroll(direction: .down, amount: .points(60)), context: ActuationContext(bundleIdentifier: "x")),
            .passedThrough
        )
    }

    func testTargetLogLineNamesTheSourceAndTheMove() {
        let aim = ScrollAim(
            targetID: "0/2",
            role: "AXWebArea",
            location: ActuatorPoint(x: 10, y: 20),
            movesPointer: true,
            source: .area,
            page: (100, 200)
        )
        XCTAssertEqual(
            ScrollTargeting.logLine(aim, direction: .down),
            "scroll-target id=0/2 direction=down source=area move=1 x=10.0 y=20.0"
        )
    }

    private func area(_ identifier: String, _ frame: ActuatorRect, depth: Int = 1, role: String = "AXScrollArea") -> ScrollArea {
        ScrollArea(
            identifier: identifier,
            frame: frame,
            depth: depth,
            containsPointer: false,
            isFocusContainer: false,
            visibleWidth: frame.width,
            visibleHeight: frame.height,
            travelLeft: 0,
            travelDown: 1,
            travelUp: 1,
            travelRight: 0,
            contentWidth: nil,
            contentHeight: nil,
            role: role
        )
    }
}

private final class TargetPoster: ActuatorPosting, @unchecked Sendable {
    private let lock = NSLock()
    private var posted: [ActuatorEffect] = []

    func post(_ effect: ActuatorEffect) {
        lock.lock()
        posted.append(effect)
        lock.unlock()
    }

    var effects: [ActuatorEffect] {
        lock.lock()
        defer { lock.unlock() }
        return posted
    }
}

private final class SettableBars: EdgeScrollBars, @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.25
    private var count = 0

    var reads: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func bar(elementID: String, direction: ScrollDirection) -> EdgeBar? {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return EdgeBar(value: value, minimum: 0, maximum: 1, settable: true)
    }

    func writeBar(elementID: String, direction: ScrollDirection, value: Double) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
        return value
    }
}

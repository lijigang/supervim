import Foundation
import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// Each test is a way `j` / `k` did nothing in 0.1.4. They use only the
/// 0.1.4 API, so the same file fails against that code.
final class ScrollRegressionTests: XCTestCase {
    func testScrollingUpWorksWhenTheSnapshotWasTakenAtTheTop() {
        // The catalog is read when focus changes. A page that was at the top
        // then has travelUp 0. After `j j j` the page is no longer at the
        // top, and the snapshot still says it is.
        let poster = RegressionPoster()
        let actuator = ActionActuator(poster: poster)
        let page = area("0", x: 0, y: 100, width: 800, height: 500, up: 0, down: 1)
        let outcome = actuator.perform(
            .scroll(direction: .up, amount: .points(60)),
            context: ActuationContext(
                bundleIdentifier: "com.apple.Safari",
                pointer: ActuatorPoint(x: 400, y: 300),
                scrollAreas: [page],
                windowFrame: ActuatorRect(x: 0, y: 0, width: 800, height: 600)
            )
        )
        XCTAssertNotEqual(outcome, .passedThrough)
        XCTAssertEqual(poster.wheels.map(\.vertical), [60])
    }

    func testPointerOnAnotherDisplayStillScrollsTheFrontWindow() {
        let poster = RegressionPoster()
        let actuator = ActionActuator(poster: poster)
        var page = area("0", x: 0, y: 100, width: 800, height: 500, up: 1, down: 1)
        page.containsPointer = false
        page.isFocusContainer = true
        let outcome = actuator.perform(
            .scroll(direction: .down, amount: .points(60)),
            context: ActuationContext(
                bundleIdentifier: "com.apple.Safari",
                pointer: ActuatorPoint(x: -1_200, y: 400),
                scrollAreas: [page],
                windowFrame: ActuatorRect(x: 0, y: 0, width: 800, height: 600)
            )
        )
        XCTAssertNotEqual(outcome, .passedThrough)
        XCTAssertEqual(poster.wheels.map(\.vertical), [-60])
        XCTAssertEqual(poster.wheels.first?.location, ActuatorPoint(x: 400, y: 350))
    }

    func testAScrollAreaSomewhereElseDoesNotStopTheWheelUnderThePointer() {
        // WeChat exposes the chat list and not the history. The pointer is
        // over the history: the wheel belongs there.
        let poster = RegressionPoster()
        let actuator = ActionActuator(poster: poster)
        var list = area("0", x: 0, y: 0, width: 200, height: 600, up: 1, down: 1)
        list.containsPointer = false
        let outcome = actuator.perform(
            .scroll(direction: .down, amount: .points(60)),
            context: ActuationContext(
                bundleIdentifier: "com.tencent.xinWeChat",
                pointer: ActuatorPoint(x: 600, y: 300),
                scrollAreas: [list],
                windowFrame: ActuatorRect(x: 0, y: 0, width: 900, height: 600)
            )
        )
        XCTAssertNotEqual(outcome, .passedThrough)
        XCTAssertEqual(poster.wheels.first?.location, ActuatorPoint(x: 600, y: 300))
    }

    private func area(
        _ identifier: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        up: Double,
        down: Double
    ) -> ScrollArea {
        ScrollArea(
            identifier: identifier,
            frame: ActuatorRect(x: x, y: y, width: width, height: height),
            depth: 1,
            containsPointer: true,
            isFocusContainer: false,
            visibleWidth: width,
            visibleHeight: height,
            travelLeft: 0,
            travelDown: down,
            travelUp: up,
            travelRight: 0,
            contentWidth: nil,
            contentHeight: nil,
            role: "AXScrollArea"
        )
    }
}

private struct RegressionWheel: Equatable {
    var location: ActuatorPoint
    var vertical: Int
}

private final class RegressionPoster: ActuatorPosting, @unchecked Sendable {
    private let lock = NSLock()
    private var posted: [ActuatorEffect] = []

    func post(_ effect: ActuatorEffect) {
        lock.lock()
        posted.append(effect)
        lock.unlock()
    }

    var wheels: [RegressionWheel] {
        lock.lock()
        defer { lock.unlock() }
        return posted.compactMap { effect in
            if case .pointerScroll(_, _, _, let location, _, let vertical) = effect {
                return RegressionWheel(location: location, vertical: vertical)
            }
            return nil
        }
    }
}

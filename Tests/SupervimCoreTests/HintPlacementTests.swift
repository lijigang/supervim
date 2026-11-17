import XCTest
@testable import SupervimCore

/// Primary display on the right. The left display has a negative x and a
/// different scale. Clicks use the clipped accessibility center.
final class HintPlacementTests: XCTestCase {
    private let screens = [
        DisplayFrame(x: 0, y: 0, width: 1920, height: 1080, backingScale: 2),
        DisplayFrame(x: -1920, y: 0, width: 1920, height: 1080, backingScale: 1),
    ]

    func testClickIsTheCenterOfTheClippedFrameTheLabelSitsOn() {
        let element = HintRect(x: -400, y: 100, width: 200, height: 40)
        let window = HintRect(x: -500, y: 80, width: 180, height: 50)
        guard let placed = HintGeometry.place(
            element: element,
            window: window,
            badgeWidth: 18,
            badgeHeight: 16,
            screens: screens
        ) else {
            return XCTFail("expected a placement")
        }
        XCTAssertEqual(placed.visible, HintRect(x: -400, y: 100, width: 80, height: 30))
        XCTAssertEqual(placed.click, placed.visible.center)
        XCTAssertEqual(placed.click, HintPoint(x: -360, y: 115))
        XCTAssertEqual(placed.screenIndex, 1)
        XCTAssertEqual(placed.label.x, placed.visible.x)
        let badgeTop = screens[0].height - (placed.label.y + placed.label.height)
        XCTAssertEqual(badgeTop, placed.visible.y, accuracy: 0.001)
        let badgeCenterY = screens[0].height - (placed.label.y + placed.label.height / 2)
        XCTAssertGreaterThanOrEqual(badgeCenterY, placed.visible.y)
        XCTAssertLessThanOrEqual(badgeCenterY, placed.visible.y + placed.visible.height)
    }

    func testScaleDoesNotMoveTheClickAndPanelsStayOnTheirOwnScreens() {
        let left = HintRect(x: -400, y: 100, width: 80, height: 30)
        let right = HintRect(x: 100, y: 40, width: 50, height: 20)
        let unit = screens.map {
            DisplayFrame(x: $0.x, y: $0.y, width: $0.width, height: $0.height, backingScale: 1)
        }
        let retina = HintGeometry.place(
            element: left, window: nil, badgeWidth: 18, badgeHeight: 16, screens: screens
        )
        let points = HintGeometry.place(
            element: left, window: nil, badgeWidth: 18, badgeHeight: 16, screens: unit
        )
        XCTAssertEqual(retina?.click, points?.click)
        XCTAssertEqual(retina?.label, points?.label)
        guard let leftLabel = retina?.label,
              let rightPlaced = HintGeometry.place(
                element: right, window: nil, badgeWidth: 10, badgeHeight: 10, screens: screens
              )
        else {
            return XCTFail("expected both labels")
        }
        let panels = HintGeometry.panels(labels: [leftLabel, rightPlaced.label], screens: screens)
        XCTAssertEqual(panels.map(\.screenIndex), [0, 1])
        XCTAssertEqual(panels.map(\.backingScale), [2, 1])
        for panel in panels {
            for item in panel.items {
                let globalX = item.local.x + panel.frame.x
                let globalY = item.local.y + panel.frame.y
                let source = item.sourceIndex == 0 ? leftLabel : rightPlaced.label
                XCTAssertEqual(globalX, source.x, accuracy: 0.001)
                XCTAssertEqual(globalY, source.y, accuracy: 0.001)
            }
        }
    }

    func testOffscreenZeroAndHugeFramesAreDroppedOrClipped() {
        let window = HintRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertNil(HintGeometry.visibleElement(HintRect(x: 0, y: 0, width: 0, height: 10), window: window))
        XCTAssertNil(HintGeometry.visibleElement(HintRect(x: 900, y: 10, width: 40, height: 20), window: window))
        let huge = HintGeometry.visibleElement(
            HintRect(x: -100, y: -50, width: 2000, height: 2000),
            window: window
        )
        XCTAssertEqual(huge, window)
        let viewport = HintRect(x: 0, y: 80, width: 800, height: 400)
        let scrolled = HintGeometry.visibleElement(
            HintRect(x: 20, y: 900, width: 100, height: 2000),
            window: window,
            viewports: [viewport]
        )
        XCTAssertNil(scrolled)
        let clipped = HintGeometry.visibleElement(
            HintRect(x: 20, y: 60, width: 100, height: 40),
            window: window,
            viewports: [viewport]
        )
        XCTAssertEqual(clipped, HintRect(x: 20, y: 80, width: 100, height: 20))
        let sliver = HintGeometry.visibleElement(
            HintRect(x: 0, y: 470, width: 800, height: 4000),
            window: window,
            viewports: [viewport]
        )
        XCTAssertNil(sliver)
    }

    func testOverlappingLabelsAreNudgedApart() {
        let nudged = HintGeometry.nudge([
            HintRect(x: 0, y: 0, width: 18, height: 16),
            HintRect(x: 10, y: 0, width: 18, height: 16),
        ])
        XCTAssertEqual(nudged[0], HintRect(x: 0, y: 0, width: 18, height: 16))
        XCTAssertGreaterThanOrEqual(nudged[1].x, nudged[0].x + nudged[0].width)
        XCTAssertNil(intersection(nudged[0], nudged[1]))
    }

    private func intersection(_ lhs: HintRect, _ rhs: HintRect) -> HintRect? {
        let x = max(lhs.x, rhs.x)
        let y = max(lhs.y, rhs.y)
        let maxX = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let maxY = min(lhs.y + lhs.height, rhs.y + rhs.height)
        guard maxX > x, maxY > y else {
            return nil
        }
        return HintRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }
}

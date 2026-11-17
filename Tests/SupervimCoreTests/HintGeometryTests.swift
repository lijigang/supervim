import XCTest
@testable import SupervimCore

/// Label placement and click points for multi-display layouts.
/// Accessibility frames use the primary screen's top-left, y down.
/// AppKit frames use the primary screen's bottom-left, y up.
/// The primary screen is the first entry, matching `NSScreen.screens[0]`.
final class HintGeometryTests: XCTestCase {
    func testLabelAndClickOnALeftScreenWithNegativeX() {
        let element = HintRect(x: -400, y: 100, width: 200, height: 40)
        assertPlacement(
            element: element,
            screens: [
                DisplayFrame(x: 0, y: 0, width: 1920, height: 1080, backingScale: 1),
                DisplayFrame(x: -1920, y: 0, width: 1920, height: 1080, backingScale: 1),
            ],
            badge: HintRect(x: -400, y: 964, width: 18, height: 16),
            click: HintPoint(x: -300, y: 120)
        )
    }

    func testLabelAndClickWhenTheScreensHaveDifferentHeights() {
        let element = HintRect(x: -100, y: 360, width: 80, height: 30)
        assertPlacement(
            element: element,
            screens: [
                DisplayFrame(x: 0, y: 0, width: 2560, height: 1440, backingScale: 1),
                DisplayFrame(x: -1920, y: 0, width: 1920, height: 1080, backingScale: 1),
            ],
            badge: HintRect(x: -100, y: 1070, width: 10, height: 10),
            click: HintPoint(x: -60, y: 375)
        )
    }

    func testLabelAndClickWhenTheSecondaryScreenIsAboveThePrimary() {
        let element = HintRect(x: 100, y: -900, width: 50, height: 20)
        assertPlacement(
            element: element,
            screens: [
                DisplayFrame(x: 0, y: 0, width: 1920, height: 1080, backingScale: 1),
                DisplayFrame(x: 0, y: 1080, width: 1440, height: 900, backingScale: 1),
            ],
            badge: HintRect(x: 100, y: 1970, width: 10, height: 10),
            click: HintPoint(x: 125, y: -890)
        )
    }

    func testBackingScaleDoesNotChangePointCoordinates() {
        let element = HintRect(x: -400, y: 100, width: 200, height: 40)
        let points = [
            DisplayFrame(x: 0, y: 0, width: 1920, height: 1080, backingScale: 1),
            DisplayFrame(x: -1920, y: 0, width: 1920, height: 1080, backingScale: 1),
        ]
        let retina = points.map { screen in
            DisplayFrame(
                x: screen.x,
                y: screen.y,
                width: screen.width,
                height: screen.height,
                backingScale: 2
            )
        }
        XCTAssertEqual(
            HintGeometry.labelRect(element: element, badgeWidth: 18, badgeHeight: 16, screens: retina),
            HintGeometry.labelRect(element: element, badgeWidth: 18, badgeHeight: 16, screens: points)
        )
        XCTAssertEqual(HintGeometry.clickPoint(element: element), HintPoint(x: -300, y: 120))
    }

    func testPanelFrameCoversLabelsOnBothDisplaysAndLocalOriginsAddBack() {
        let badges = [
            HintRect(x: -400, y: 964, width: 18, height: 16),
            HintRect(x: 100, y: 1970, width: 10, height: 10),
        ]
        guard let arranged = HintGeometry.arrange(badges: badges) else {
            return XCTFail("expected a panel")
        }
        XCTAssertEqual(arranged.frame, HintRect(x: -400, y: 964, width: 510, height: 1016))
        XCTAssertEqual(arranged.local.count, 2)
        for (global, local) in zip(badges, arranged.local) {
            XCTAssertEqual(local.x + arranged.frame.x, global.x)
            XCTAssertEqual(local.y + arranged.frame.y, global.y)
        }
    }

    func testHintLogLinesNameTheScanTheScreenAndTheClick() {
        XCTAssertEqual(
            ModeTrace.formatHintScan(
                bundleIdentifier: "com.tencent.xinWeChat",
                visited: 40,
                hits: 0,
                milliseconds: 12,
                expansion: "manual"
            ),
            "hint-scan bundle=com.tencent.xinWeChat visited=40 hits=0 ms=12 expansion=manual"
        )
        XCTAssertEqual(
            ModeTrace.formatHintClick(index: 2, method: "AXPress", x: -300, y: 120),
            "hint-click index=2 method=AXPress ax=-300.0,120.0"
        )
    }

    func testTheNthLabelClicksTheNthElement() {
        let targets = [
            HintTarget(frame: HintRect(x: -400, y: 100, width: 200, height: 40), identifier: "left"),
            HintTarget(frame: HintRect(x: 40, y: 200, width: 80, height: 30), identifier: "primary"),
            HintTarget(frame: HintRect(x: 100, y: -900, width: 50, height: 20), identifier: "above"),
        ]
        let session = HintSession(targets: targets, click: .plain)
        XCTAssertEqual(session.markers.count, targets.count)
        for marker in session.markers {
            var typing = HintSession(targets: targets, click: .plain)
            var outcome = HintSessionOutcome.inactive
            for character in marker.text {
                outcome = typing.handle(.character(character))
            }
            guard case .activated(let activation) = outcome else {
                return XCTFail("label \(marker.text) did not activate, got \(outcome)")
            }
            XCTAssertEqual(activation.index, marker.index)
            XCTAssertEqual(activation.identifier, targets[marker.index].identifier)
            XCTAssertEqual(activation.point, targets[marker.index].frame.center)
            XCTAssertEqual(
                activation.point,
                HintGeometry.clickPoint(element: targets[marker.index].frame)
            )
        }
    }

    private func assertPlacement(
        element: HintRect,
        screens: [DisplayFrame],
        badge: HintRect,
        click: HintPoint
    ) {
        let label = HintGeometry.labelRect(
            element: element,
            badgeWidth: badge.width,
            badgeHeight: badge.height,
            screens: screens
        )
        XCTAssertEqual(label, badge)
        let center = HintPoint(x: badge.x + badge.width / 2, y: badge.y + badge.height / 2)
        let axY = screens[0].height - center.y
        XCTAssertGreaterThanOrEqual(center.x, element.x)
        XCTAssertLessThanOrEqual(center.x, element.x + element.width)
        XCTAssertGreaterThanOrEqual(axY, element.y)
        XCTAssertLessThanOrEqual(axY, element.y + element.height)
        XCTAssertEqual(HintGeometry.clickPoint(element: element), click)
        XCTAssertEqual(click, element.center)
    }
}

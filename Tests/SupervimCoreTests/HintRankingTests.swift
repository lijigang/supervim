import XCTest
@testable import SupervimCore

/// Likelihood order for hint labels. Nothing is drawn or scanned here.
final class HintRankingTests: XCTestCase {
    func testButtonsOutrankLinksTabsMenuItemsAndGroups() {
        let window = HintRect(x: 0, y: 0, width: 800, height: 600)
        let items = [
            item("AXGroup", index: 0, x: 360, y: 260, width: 200, height: 80),
            item("AXStaticText", index: 1, x: 300, y: 300, width: 40, height: 16),
            item("AXMenuItem", index: 2, x: 20, y: 20, width: 120, height: 22),
            item("AXTab", index: 3, x: 40, y: 40, width: 80, height: 24),
            item("AXLink", index: 4, x: 100, y: 80, width: 60, height: 18),
            item("AXButton", index: 5, x: 500, y: 400, width: 30, height: 20),
        ]
        let ordered = HintRanking.order(items, window: window)
        XCTAssertEqual(ordered.map(\.role), [
            "AXButton", "AXLink", "AXTab", "AXMenuItem", "AXGroup", "AXStaticText",
        ])
    }

    func testCenterAndSizeBreakTiesInsideOneRole() {
        let window = HintRect(x: 0, y: 0, width: 800, height: 600)
        let items = [
            item("AXButton", index: 0, x: 10, y: 10, width: 40, height: 20),
            item("AXButton", index: 1, x: 360, y: 280, width: 80, height: 40),
            item("AXButton", index: 2, x: 430, y: 290, width: 20, height: 16),
        ]
        let ordered = HintRanking.order(items, window: window)
        XCTAssertEqual(ordered.map(\.index), [1, 2, 0])
    }

    func testPointerPullsAnOtherwiseEqualTargetForward() {
        let window = HintRect(x: 0, y: 0, width: 800, height: 600)
        let items = [
            item("AXButton", index: 0, x: 280, y: 290, width: 40, height: 20),
            item("AXButton", index: 1, x: 480, y: 290, width: 40, height: 20),
        ]
        let ordered = HintRanking.order(items, window: window, pointer: HintPoint(x: 500, y: 300))
        XCTAssertEqual(ordered.map(\.index), [1, 0])
        let again = HintRanking.order(items, window: window, pointer: HintPoint(x: 500, y: 300))
        XCTAssertEqual(again.map(\.index), ordered.map(\.index))
    }

    func testTinyControlsSortAfterNormalOnesAndOffscreenOnesDrop() {
        let window = HintRect(x: 0, y: 0, width: 400, height: 300)
        let items = [
            item("AXButton", index: 0, x: 1, y: 1, width: 4, height: 4),
            item("AXGroup", index: 1, x: 40, y: 40, width: 80, height: 40),
            item("AXButton", index: 2, x: 900, y: 900, width: 40, height: 20),
            item("AXLink", index: 3, x: 80, y: 80, width: 30, height: 16),
        ]
        let ordered = HintRanking.order(items, window: window)
        XCTAssertEqual(ordered.map(\.index), [3, 1, 0])
    }

    func testALoneTinyTargetIsKept() {
        let only = [item("AXButton", index: 4, x: 0, y: 0, width: 2, height: 2)]
        XCTAssertEqual(HintRanking.order(only).map(\.index), [4])
    }

    func testOriginalIndexBreaksATotalTie() {
        let window = HintRect(x: 0, y: 0, width: 200, height: 200)
        let items = [
            item("AXButton", index: 3, x: 80, y: 80, width: 40, height: 20),
            item("AXButton", index: 1, x: 80, y: 80, width: 40, height: 20),
        ]
        XCTAssertEqual(HintRanking.order(items, window: window).map(\.index), [1, 3])
    }

    private func item(
        _ role: String,
        index: Int,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> HintRankItem {
        HintRankItem(
            role: role,
            subrole: nil,
            frame: HintRect(x: x, y: y, width: width, height: height),
            index: index
        )
    }
}

import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// Fixtures for the two complaints about `f`: a control with no label, and
/// one control with several labels. Each tree is a copied accessibility
/// tree, shaped like the app named in the test.
final class ClickableDetectionTests: XCTestCase {
    // MARK: Controls that had no label

    func testSidebarRowsAreLabelledOncePerRow() {
        let rows = (0..<3).map { index in
            node("AXRow", frame: rect(0, 100 + Double(index) * 30, 200, 30), children: [
                node("AXCell", frame: rect(0, 100 + Double(index) * 30, 200, 30), children: [
                    node("AXImage", frame: rect(8, 106 + Double(index) * 30, 18, 18)),
                    node("AXStaticText", frame: rect(32, 106 + Double(index) * 30, 120, 18)),
                ]),
            ])
        }
        let found = clickables(window(children: [
            node("AXScrollArea", frame: rect(0, 100, 200, 400), children: [
                node("AXOutline", frame: rect(0, 100, 200, 400), children: rows),
            ]),
        ]))
        XCTAssertEqual(found.map(\.role), ["AXRow", "AXRow", "AXRow"])
        XCTAssertEqual(found.map(\.path), [[0, 0, 0], [0, 0, 1], [0, 0, 2]])
    }

    func testFinderIconWithOnlyTheOpenActionIsClickable() {
        let found = clickables(window(children: [
            node("AXImage", actions: ["AXOpen"], frame: rect(40, 40, 64, 64)),
            node("AXImage", frame: rect(140, 40, 64, 64)),
        ]))
        XCTAssertEqual(found.map(\.path), [[0]])
    }

    func testShowMenuAloneCountsOnlyOffTextAndContainers() {
        let found = clickables(window(children: [
            node("AXStaticText", actions: ["AXShowMenu"], frame: rect(10, 10, 80, 16)),
            node("AXGroup", actions: ["AXShowMenu"], frame: rect(10, 40, 80, 16)),
            node("AXImage", actions: ["AXShowMenu"], frame: rect(10, 70, 80, 16)),
            node("AXWebArea", actions: ["AXShowMenu"], frame: rect(10, 100, 80, 16)),
            node("AXCustomBadge", actions: ["AXShowMenu"], frame: rect(10, 130, 80, 16)),
            node(nil, actions: ["AXShowMenu"], frame: rect(10, 160, 80, 16)),
        ]))
        XCTAssertEqual(found.map(\.role), ["AXCustomBadge"])
    }

    func testMenuBarItemsDockItemsAndHeaderSortButtonsAreClickable() {
        let found = clickables(window(children: [
            node("AXMenuBarItem", frame: rect(10, 10, 60, 22)),
            node("AXDockItem", frame: rect(80, 10, 60, 22)),
            node("AXGroup", subrole: "AXSortButton", frame: rect(150, 10, 60, 22)),
            node("AXGroup", subrole: "AXTabButton", frame: rect(220, 10, 60, 22)),
            node("AXDateField", frame: rect(290, 10, 60, 22)),
            node("AXLevelIndicator", frame: rect(360, 10, 60, 22)),
        ]))
        XCTAssertEqual(found.map(\.path), [[0], [1], [2], [3], [4], [5]])
    }

    func testZeroSizeAndFramelessParentsDoNotHideTheirChildren() {
        let found = clickables(window(children: [
            node("AXGroup", frame: rect(0, 0, 0, 0), children: [
                node("AXButton", frame: rect(20, 20, 80, 24)),
            ]),
            node("AXGroup", frame: nil, children: [
                node("AXLink", frame: rect(20, 60, 80, 24)),
            ]),
        ]))
        XCTAssertEqual(found.map(\.path), [[0, 0], [1, 0]])
    }

    func testButtonBesideAScrollAreaIsNotClippedByThatSiblingViewport() {
        let found = clickables(window(children: [
            node("AXScrollArea", frame: rect(0, 100, 300, 400), children: []),
            node("AXButton", frame: rect(280, 80, 60, 40)),
        ]))
        XCTAssertEqual(found.map(\.frame), [rect(280, 80, 60, 40)])
    }

    func testWebLinkIsClippedByEveryAncestorViewport() {
        let found = clickables(window(children: [
            node("AXScrollArea", frame: rect(0, 100, 600, 400), children: [
                node("AXWebArea", frame: rect(0, 100, 600, 4_000), children: [
                    node("AXScrollArea", frame: rect(50, 300, 200, 100), children: [
                        node("AXLink", frame: rect(60, 380, 100, 40)),
                    ]),
                ]),
            ]),
        ]))
        XCTAssertEqual(found.map(\.frame), [rect(60, 380, 100, 20)])
    }

    // MARK: Labels that were not on a control

    func testRowScrolledAboveItsListIsNotLabelledOverTheToolbar() {
        let found = clickables(window(children: [
            node("AXToolbar", frame: rect(0, 40, 800, 60), children: [
                node("AXButton", frame: rect(20, 55, 60, 30)),
            ]),
            node("AXScrollArea", frame: rect(0, 100, 300, 400), children: [
                node("AXButton", frame: rect(20, 60, 200, 30)),
                node("AXButton", frame: rect(20, 120, 200, 30)),
                node("AXButton", frame: rect(20, 520, 200, 30)),
            ]),
        ]))
        XCTAssertEqual(found.map(\.path), [[0, 0], [1, 1]])
    }

    func testItemScrolledOutOfAnInnerListIsNotLabelledInsideTheOuterOne() {
        let found = clickables(window(children: [
            node("AXScrollArea", frame: rect(0, 100, 600, 400), children: [
                node("AXScrollArea", frame: rect(50, 150, 200, 100), children: [
                    node("AXLink", frame: rect(60, 300, 100, 20)),
                    node("AXLink", frame: rect(60, 200, 100, 20)),
                ]),
            ]),
        ]))
        XCTAssertEqual(found.map(\.path), [[0, 0, 1]])
    }

    func testDisabledControlsAreSkipped() {
        var off = node("AXButton", frame: rect(20, 20, 80, 24))
        off.isEnabled = false
        var on = node("AXButton", frame: rect(20, 60, 80, 24))
        on.isEnabled = true
        let found = clickables(window(children: [off, on, node("AXButton", frame: rect(20, 100, 80, 24))]))
        XCTAssertEqual(found.map(\.path), [[1], [2]])
    }

    func testScrollBarPartsAreNotLabelled() {
        let found = clickables(window(children: [
            node("AXScrollArea", frame: rect(0, 100, 300, 400), children: [
                node("AXScrollBar", frame: rect(285, 100, 15, 400), children: [
                    node("AXValueIndicator", frame: rect(285, 120, 15, 80)),
                    node("AXButton", subrole: "AXIncrementPage", actions: ["AXPress"], frame: rect(285, 200, 15, 300)),
                    node("AXButton", subrole: "AXDecrementPage", actions: ["AXPress"], frame: rect(285, 100, 15, 20)),
                ]),
                node("AXButton", frame: rect(20, 120, 100, 30)),
            ]),
        ]))
        XCTAssertEqual(found.map(\.path), [[0, 1]])
    }

    func testWebTableRowsAndCellsAreNotClickableByRole() {
        let found = clickables(window(children: [
            node("AXWebArea", frame: rect(0, 100, 600, 400), children: [
                node("AXTable", frame: rect(0, 100, 600, 200), children: [
                    node("AXRow", frame: rect(0, 100, 600, 30), children: [
                        node("AXCell", frame: rect(0, 100, 300, 30), children: [
                            node("AXLink", actions: ["AXPress"], frame: rect(4, 104, 80, 20)),
                        ]),
                        node("AXCell", frame: rect(300, 100, 300, 30)),
                    ]),
                ]),
            ]),
        ]))
        XCTAssertEqual(found.map(\.role), ["AXLink"])
    }

    // MARK: One control, several labels

    func testChromiumLinkWithPressOnItsTextAndImageIsOneTarget() {
        let found = clickables(window(children: [
            node("AXLink", actions: ["AXPress"], frame: rect(20, 20, 200, 40), children: [
                node("AXImage", actions: ["AXPress"], frame: rect(24, 24, 32, 32)),
                node("AXStaticText", actions: ["AXPress"], frame: rect(60, 30, 150, 20)),
                node("AXGroup", actions: ["AXPress"], frame: rect(60, 30, 150, 20), children: [
                    node("AXStaticText", actions: ["AXPress"], frame: rect(60, 30, 150, 20)),
                ]),
            ]),
        ]))
        XCTAssertEqual(found.map(\.path), [[0]])
    }

    func testWrapperGroupWithTheSameFrameKeepsTheButtonInside() {
        let found = clickables(window(children: [
            node("AXGroup", actions: ["AXPress"], frame: rect(20, 20, 100, 30), children: [
                node("AXButton", actions: ["AXPress"], frame: rect(21, 20, 99, 30)),
            ]),
        ]))
        XCTAssertEqual(found.map(\.path), [[0, 0]])
        XCTAssertEqual(found.map(\.role), ["AXButton"])
    }

    func testTwoElementsOnTheSameVisibleFrameCollapseToTheMoreSpecificOne() {
        let found = clickables(window(children: [
            node("AXGroup", actions: ["AXPress"], frame: rect(20, 20, 100, 30)),
            node("AXButton", frame: rect(20, 20, 100, 30)),
            node("AXLink", frame: rect(22, 21, 97, 29)),
            node("AXButton", frame: rect(20, 60, 100, 30)),
        ]))
        XCTAssertEqual(found.map(\.path), [[1], [3]])
    }

    func testNeighboursThatOnlyTouchAreKept() {
        let found = clickables(window(children: [
            node("AXButton", frame: rect(20, 20, 40, 30)),
            node("AXButton", frame: rect(60, 20, 40, 30)),
            node("AXButton", frame: rect(40, 20, 40, 30)),
        ]))
        XCTAssertEqual(found.map(\.path), [[0], [1], [2]])
    }

    func testCellsAndColumnsDoNotRepeatTheRow() {
        let cell = node("AXCell", frame: rect(0, 100, 200, 30), children: [
            node("AXStaticText", frame: rect(8, 104, 120, 18)),
        ])
        let found = clickables(window(children: [
            node("AXTable", frame: rect(0, 100, 200, 400), children: [
                node("AXRow", frame: rect(0, 100, 200, 30), children: [cell]),
                node("AXColumn", frame: rect(0, 100, 200, 400), children: [cell]),
            ]),
        ]))
        XCTAssertEqual(found.map(\.path), [[0, 0]])
    }

    func testFinderListRowKeepsTheNameFieldInsteadOfTheRow() {
        let found = clickables(window(children: [
            node("AXOutline", frame: rect(0, 100, 600, 400), children: [
                node("AXRow", frame: rect(0, 100, 600, 24), children: [
                    node("AXCell", frame: rect(0, 100, 300, 24), children: [
                        node("AXImage", frame: rect(4, 102, 20, 20)),
                        node("AXTextField", frame: rect(28, 102, 200, 20)),
                    ]),
                    node("AXCell", frame: rect(300, 100, 300, 24), children: [
                        node("AXStaticText", frame: rect(304, 102, 100, 20)),
                    ]),
                ]),
            ]),
        ]))
        XCTAssertEqual(found.map(\.role), ["AXTextField"])
    }

    func testRowWithACheckboxKeepsBothTargets() {
        let found = clickables(window(children: [
            node("AXTable", frame: rect(0, 100, 600, 400), children: [
                node("AXRow", frame: rect(0, 100, 600, 30), children: [
                    node("AXCell", frame: rect(0, 100, 600, 30), children: [
                        node("AXCheckBox", frame: rect(8, 104, 22, 22)),
                        node("AXStaticText", frame: rect(40, 104, 200, 22)),
                    ]),
                ]),
            ]),
        ]))
        XCTAssertEqual(found.map(\.role), ["AXRow", "AXCheckBox"])
    }

    func testPageSizedPressGroupIsNotATargetWhenItHoldsControls() {
        let found = clickables(window(children: [
            node("AXWebArea", frame: rect(0, 0, 800, 600), children: [
                node("AXGroup", actions: ["AXPress"], frame: rect(0, 0, 800, 600), children: [
                    node("AXButton", actions: ["AXPress"], frame: rect(20, 20, 80, 30)),
                    node("AXLink", actions: ["AXPress"], frame: rect(20, 80, 80, 20)),
                    node("AXGroup", actions: ["AXPress"], frame: rect(20, 120, 300, 80)),
                ]),
            ]),
        ]))
        XCTAssertEqual(found.map(\.path), [[0, 0, 0], [0, 0, 1], [0, 0, 2]])
    }

    func testCardWithPressIsOneTargetAndKeepsTheButtonInside() {
        let found = clickables(window(children: [
            node("AXGroup", actions: ["AXPress"], frame: rect(20, 20, 300, 120), children: [
                node("AXImage", actions: ["AXPress"], frame: rect(28, 28, 60, 60)),
                node("AXStaticText", actions: ["AXPress"], frame: rect(100, 30, 200, 20)),
                node("AXButton", actions: ["AXPress"], frame: rect(260, 100, 50, 28)),
            ]),
        ]))
        XCTAssertEqual(found.map(\.path), [[0], [0, 2]])
    }

    func testStepperKeepsItsArrowsAndDropsTheWrapper() {
        let found = clickables(window(children: [
            node("AXIncrementor", frame: rect(20, 20, 16, 24), children: [
                node("AXButton", actions: ["AXPress"], frame: rect(20, 20, 16, 12)),
                node("AXButton", actions: ["AXPress"], frame: rect(20, 32, 16, 12)),
            ]),
        ]))
        XCTAssertEqual(found.map(\.path), [[0, 0], [0, 1]])
    }

    func testEditableCandidatesUseTheSameAncestorClipping() {
        let tree = window(children: [
            node("AXScrollArea", frame: rect(0, 100, 300, 400), children: [
                node("AXTextField", frame: rect(20, 60, 200, 30)),
                node("AXTextField", frame: rect(20, 200, 200, 30)),
            ]),
        ])
        let found = FocusClassification.editableCandidates(in: tree, limits: .standard, inFocusedWindow: true)
        XCTAssertEqual(found.candidates.map(\.path), [[0, 1]])
        XCTAssertFalse(found.truncated)
    }

    func testVisibleElementWithAncestorsDropsWhatTheChainHides() {
        let window = HintRect(x: 0, y: 0, width: 800, height: 600)
        let outer = HintRect(x: 0, y: 100, width: 600, height: 400)
        let inner = HintRect(x: 50, y: 150, width: 200, height: 100)
        XCTAssertNil(HintGeometry.visibleElement(
            HintRect(x: 60, y: 300, width: 100, height: 20), window: window, ancestors: [outer, inner]
        ))
        XCTAssertEqual(
            HintGeometry.visibleElement(
                HintRect(x: 60, y: 240, width: 100, height: 20), window: window, ancestors: [outer, inner]
            ),
            HintRect(x: 60, y: 240, width: 100, height: 10)
        )
        XCTAssertEqual(
            HintGeometry.visibleElement(
                HintRect(x: 700, y: 20, width: 60, height: 20), window: window, ancestors: []
            ),
            HintRect(x: 700, y: 20, width: 60, height: 20)
        )
        XCTAssertNil(HintGeometry.visibleElement(
            HintRect(x: 0, y: 490, width: 600, height: 4_000), window: window, ancestors: [outer]
        ))
        XCTAssertNil(HintGeometry.visibleElement(
            HintRect(x: 60, y: 160, width: 100, height: 20),
            window: window,
            ancestors: [HintRect(x: 0, y: 0, width: 0, height: 0), HintRect(x: 500, y: 500, width: 20, height: 20)]
        ))
        XCTAssertEqual(
            HintGeometry.visibleElement(
                HintRect(x: 60, y: 160, width: 100, height: 20), window: nil, ancestors: [inner]
            ),
            HintRect(x: 60, y: 160, width: 100, height: 20)
        )
    }

    // MARK: Helpers

    private func clickables(_ tree: AccessibilityElement) -> [ClickableElement] {
        FocusClassification.clickableElements(in: tree, limits: .standard).elements
    }

    private func window(children: [AccessibilityElement]) -> AccessibilityElement {
        AccessibilityElement(role: "AXWindow", frame: rect(0, 0, 800, 600), children: children)
    }

    private func node(
        _ role: String?,
        subrole: String? = nil,
        actions: [String] = [],
        frame: ElementFrame?,
        children: [AccessibilityElement] = []
    ) -> AccessibilityElement {
        AccessibilityElement(role: role, subrole: subrole, actions: actions, frame: frame, children: children)
    }

    private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> ElementFrame {
        ElementFrame(x: x, y: y, width: width, height: height)
    }
}

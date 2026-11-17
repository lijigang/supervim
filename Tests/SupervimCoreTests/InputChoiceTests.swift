import XCTest
@testable import SupervimCore

final class InputChoiceTests: XCTestCase {
    func testBottomComposerBeatsTheFirstSearchFieldUnlessItWasFocused() {
        let search = InputCandidate(
            role: "AXTextField",
            subrole: "AXSearchField",
            frame: HintRect(x: 10, y: 10, width: 200, height: 24),
            path: [0],
            editable: true,
            identity: "search",
            inFocusedWindow: true
        )
        let composer = InputCandidate(
            role: "AXTextArea",
            subrole: nil,
            frame: HintRect(x: 10, y: 400, width: 500, height: 80),
            path: [3],
            editable: true,
            identity: "composer",
            inFocusedWindow: true
        )
        let popup = InputCandidate(
            role: "AXPopUpButton",
            subrole: nil,
            frame: HintRect(x: 10, y: 500, width: 400, height: 40),
            path: [4],
            editable: true,
            identity: "popup",
            inFocusedWindow: true
        )
        let otherWindow = InputCandidate(
            role: "AXTextArea",
            subrole: nil,
            frame: HintRect(x: 10, y: 700, width: 800, height: 100),
            path: [0],
            editable: true,
            identity: "other",
            inFocusedWindow: false
        )
        XCTAssertEqual(
            InputChoice.best([search, composer, popup, otherWindow], lastFocusedIdentity: nil, window: nil)?.identity,
            "composer"
        )
        XCTAssertEqual(
            InputChoice.best([search, composer], lastFocusedIdentity: "search", window: nil)?.identity,
            "search"
        )
    }

    func testBottomCenterStaysInsideARealWindowAndRefusesATinyOne() {
        XCTAssertEqual(
            InputChoice.bottomCenter(of: HintRect(x: 0, y: 0, width: 800, height: 600)),
            HintPoint(x: 400, y: 552)
        )
        XCTAssertNil(InputChoice.bottomCenter(of: HintRect(x: 0, y: 0, width: 40, height: 40)))
        XCTAssertEqual(
            InputChoice.logLine(decision: "none", fields: ["reason=no-input"]),
            "gi decision=none reason=no-input"
        )
    }
}

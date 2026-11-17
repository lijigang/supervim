import XCTest
@testable import SupervimCore

/// Labels, filtering, activation, and cancellation for one hint session.
/// No window, click, or accessibility walk happens here.
final class HintSessionTests: XCTestCase {
    func testOneTargetShowsUppercaseAAtTheOrigin() {
        let frame = HintRect(x: 10, y: 20, width: 8, height: 6)
        let session = HintSession(targets: [HintTarget(frame: frame, identifier: "0")], click: .plain)
        XCTAssertEqual(session.click, .plain)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.markers, [
            HintMarker(index: 0, text: "A", anchor: HintPoint(x: 10, y: 20), elementWidth: 8, elementHeight: 6),
        ])
    }

    func testTypingTheOnlyLabelActivatesTheCenter() {
        var session = HintSession(targets: [sampleTarget(0)], click: .plain)
        XCTAssertEqual(session.markers, [HintMarker(index: 0, text: "A", anchor: HintPoint(x: 10, y: 20), elementWidth: 8, elementHeight: 6)])
        XCTAssertEqual(
            session.handle(.character("a")),
            .activated(HintActivation(index: 0, click: .plain, point: HintPoint(x: 14, y: 23), identifier: "0"))
        )
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.markers, [])
        XCTAssertEqual(session.handle(.character("a")), .inactive)
    }

    func testCommandClickKindIsRememberedOnActivation() {
        var session = HintSession(targets: [sampleTarget(0)], click: .command)
        XCTAssertEqual(
            session.handle(.character("A")),
            .activated(HintActivation(index: 0, click: .command, point: HintPoint(x: 14, y: 23), identifier: "0"))
        )
    }

    func testPartialPrefixShowsMatchesWithoutActivating() {
        var session = HintSession(targets: tenTargets(), click: .plain)
        guard case .showing(let markers) = session.handle(.character("a")) else {
            return XCTFail("a shared prefix should keep the hint open")
        }
        XCTAssertEqual(markers, [
            HintMarker(index: 0, text: "AA", anchor: HintPoint(x: 0, y: 0), elementWidth: 20, elementHeight: 10),
            HintMarker(index: 9, text: "AS", anchor: HintPoint(x: 270, y: 0), elementWidth: 20, elementHeight: 10),
        ])
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.markers, markers)
    }

    func testCompletingTheSecondCharacterActivatesThatTarget() {
        var session = HintSession(targets: tenTargets(), click: .command)
        XCTAssertEqual(session.handle(.character("a")), .showing([
            HintMarker(index: 0, text: "AA", anchor: HintPoint(x: 0, y: 0), elementWidth: 20, elementHeight: 10),
            HintMarker(index: 9, text: "AS", anchor: HintPoint(x: 270, y: 0), elementWidth: 20, elementHeight: 10),
        ]))
        XCTAssertEqual(
            session.handle(.character("s")),
            .activated(HintActivation(
                index: 9,
                click: .command,
                point: HintPoint(x: 280, y: 5),
                identifier: "9"
            ))
        )
    }

    func testSingleLetterAmongLongerLabelsActivatesImmediately() {
        var session = HintSession(targets: tenTargets(), click: .plain)
        XCTAssertEqual(
            session.handle(.character("d")),
            .activated(HintActivation(index: 1, click: .plain, point: HintPoint(x: 40, y: 5), identifier: "1"))
        )
    }

    func testInvalidCharacterCancelsAndFurtherInputIsInactive() {
        var session = HintSession(targets: tenTargets(), click: .plain)
        _ = session.handle(.character("a"))
        XCTAssertEqual(session.handle(.character("q")), .cancelled)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.handle(.character("a")), .inactive)
        XCTAssertEqual(session.cancel(), .inactive)
    }

    func testCancelDoesNotActivate() {
        var session = HintSession(targets: [sampleTarget(0)], click: .plain)
        XCTAssertEqual(session.cancel(), .cancelled)
        XCTAssertEqual(session.markers, [])
        XCTAssertEqual(session.handle(.backspace), .inactive)
    }

    func testBackspaceRestoresHiddenMarkers() {
        var session = HintSession(targets: tenTargets(), click: .plain)
        _ = session.handle(.character("a"))
        guard case .showing(let restored) = session.handle(.backspace) else {
            return XCTFail("backspace should reopen the filtered labels")
        }
        XCTAssertEqual(restored.count, 10)
        XCTAssertEqual(restored.map(\.text), HintLabeler(elementCount: 10).labels.map(\.displayText))
        XCTAssertTrue(session.isActive)
    }

    func testBackspaceOnAnEmptyPrefixStaysShowing() {
        var session = HintSession(targets: [sampleTarget(0)], click: .plain)
        guard case .showing(let markers) = session.handle(.backspace) else {
            return XCTFail("backspace with nothing typed should keep the label")
        }
        XCTAssertEqual(markers, [HintMarker(index: 0, text: "A", anchor: HintPoint(x: 10, y: 20), elementWidth: 8, elementHeight: 6)])
    }

    func testNoTargetsStartInactive() {
        let session = HintSession(targets: [], click: .plain)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.markers, [])
    }

    func testUnusableFramesAreDroppedBeforeLabeling() {
        let targets = [
            HintTarget(frame: HintRect(x: .nan, y: 0, width: 10, height: 10), identifier: "bad"),
            HintTarget(frame: HintRect(x: 0, y: 0, width: 0, height: 10), identifier: "flat"),
            HintTarget(frame: HintRect(x: 4, y: 6, width: 10, height: 8), identifier: "ok"),
            HintTarget(
                frame: HintRect(x: .greatestFiniteMagnitude, y: 0, width: .greatestFiniteMagnitude, height: 2),
                identifier: "overflow"
            ),
        ]
        let session = HintSession(targets: targets, click: .plain)
        XCTAssertEqual(session.markers, [
            HintMarker(index: 0, text: "A", anchor: HintPoint(x: 4, y: 6), elementWidth: 10, elementHeight: 8),
        ])
        XCTAssertFalse(HintRect(x: 1, y: 1, width: -5, height: 5).isUsable)
        XCTAssertTrue(HintRect(x: 4, y: 6, width: 10, height: 8).isUsable)
    }

    func testAllUnusableFramesStartInactive() {
        let session = HintSession(
            targets: [HintTarget(frame: HintRect(x: 0, y: 0, width: 0, height: 1))],
            click: .command
        )
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.click, .command)
    }

    func testActivationKeepsTheUsableTargetIdentifier() {
        var session = HintSession(
            targets: [
                HintTarget(frame: HintRect(x: 0, y: 0, width: 0, height: 4), identifier: "skip"),
                sampleTarget(3, identifier: "2/0"),
            ],
            click: .plain
        )
        XCTAssertEqual(
            session.handle(.character("a")),
            .activated(HintActivation(index: 0, click: .plain, point: HintPoint(x: 14, y: 23), identifier: "2/0"))
        )
    }

    func testResolveMapsCharactersEscapeAndBackspace() {
        XCTAssertEqual(HintTyping.resolve(KeyEvent("a")), .input(.character("a")))
        XCTAssertEqual(
            HintTyping.resolve(KeyEvent("b", modifiers: .command)),
            .input(.character("b"))
        )
        XCTAssertEqual(HintTyping.resolve(KeyEvent(identity: .escape)), .cancel)
        XCTAssertEqual(
            HintTyping.resolve(KeyEvent(identity: .unnamed), keyCode: HintTyping.backspaceKeyCode),
            .input(.backspace)
        )
        XCTAssertEqual(HintTyping.resolve(KeyEvent(identity: .unnamed)), .cancel)
        XCTAssertEqual(HintTyping.resolve(KeyEvent(identity: .unnamed), keyCode: 0x7B), .cancel)
        XCTAssertEqual(HintTyping.backspaceKeyCode, 0x33)
    }

    func testMarkersFollowHintLabelerOrderAndDisplayText() {
        let session = HintSession(targets: tenTargets(), click: .plain)
        let expected = HintLabeler(elementCount: 10).labels.map { label in
            HintMarker(
                index: label.index,
                text: label.displayText,
                anchor: HintPoint(x: Double(label.index) * 30, y: 0),
                elementWidth: 20,
                elementHeight: 10
            )
        }
        XCTAssertEqual(session.markers, expected)
    }

    func testSessionSourceDoesNotTouchTheSystemOrRecordKeys() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimCore/HintSession.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        for token in [
            "import AppKit",
            "import ApplicationServices",
            "import CoreGraphics",
            "import Accessibility",
            "AXUIElement",
            "CGEvent",
            "URLSession",
            "os_log",
            "Logger(",
            "NSLog",
            "print(",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
    }
}

private func sampleTarget(_ index: Int, identifier: String? = nil) -> HintTarget {
    HintTarget(
        frame: HintRect(x: 10, y: 20, width: 8, height: 6),
        identifier: identifier ?? String(index)
    )
}

private func tenTargets() -> [HintTarget] {
    (0..<10).map { index in
        HintTarget(
            frame: HintRect(x: Double(index) * 30, y: 0, width: 20, height: 10),
            identifier: String(index)
        )
    }
}

import XCTest
@testable import SupervimCore

/// The redesign candidates: which one ships, what each is drawn from, how
/// readable its colors are, and where a label with a pointer is put.
final class HintLabelStyleTests: XCTestCase {
    private let screens = [
        DisplayFrame(x: 0, y: 0, width: 1440, height: 900, backingScale: 2),
        DisplayFrame(x: -1280, y: 0, width: 1280, height: 800, backingScale: 1),
    ]

    func testTheShippedStyleIsStillClassicAndTheCandidatesAreAToD() {
        XCTAssertEqual(HintLabelStyle.shipped, .classic)
        XCTAssertEqual(HintLabelStyle.candidates, [.amber, .ink, .cursor, .glass])
        XCTAssertEqual(HintLabelStyle.candidates.map(\.optionLetter), ["A", "B", "C", "D"])
        XCTAssertNil(HintLabelStyle.classic.optionLetter)
        XCTAssertEqual(Set(HintLabelStyle.allCases.map(\.title)).count, HintLabelStyle.allCases.count)
        XCTAssertFalse(HintLabelStyle.candidates.contains(.shipped))
    }

    func testAStyleIsChosenByNameOrLetterAndAnythingElseIsTheShippedStyle() {
        XCTAssertEqual(HintLabelStyle.resolve(nil), .classic)
        XCTAssertEqual(HintLabelStyle.resolve(""), .classic)
        XCTAssertEqual(HintLabelStyle.resolve("  "), .classic)
        XCTAssertEqual(HintLabelStyle.resolve("neon"), .classic)
        XCTAssertEqual(HintLabelStyle.resolve("amber"), .amber)
        XCTAssertEqual(HintLabelStyle.resolve("Amber "), .amber)
        XCTAssertEqual(HintLabelStyle.resolve("A"), .amber)
        XCTAssertEqual(HintLabelStyle.resolve("b"), .ink)
        XCTAssertEqual(HintLabelStyle.resolve("INK"), .ink)
        XCTAssertEqual(HintLabelStyle.resolve("c"), .cursor)
        XCTAssertEqual(HintLabelStyle.resolve("cursor"), .cursor)
        XCTAssertEqual(HintLabelStyle.resolve("D"), .glass)
        XCTAssertEqual(HintLabelStyle.resolve("glass"), .glass)
        XCTAssertEqual(HintLabelStyle.resolve("classic"), .classic)
    }

    func testThePreferenceIsReadFromTheFirstStoreThatHasOne() throws {
        let name = "supervim.tests.hint-style.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        XCTAssertEqual(HintLabelStyle.preferred(in: [nil, store]), .classic)
        store.set("glass", forKey: HintLabelStyle.defaultsKey)
        XCTAssertEqual(HintLabelStyle.preferred(in: [nil, store]), .glass)
        store.set("nonsense", forKey: HintLabelStyle.defaultsKey)
        XCTAssertEqual(HintLabelStyle.preferred(in: [store]), .classic)
        store.removeObject(forKey: HintLabelStyle.defaultsKey)
        XCTAssertEqual(HintLabelStyle.preferred(in: [store]), .classic)
        XCTAssertEqual(HintLabelStyle.preferred(in: []), .classic)
        XCTAssertEqual(HintLabelStyle.defaultsKey, "SupervimHintLabelStyle")
    }

    func testClassicKeepsItsNumbersAndEveryCandidateIsLargerBolderAndPointed() {
        let classic = HintLabelStyle.classic.spec
        XCTAssertEqual(classic.fontSize, 12)
        XCTAssertEqual(classic.fontWeight, .semibold)
        XCTAssertEqual(classic.fontDesign, .mono)
        XCTAssertEqual(classic.pointer, .none)
        XCTAssertEqual(classic.margin, HintBadgeMetrics.shadowMargin)
        XCTAssertEqual(classic.cornerRadius, HintBadgeMetrics.cornerRadius)
        XCTAssertEqual(HintLabelStyle.classic.palette(dark: false).fillTop, ChromePalette.lightFill)
        XCTAssertEqual(HintLabelStyle.classic.palette(dark: true).typedText, ChromePalette.darkMatched)

        for style in HintLabelStyle.candidates {
            let spec = style.spec
            XCTAssertGreaterThanOrEqual(spec.fontSize, 14, "\(style)")
            XCTAssertLessThanOrEqual(spec.fontSize, 16, "\(style)")
            XCTAssertNotEqual(spec.fontWeight, .semibold, "\(style)")
            XCTAssertNotEqual(spec.pointer, .none, "\(style)")
            XCTAssertGreaterThanOrEqual(spec.tracking, 0, "\(style)")
            if spec.pointer == .caret {
                XCTAssertGreaterThanOrEqual(spec.margin, HintLabelMetrics.caretHeight, "\(style)")
            }
        }
        // Four directions, not four tints: no two share a typed treatment,
        // and each font design and each pointer is used by two of them.
        XCTAssertEqual(Set(HintLabelStyle.candidates.map(\.spec.typed)).count, 4)
        XCTAssertEqual(HintLabelStyle.candidates.filter { $0.spec.fontDesign == .mono }.count, 2)
        XCTAssertEqual(HintLabelStyle.candidates.filter { $0.spec.pointer == .caret }.count, 2)
        XCTAssertEqual(HintLabelStyle.candidates.filter { $0.spec.cornerRadius == nil }.count, 2)
        XCTAssertEqual(HintLabelFontDesign.mono.familyName, "SF Mono")
        XCTAssertEqual(HintLabelFontDesign.rounded.familyName, "SF Pro Rounded")
    }

    func testLettersToTypeClearSevenToOneOnEveryFillOverLoudBackdrops() {
        for style in HintLabelStyle.candidates {
            for dark in [false, true] {
                let palette = style.palette(dark: dark)
                for backdrop in ChromePalette.backdrops {
                    for fill in palette.fills(over: backdrop) {
                        let ratio = palette.text.contrastRatio(against: fill)
                        XCTAssertGreaterThanOrEqual(
                            ratio, 7,
                            "\(style) dark=\(dark) text \(ratio) on \(fill) over \(backdrop)"
                        )
                    }
                }
            }
        }
    }

    func testTypedLettersAreReadableWhereTheyCarryColorAndFaintWhereTheyFade() {
        for style in HintLabelStyle.candidates {
            for dark in [false, true] {
                let palette = style.palette(dark: dark)
                for backdrop in ChromePalette.backdrops {
                    for fill in palette.fills(over: backdrop) {
                        let paper = palette.typedFill ?? fill
                        let typed = palette.typedInk(on: fill).contrastRatio(against: paper)
                        let rest = palette.text.contrastRatio(against: fill)
                        let note = "\(style) dark=\(dark) typed \(typed) rest \(rest) over \(backdrop)"
                        switch style.spec.typed {
                        case .recolor, .inverse:
                            XCTAssertGreaterThanOrEqual(typed, ChromePalette.minimumTextContrast, note)
                            XCTAssertNotEqual(palette.typedText, palette.text, note)
                        case .dim, .dimWithCursor:
                            // Still a letter, but plainly not the one to press next.
                            XCTAssertGreaterThanOrEqual(typed, 1.35, note)
                            XCTAssertLessThanOrEqual(typed, 3.2, note)
                            XCTAssertGreaterThanOrEqual(rest / typed, 3, note)
                        }
                    }
                }
            }
        }
        XCTAssertNotNil(HintLabelStyle.cursor.palette(dark: false).typedFill)
        XCTAssertNil(HintLabelStyle.amber.palette(dark: false).typedFill)
    }

    func testAmberAndCursorKeepOneFillInBothAppearancesAndGlassFollowsTheSystem() {
        for style in [HintLabelStyle.amber, .cursor, .ink] {
            XCTAssertEqual(style.palette(dark: false).fillTop, style.palette(dark: true).fillTop, "\(style)")
            XCTAssertEqual(style.palette(dark: false).text, style.palette(dark: true).text, "\(style)")
        }
        let light = HintLabelStyle.glass.palette(dark: false)
        let dark = HintLabelStyle.glass.palette(dark: true)
        XCTAssertGreaterThan(light.fillTop.relativeLuminance, 0.8)
        XCTAssertLessThan(dark.fillTop.relativeLuminance, 0.1)
        XCTAssertLessThan(light.fillAlpha, 1)
        XCTAssertLessThan(dark.fillAlpha, 1)
        // The ink pill is dark on dark in dark mode, so its outline turns light.
        XCTAssertGreaterThan(HintLabelStyle.ink.palette(dark: true).edge.relativeLuminance, 0.9)
        XCTAssertLessThan(HintLabelStyle.ink.palette(dark: false).edge.relativeLuminance, 0.1)
        // The cursor block is the icon's green, give or take the gradient.
        let block = HintLabelStyle.cursor.palette(dark: false)
        XCTAssertLessThan(block.fillBottom.relativeLuminance, ChromePalette.iconGreen.relativeLuminance)
        XCTAssertGreaterThan(block.fillTop.relativeLuminance, ChromePalette.iconGreen.relativeLuminance)
    }

    func testBodyIsSizedOnCapHeightAndTheFrameAddsTheMargin() {
        // SF Pro Rounded Bold 15: one capital is about 10pt wide and 10.6pt tall.
        let amber = HintLabelStyle.amber.spec
        XCTAssertEqual(
            HintLabelMetrics.bodySize(spec: amber, textWidth: 10, capHeight: 10.6),
            HintBadgeSize(width: 22, height: 21)
        )
        XCTAssertEqual(
            HintLabelMetrics.size(spec: amber, textWidth: 10, capHeight: 10.6),
            HintBadgeSize(width: 30, height: 29)
        )
        // A narrow letter does not make a body narrower than it is tall.
        XCTAssertEqual(HintLabelMetrics.bodySize(spec: amber, textWidth: 4, capHeight: 10.6).width, 21)
        // A capsule is never a circle: the caret needs a flat stretch of edge.
        let ink = HintLabelStyle.ink.spec
        let pill = HintLabelMetrics.bodySize(spec: ink, textWidth: 2, capHeight: 9.9)
        XCTAssertEqual(pill.height, 21)
        XCTAssertEqual(pill.width, 25)
        XCTAssertEqual(HintLabelMetrics.radius(spec: ink, bodyHeight: 21), 10.5)
        XCTAssertEqual(HintLabelMetrics.radius(spec: amber, bodyHeight: 21), 6)
        XCTAssertEqual(HintLabelMetrics.radius(spec: amber, bodyHeight: 8), 4)
        XCTAssertEqual(
            HintLabelMetrics.bodySize(spec: amber, textWidth: -3, capHeight: -1),
            HintBadgeSize(width: 12, height: 10)
        )
        // Every candidate's body is taller than classic's 20pt pill by at most 3pt,
        // while its capitals are 2 to 4pt larger.
        for style in HintLabelStyle.candidates {
            let spec = style.spec
            let body = HintLabelMetrics.bodySize(spec: spec, textWidth: 10, capHeight: spec.fontSize * 0.705)
            XCTAssertGreaterThanOrEqual(body.height, 20, "\(style)")
            XCTAssertLessThanOrEqual(body.height, 23, "\(style)")
        }
    }

    func testACornerPointerKeepsTheClassicFrame() {
        let element = HintRect(x: 300, y: 200, width: 120, height: 18)
        for style in [HintLabelStyle.classic, .amber, .cursor] {
            let box = HintGeometry.labelBox(
                element: element, badgeWidth: 30, badgeHeight: 29, spec: style.spec, screens: screens
            )
            let rect = HintGeometry.labelRect(element: element, badgeWidth: 30, badgeHeight: 29, screens: screens)
            XCTAssertEqual(box?.frame, rect, "\(style)")
            XCTAssertNil(box?.tipX, "\(style)")
            XCTAssertEqual(box?.tailDown, false, "\(style)")
        }
        XCTAssertNil(HintGeometry.labelBox(
            element: element, badgeWidth: 30, badgeHeight: 29, spec: HintLabelStyle.amber.spec, screens: []
        ))
    }

    func testACaretTouchesTheMiddleOfANarrowTargetAndTheLabelHangsBelow() {
        let spec = HintLabelStyle.ink.spec
        // A 28pt toolbar button.
        let button = HintRect(x: 100, y: 40, width: 28, height: 28)
        guard let box = HintGeometry.labelBox(
            element: button, badgeWidth: 37, badgeHeight: 33, spec: spec, screens: screens
        ) else {
            return XCTFail("expected a label")
        }
        XCTAssertEqual(box.tipX, 114)
        XCTAssertFalse(box.tailDown)
        XCTAssertEqual(box.frame.x + box.frame.width / 2, 114, accuracy: 0.001)
        // The tip is 4pt inside the bottom edge: y = 64 from the top.
        let frameTop = 900 - (box.frame.y + box.frame.height)
        let tipY = frameTop + spec.margin - HintLabelMetrics.caretHeight
        XCTAssertEqual(tipY, 64, accuracy: 0.001)
        // The body starts below the tip, so the button's icon stays visible.
        XCTAssertEqual(frameTop + spec.margin, 69, accuracy: 0.001)
    }

    func testACaretLeadsAWideTargetAndStaysInsideATallRow() {
        let spec = HintLabelStyle.glass.spec
        let link = HintRect(x: 200, y: 300, width: 180, height: 17)
        let row = HintRect(x: 0, y: 100, width: 260, height: 64)
        guard let onLink = HintGeometry.labelBox(
            element: link, badgeWidth: 40, badgeHeight: 34, spec: spec, screens: screens
        ), let onRow = HintGeometry.labelBox(
            element: row, badgeWidth: 40, badgeHeight: 34, spec: spec, screens: screens
        ) else {
            return XCTFail("expected both labels")
        }
        XCTAssertEqual(onLink.tipX, 224)
        XCTAssertEqual(onRow.tipX, 24)
        let linkTip = 900 - (onLink.frame.y + onLink.frame.height) + spec.margin - HintLabelMetrics.caretHeight
        XCTAssertEqual(linkTip, 300 + 13, accuracy: 0.001)
        let rowTop = 900 - (onRow.frame.y + onRow.frame.height)
        XCTAssertEqual(rowTop + spec.margin - HintLabelMetrics.caretHeight, 128, accuracy: 0.001)
        // Body: 6pt margin, 22pt tall. It ends inside the 64pt row.
        let bodyBottom = rowTop + 34 - spec.margin
        XCTAssertLessThanOrEqual(bodyBottom, row.y + row.height)
        XCTAssertEqual(onRow.frame.x, 4, accuracy: 0.001)
        XCTAssertFalse(onRow.tailDown)
        // A small target at the screen's left edge: the frame is pushed in
        // until the body is 2pt from the edge, and the tip stays on the target.
        let corner = HintGeometry.labelBox(
            element: HintRect(x: 0, y: 100, width: 10, height: 10),
            badgeWidth: 40, badgeHeight: 34, spec: spec, screens: screens
        )
        XCTAssertEqual(corner?.tipX, 5)
        XCTAssertEqual(corner?.frame.x ?? 0, -spec.margin + 2, accuracy: 0.001)
    }

    func testACaretLabelGoesAboveATargetAtTheBottomOfItsScreen() {
        let spec = HintLabelStyle.ink.spec
        let dock = HintRect(x: 700, y: 870, width: 40, height: 28)
        guard let box = HintGeometry.labelBox(
            element: dock, badgeWidth: 37, badgeHeight: 33, spec: spec, screens: screens
        ) else {
            return XCTFail("expected a label")
        }
        XCTAssertTrue(box.tailDown)
        // Mirror of the hanging case: the tip is 4pt inside the top edge.
        let frameBottom = 900 - box.frame.y
        XCTAssertEqual(frameBottom - spec.margin + HintLabelMetrics.caretHeight, 874, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(box.frame.y, 0)
        XCTAssertEqual(box.tipX, 720)

        // On the second screen, which is shorter and left of the primary.
        // Its bottom edge is level with the primary's, so it ends at y = 900 too.
        let far = HintRect(x: -12, y: 880, width: 10, height: 18)
        guard let edge = HintGeometry.labelBox(
            element: far, badgeWidth: 37, badgeHeight: 33, spec: spec, screens: screens
        ) else {
            return XCTFail("expected a label on the second screen")
        }
        XCTAssertTrue(edge.tailDown)
        XCTAssertEqual(edge.tipX, -7)
        XCTAssertEqual(edge.frame.x + edge.frame.width, spec.margin - 2, accuracy: 0.001)

        // A target that fills the screen cannot be cleared either way; it stays below.
        let whole = HintRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(HintGeometry.labelBox(
            element: whole, badgeWidth: 37, badgeHeight: 33, spec: spec, screens: screens
        )?.tailDown, false)
        XCTAssertNil(HintGeometry.labelBox(
            element: HintRect(x: 0, y: 0, width: 0, height: 10),
            badgeWidth: 37, badgeHeight: 33, spec: spec, screens: screens
        ))
        XCTAssertNil(HintGeometry.labelBox(
            element: dock, badgeWidth: 0, badgeHeight: 33, spec: spec, screens: screens
        ))
    }

    func testMarginsMayOverlapButBodiesAreMovedApart() {
        // Two 30 by 29 frames with a 4pt margin: bodies are 22 by 21.
        let first = HintRect(x: 0, y: 0, width: 30, height: 29)
        let marginsOnly = HintRect(x: 24, y: 0, width: 30, height: 29)
        let bodies = HintRect(x: 12, y: 0, width: 30, height: 29)
        XCTAssertEqual(HintGeometry.nudge([first, marginsOnly], slack: 5.5), [first, marginsOnly])
        XCTAssertNotEqual(HintGeometry.nudge([first, marginsOnly]), [first, marginsOnly])
        let moved = HintGeometry.nudge([first, bodies], slack: 5.5)
        XCTAssertEqual(moved[0], first)
        // The second core starts 2pt after the first core ends.
        XCTAssertEqual(moved[1].x + 5.5, first.x + first.width - 5.5 + 2, accuracy: 0.001)
        XCTAssertEqual(moved[1].y, bodies.y)
        XCTAssertEqual(moved[1].width, bodies.width)
        XCTAssertEqual(HintGeometry.nudge([first, bodies], slack: 0), HintGeometry.nudge([first, bodies]))
        // A frame too small to shrink is compared whole.
        let tiny = HintRect(x: 2, y: 2, width: 6, height: 6)
        XCTAssertEqual(HintGeometry.nudge([first, tiny], slack: 5.5).count, 2)
    }

    func testClassicArrangementIsTheOldPipeline() {
        let markers = sampleMarkers()
        let size = HintBadgeSize(width: 32, height: 28)
        let arrangement = HintOverlayLayout.arrange(
            markers: markers, style: .classic, screens: screens
        ) { _ in size }
        var expected: [HintRect] = []
        for marker in markers {
            let element = HintRect(
                x: marker.anchor.x, y: marker.anchor.y,
                width: marker.elementWidth, height: marker.elementHeight
            )
            if let rect = HintGeometry.labelRect(
                element: element, badgeWidth: size.width, badgeHeight: size.height, screens: screens
            ) {
                expected.append(rect)
            }
        }
        XCTAssertEqual(arrangement.labels.map(\.placed), expected)
        XCTAssertEqual(arrangement.labels.map(\.box.frame), HintGeometry.nudge(expected))
        XCTAssertEqual(arrangement.panels, HintGeometry.panels(labels: HintGeometry.nudge(expected), screens: screens))
        XCTAssertEqual(arrangement.labels.map(\.text), ["F", "J", "D", "K"])
        XCTAssertEqual(arrangement.labels.map(\.markerIndex), [0, 1, 2, 4])
        XCTAssertTrue(arrangement.labels.allSatisfy { $0.box.tipX == nil })
        // The second target starts inside the first one's label, so it was moved.
        XCTAssertNotEqual(arrangement.labels[1].placed, arrangement.labels[1].box.frame)
    }

    func testCandidateArrangementKeepsEachCaretOnItsOwnTarget() {
        let markers = sampleMarkers()
        let arrangement = HintOverlayLayout.arrange(
            markers: markers, style: .ink, screens: screens
        ) { text in
            HintBadgeSize(width: text.count == 1 ? 37 : 46, height: 33)
        }
        XCTAssertEqual(arrangement.labels.count, 4)
        XCTAssertEqual(arrangement.labels.map(\.box.tipX), [107, 121, 624, -90])
        XCTAssertEqual(arrangement.panels.map(\.screenIndex), [0, 1])
        let panelItems = arrangement.panels.flatMap(\.items)
        XCTAssertEqual(Set(panelItems.map(\.sourceIndex)), [0, 1, 2, 3])
        // The two neighbours' bodies collide, so the second moved right; its
        // tip did not, and still lies under its own target.
        XCTAssertGreaterThan(arrangement.labels[1].box.frame.x, arrangement.labels[1].placed.x)
        XCTAssertEqual(arrangement.labels[0].box.frame, arrangement.labels[0].placed)

        let none = HintOverlayLayout.arrange(markers: [], style: .glass, screens: screens) { _ in
            HintBadgeSize(width: 1, height: 1)
        }
        XCTAssertEqual(none, HintOverlayArrangement(labels: [], panels: []))
    }

    func testACaretLabelRestsOnItsOwnRowWhenTheNextRowIsUnderIt() {
        // Six links 17pt high, one every 22pt, as in a sidebar list.
        let rows = (0..<6).map { index in
            HintMarker(
                index: index,
                text: "Z\(index)",
                anchor: HintPoint(x: 500, y: 200 + Double(index) * 22),
                elementWidth: 180,
                elementHeight: 17
            )
        }
        let spec = HintLabelStyle.ink.spec
        let arrangement = HintOverlayLayout.arrange(markers: rows, style: .ink, screens: screens) { _ in
            HintBadgeSize(width: 46, height: 33)
        }
        XCTAssertEqual(arrangement.labels.count, 6)
        for index in 0..<5 {
            let label = arrangement.labels[index]
            XCTAssertNil(label.box.tipX, "row \(index) has the next row under it")
            XCTAssertFalse(label.box.tailDown)
            // The 21pt body is centred on the 17pt row, 2pt inside its left edge.
            let bodyTop = 900 - (label.box.frame.y + label.box.frame.height) + spec.margin
            XCTAssertEqual(bodyTop, label.element.y - 2, accuracy: 0.001)
            XCTAssertEqual(label.box.frame.x + spec.margin, 502, accuracy: 0.001)
            XCTAssertEqual(label.box.frame, label.placed, "22pt rows leave room for 21pt bodies")
        }
        // Nothing is under the last row, so its label hangs there on a caret.
        let last = arrangement.labels[5]
        XCTAssertEqual(last.box.tipX, 524)
        let lastBodyTop = 900 - (last.box.frame.y + last.box.frame.height) + spec.margin
        XCTAssertGreaterThan(lastBodyTop, last.element.y + last.element.height)

        // The corner styles lie on the row whatever is under it.
        let corner = HintOverlayLayout.arrange(markers: rows, style: .amber, screens: screens) { _ in
            HintBadgeSize(width: 40, height: 29)
        }
        XCTAssertEqual(corner.labels.map(\.box.frame.x), Array(repeating: 500, count: 6))
        XCTAssertEqual(corner.labels.compactMap(\.box.tipX), [])
    }

    func testLabelsLeftAfterAKeyStayWhereTheWholePassPutThem() {
        let first = HintMarker(
            index: 0, text: "ZF", anchor: HintPoint(x: 500, y: 200), elementWidth: 180, elementHeight: 17
        )
        let second = HintMarker(
            index: 1, text: "J", anchor: HintPoint(x: 500, y: 222), elementWidth: 180, elementHeight: 17
        )
        let size: (String) -> HintBadgeSize = { _ in HintBadgeSize(width: 46, height: 33) }
        let whole = HintOverlayLayout.arrange(markers: [first, second], style: .glass, screens: screens, size: size)
        let pass = [first, second].map(HintOverlayLayout.element(of:))
        XCTAssertEqual(pass[1], HintRect(x: 500, y: 222, width: 180, height: 17))

        // "z" was typed: only the first label is left. With the pass's
        // targets it stays on its row; without them it would drop under it.
        let kept = HintOverlayLayout.arrange(
            markers: [first], style: .glass, screens: screens, neighbours: pass, size: size
        )
        XCTAssertEqual(kept.labels.first?.box, whole.labels.first?.box)
        XCTAssertNil(kept.labels.first?.box.tipX)
        let alone = HintOverlayLayout.arrange(markers: [first], style: .glass, screens: screens, size: size)
        XCTAssertEqual(alone.labels.first?.box.tipX, 524)

        // Classic does not look at neighbours.
        let classic = HintOverlayLayout.arrange(markers: [first], style: .classic, screens: screens, size: size)
        let classicWithPass = HintOverlayLayout.arrange(
            markers: [first], style: .classic, screens: screens, neighbours: pass, size: size
        )
        XCTAssertEqual(classic, classicWithPass)
    }

    func testThePlaceUnderATargetIsTakenOnlyByAnotherTargetThatDoesNotHoldIt() {
        let spec = HintLabelStyle.ink.spec
        let button = HintRect(x: 100, y: 40, width: 28, height: 28)
        guard let box = HintGeometry.labelBox(
            element: button, badgeWidth: 37, badgeHeight: 33, spec: spec, screens: screens
        ) else {
            return XCTFail("expected a label")
        }
        // The body is x 101.5...126.5, y 69...90 from the top.
        func crowded(_ neighbours: [HintRect]) -> Bool {
            HintGeometry.isCrowded(
                frame: box.frame, element: button, neighbours: neighbours, spec: spec, screens: screens
            )
        }
        XCTAssertFalse(crowded([]))
        XCTAssertFalse(crowded([button]), "the target itself")
        XCTAssertFalse(crowded([HintRect(x: 134, y: 40, width: 28, height: 28)]), "the next button in the bar")
        XCTAssertFalse(crowded([HintRect(x: 0, y: 30, width: 600, height: 80)]), "the bar that holds the button")
        XCTAssertFalse(crowded([HintRect(x: 90, y: 87, width: 60, height: 20)]), "3pt into the body")
        XCTAssertTrue(crowded([HintRect(x: 90, y: 86, width: 60, height: 20)]), "4pt into the body")
        XCTAssertTrue(crowded([HintRect(x: 0, y: 75, width: 600, height: 40)]), "a field under the bar")
        XCTAssertFalse(HintGeometry.isCrowded(
            frame: box.frame, element: button,
            neighbours: [HintRect(x: 0, y: 75, width: 600, height: 40)], spec: spec, screens: []
        ))
    }

    func testARestingLabelIsCentredOnAShortTargetAndAtTheTopOfATallOne() {
        let spec = HintLabelStyle.glass.spec
        func rest(_ element: HintRect) -> HintLabelBox? {
            HintGeometry.restingBox(
                element: element, badgeWidth: 50, badgeHeight: 34, spec: spec, screens: screens
            )
        }
        func bodyTop(_ box: HintLabelBox) -> Double {
            900 - (box.frame.y + box.frame.height) + spec.margin
        }
        // Body 22pt. A 28pt tab is within 8pt of it: centred.
        guard let tab = rest(HintRect(x: 88, y: 5, width: 172, height: 28)) else {
            return XCTFail("expected a label")
        }
        XCTAssertNil(tab.tipX)
        XCTAssertEqual(bodyTop(tab), 8, accuracy: 0.001)
        XCTAssertEqual(tab.frame.x + spec.margin, 90, accuracy: 0.001)
        XCTAssertEqual(tab.frame.width, 50)
        XCTAssertEqual(tab.frame.height, 34)
        // A 62pt row is not: 2pt below its top edge.
        guard let row = rest(HintRect(x: 56, y: 114, width: 230, height: 62)) else {
            return XCTFail("expected a label")
        }
        XCTAssertEqual(bodyTop(row), 116, accuracy: 0.001)
        // At the left edge of a screen the body stays 2pt inside it.
        guard let edge = rest(HintRect(x: -1280, y: 300, width: 40, height: 20)) else {
            return XCTFail("expected a label")
        }
        XCTAssertEqual(edge.frame.x + spec.margin, -1278, accuracy: 0.001)
        XCTAssertNil(rest(HintRect(x: 0, y: 0, width: 0, height: 10)))
        XCTAssertNil(HintGeometry.restingBox(
            element: HintRect(x: 0, y: 0, width: 10, height: 10),
            badgeWidth: 50, badgeHeight: 34, spec: spec, screens: []
        ))
        XCTAssertNil(HintGeometry.restingBox(
            element: HintRect(x: 0, y: 0, width: 10, height: 10),
            badgeWidth: 0, badgeHeight: 34, spec: spec, screens: screens
        ))
    }

    private func sampleMarkers() -> [HintMarker] {
        [
            HintMarker(index: 0, text: "F", anchor: HintPoint(x: 100, y: 40), elementWidth: 14, elementHeight: 14),
            HintMarker(index: 1, text: "J", anchor: HintPoint(x: 114, y: 40), elementWidth: 14, elementHeight: 14),
            HintMarker(index: 2, text: "D", anchor: HintPoint(x: 600, y: 300), elementWidth: 200, elementHeight: 17),
            HintMarker(index: 3, text: "S", anchor: HintPoint(x: 10, y: 10), elementWidth: 0, elementHeight: 0),
            HintMarker(index: 4, text: "K", anchor: HintPoint(x: -100, y: 500), elementWidth: 20, elementHeight: 20),
        ]
    }
}

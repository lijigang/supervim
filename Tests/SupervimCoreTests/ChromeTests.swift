import XCTest
@testable import SupervimCore

/// Visual rules that do not draw: label highlighting, contrast, help placement,
/// menu symbols, and which display a floating sheet belongs on.
final class ChromeTests: XCTestCase {
    func testMatchedPrefixKeepsDisplayCasingAndLeavesTheRest() {
        XCTAssertEqual(
            HintLabelHighlight.split(label: "SA", typedPrefix: "s"),
            HintLabelSplit(matched: "S", remainder: "A")
        )
        XCTAssertEqual(
            HintLabelHighlight.split(label: "SA", typedPrefix: "SA"),
            HintLabelSplit(matched: "SA", remainder: "")
        )
        XCTAssertEqual(
            HintLabelHighlight.split(label: "F", typedPrefix: ""),
            HintLabelSplit(matched: "", remainder: "F")
        )
        XCTAssertEqual(
            HintLabelHighlight.split(label: "BA", typedPrefix: "z"),
            HintLabelSplit(matched: "", remainder: "BA")
        )
        XCTAssertEqual(
            HintLabelHighlight.split(label: "F", typedPrefix: "ff"),
            HintLabelSplit(matched: "", remainder: "F")
        )
        XCTAssertEqual(
            HintLabelHighlight.split(label: "GG", typedPrefix: "g"),
            HintLabelSplit(matched: "G", remainder: "G")
        )
    }

    func testBadgeSizeIncludesTheCursorPaddingAndShadowMargin() {
        let size = HintBadgeMetrics.size(textWidth: 14, textHeight: 12)
        XCTAssertEqual(size, HintBadgeSize(width: 39, height: 25))
        // One SF Mono 12 letter is about 7.2pt wide and 14.5pt tall. The pill
        // around it stays under 24 by 20, so it covers little of its target.
        let letter = HintBadgeMetrics.size(textWidth: 7.3, textHeight: 14.5)
        XCTAssertLessThanOrEqual(letter.width - HintBadgeMetrics.shadowMargin * 2, 24)
        XCTAssertLessThanOrEqual(letter.height - HintBadgeMetrics.shadowMargin * 2, 20)
        XCTAssertGreaterThanOrEqual(HintBadgeMetrics.cursorWidth, 2)
        XCTAssertLessThan(HintBadgeMetrics.cursorHeight, 14.5)
        let empty = HintBadgeMetrics.size(textWidth: 0, textHeight: 0)
        XCTAssertGreaterThanOrEqual(empty.height, HintBadgeMetrics.minimumHeight)
        XCTAssertGreaterThan(empty.width, HintBadgeMetrics.shadowMargin * 2)
    }

    func testLabelTextClearsContrastOnLightAndDarkFillsOverLoudBackdrops() {
        for dark in [false, true] {
            for surface in ChromePalette.surfaces(dark: dark) {
                let text = surface.text.contrastRatio(against: surface.fill)
                let matched = surface.matched.contrastRatio(against: surface.fill)
                XCTAssertGreaterThanOrEqual(
                    text,
                    ChromePalette.minimumTextContrast,
                    "text \(text) dark=\(dark) fill=\(surface.fill)"
                )
                XCTAssertGreaterThanOrEqual(
                    matched,
                    ChromePalette.minimumTextContrast,
                    "matched \(matched) dark=\(dark) fill=\(surface.fill)"
                )
            }
        }
        for dark in [false, true] {
            // The hairline has to show on the fill and on a page of the same gray.
            let fill = dark ? ChromePalette.darkFill : ChromePalette.lightFill
            let stroke = dark ? ChromePalette.darkStroke : ChromePalette.lightStroke
            let alpha = dark ? ChromePalette.darkHairlineAlpha : ChromePalette.lightHairlineAlpha
            let edge = stroke.composited(over: fill, alpha: alpha)
            XCTAssertGreaterThanOrEqual(edge.contrastRatio(against: fill), 1.25, "dark=\(dark)")
            XCTAssertLessThanOrEqual(edge.contrastRatio(against: fill), 2.2, "dark=\(dark)")
        }
        XCTAssertEqual(ChromePalette.iconGreen, ChromeColor(hex: 0x34C759))
        XCTAssertEqual(ChromePalette.lightFill, ChromeColor(hex: 0xF7F7F8))
        XCTAssertNotEqual(ChromePalette.lightMatched, ChromePalette.iconGreen)
    }

    func testReduceMotionDropsTheAppearFade() {
        XCTAssertEqual(ChromeMotion.appearDuration(reduceMotion: false), 0.14)
        XCTAssertEqual(ChromeMotion.appearDuration(reduceMotion: true), 0)
        // Labels answer a key. Their fade is short enough not to read as a wait.
        XCTAssertEqual(ChromeMotion.hintAppearDuration(reduceMotion: false), 0.05)
        XCTAssertEqual(ChromeMotion.hintAppearDuration(reduceMotion: true), 0)
        XCTAssertLessThan(ChromeMotion.hintAppearDuration, ChromeMotion.appearDuration)
    }

    func testStatusGlyphFollowsTheMenuTitleAndHintStaysNormal() {
        XCTAssertEqual(MenuBarGlyphKind(statusTitle: "Normal"), .normal)
        XCTAssertEqual(MenuBarGlyphKind(statusTitle: "Insert"), .insert)
        XCTAssertEqual(MenuBarGlyphKind(statusTitle: "Paused"), .paused)
        XCTAssertEqual(MenuBarGlyphKind(statusTitle: "没找到可点击元素"), .other)
        XCTAssertEqual(MenuBarGlyphKind(statusTitle: "Visual"), .other)
    }

    func testMenuSymbolsKeepSnapshotOrderAndInsertPermissionsBeforeTheSeparator() {
        let snapshot = MenuBarSnapshot(
            statusTitle: "Normal",
            commands: [
                MenuCommand(kind: .pause, title: "Pause", enabled: true),
                MenuCommand(kind: .resume, title: "Resume", enabled: false),
                MenuCommand(kind: .settings, title: "Settings", enabled: true),
                MenuCommand(kind: .separator, title: "", enabled: false),
                MenuCommand(kind: .quit, title: "Quit Supervim", enabled: true),
            ]
        )
        let plain = MenuChrome.items(snapshot: snapshot, permissionsTitle: nil)
        XCTAssertEqual(plain.map(\.title), ["Pause", "Resume", "Settings", "", "Quit Supervim"])
        XCTAssertEqual(plain.map(\.symbolName), ["pause.fill", "play.fill", "gearshape", nil, "power"])
        XCTAssertEqual(plain.map(\.enabled), [true, false, true, false, true])
        XCTAssertEqual(plain.map(\.keyEquivalent), ["", "", "", "", "q"])
        XCTAssertEqual(plain.filter(\.isSeparator).count, 1)

        let withPermissions = MenuChrome.items(snapshot: snapshot, permissionsTitle: "Permissions")
        XCTAssertEqual(
            withPermissions.map(\.title),
            ["Pause", "Resume", "Settings", "Permissions", "", "Quit Supervim"]
        )
        XCTAssertEqual(withPermissions[3].symbolName, MenuChrome.permissionsSymbolName)
        XCTAssertTrue(withPermissions[3].isPermissions)
        XCTAssertNil(withPermissions[3].kind)
        XCTAssertTrue(MenuChrome.items(snapshot: snapshot, permissionsTitle: "").filter(\.isPermissions).isEmpty)
    }

    func testHelpGroupsEveryBindingOnceAndNotesOnlyTheExtraFacts() {
        let page = HelpPage(bindings: CommandMap().bindings)
        let sections = HelpChrome.sections(in: page)
        XCTAssertEqual(sections.map(\.title), HelpChrome.sectionOrder)
        let keys = sections.flatMap { $0.entries.map(\.keys) }
        XCTAssertEqual(keys.count, page.entries.count)
        XCTAssertEqual(Set(keys), Set(page.entries.map(\.keys)))
        let find = page.entries.first { $0.keys == "/" }
        XCTAssertEqual(
            find.map(HelpChrome.note(for:)),
            "Command+F · differs from Vimium"
        )
        let scroll = page.entries.first { $0.keys == "j" }
        XCTAssertEqual(scroll.map(HelpChrome.note(for:)), "")
        let copy = page.entries.first { $0.keys == "yy" }
        XCTAssertEqual(copy.map(HelpChrome.note(for:)), "Command+L, Command+C · Safari, Chromium")
        XCTAssertEqual(HelpChrome.sectionTitle(for: "gi"), "Modes")
        XCTAssertEqual(HelpChrome.columnIndex(for: "Scroll"), 0)
        XCTAssertEqual(HelpChrome.columnIndex(for: "Navigation"), 1)
    }

    func testHelpLayoutFitsTwoNonOverlappingColumns() {
        let layout = HelpChrome.layout(page: HelpPage(bindings: CommandMap().bindings))
        XCTAssertEqual(layout.width, HelpMetrics.sheetWidth)
        XCTAssertLessThan(layout.height, 560)
        XCTAssertGreaterThan(layout.height, 200)
        let rows = layout.sections.flatMap(\.rows)
        XCTAssertEqual(rows.map(\.keys).sorted(), CommandMap().bindings.map(\.keys).sorted())
        let left = rows.filter { $0.frame.x == HelpMetrics.margin }
        let right = rows.filter { $0.frame.x > HelpMetrics.margin + 40 }
        XCTAssertFalse(left.isEmpty)
        XCTAssertFalse(right.isEmpty)
        XCTAssertTrue(left.contains { $0.keys == "j" })
        XCTAssertTrue(right.contains { $0.keys == "H" })
        XCTAssertLessThan(left.map(\.frame.maxX).max() ?? 0, right.map(\.frame.x).min() ?? 0)
        assertNoVerticalOverlap(left.map(\.frame))
        assertNoVerticalOverlap(right.map(\.frame))
        for row in rows {
            XCTAssertLessThanOrEqual(row.frame.maxX, layout.width - HelpMetrics.margin + 0.001)
            XCTAssertLessThanOrEqual(row.frame.maxY, layout.height)
        }
    }

    func testHelpLayoutOfAnEmptyPageStaysAtTheMinimum() {
        let layout = HelpChrome.layout(page: HelpPage(bindings: []))
        XCTAssertEqual(layout.sections, [])
        XCTAssertEqual(layout.height, HelpMetrics.minimumHeight)
        XCTAssertEqual(layout.width, HelpMetrics.sheetWidth)
    }

    func testTypedPrefixIsExposedForHighlightingWithoutChangingMarkers() {
        var session = HintSession(targets: Array(tenChromeTargets().prefix(3)), click: .plain, alphabet: "ab")
        XCTAssertEqual(session.typedText, "")
        guard case .showing(let markers) = session.handle(.character("b")) else {
            return XCTFail("a shared prefix should keep the hint open")
        }
        XCTAssertEqual(session.typedText, "b")
        XCTAssertEqual(markers.map(\.text), ["BA", "BB"])
        for marker in markers {
            XCTAssertEqual(
                HintLabelHighlight.split(label: marker.text, typedPrefix: session.typedText).matched,
                "B"
            )
        }
        guard case .showing = session.handle(.backspace) else {
            return XCTFail("backspace should clear the prefix")
        }
        XCTAssertEqual(session.typedText, "")
    }

    func testOverlayScreenPicksTheDisplayUnderThePoint() {
        let screens = [
            DisplayFrame(x: 0, y: 0, width: 1440, height: 900, backingScale: 2),
            DisplayFrame(x: -1200, y: -200, width: 1200, height: 800, backingScale: 2),
            DisplayFrame(x: 1440, y: 0, width: 1920, height: 1080, backingScale: 1),
        ]
        XCTAssertEqual(OverlayScreen.index(containingX: 10, y: 10, screens: screens), 0)
        XCTAssertEqual(OverlayScreen.index(containingX: -10, y: 100, screens: screens), 1)
        XCTAssertEqual(OverlayScreen.index(containingX: 1500, y: 40, screens: screens), 2)
        XCTAssertNil(OverlayScreen.index(containingX: 10, y: 2000, screens: screens))
        XCTAssertNil(OverlayScreen.index(containingX: 10, y: 10, screens: [
            DisplayFrame(x: 0, y: 0, width: 0, height: 100, backingScale: 2),
        ]))
        XCTAssertEqual(OverlayScreen.index(containingX: 1439.9, y: 899.9, screens: screens), 0)
        XCTAssertEqual(OverlayScreen.index(containingX: 1440, y: 10, screens: screens), 2)
    }

    private func assertNoVerticalOverlap(_ frames: [HelpFrame], file: StaticString = #filePath, line: UInt = #line) {
        let sorted = frames.sorted { $0.y < $1.y }
        for pair in zip(sorted, sorted.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.maxY, pair.1.y + 0.001, file: file, line: line)
        }
    }
}

private func tenChromeTargets() -> [HintTarget] {
    (0..<10).map { index in
        HintTarget(
            frame: HintRect(x: Double(index) * 30, y: 0, width: 20, height: 10),
            identifier: String(index)
        )
    }
}

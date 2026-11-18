import XCTest
@testable import SupervimCore

/// Vision boxes stay on device. These tests only convert and merge rectangles.
final class VisionHintGeometryTests: XCTestCase {
    func testNormalizedBottomLeftBecomesScreenPointsOnTheLeftDisplay() {
        let image = CapturedWindow(
            pixelWidth: 800,
            pixelHeight: 600,
            frame: HintRect(x: -1920, y: 100, width: 800, height: 600),
            backingScale: 1
        )
        let line = HintRect(x: 0.1, y: 0.9, width: 0.4, height: 0.05)
        let screen = VisionHintGeometry.screenRect(normalized: line, image: image)
        XCTAssertEqual(screen, HintRect(x: -1840, y: 130, width: 320, height: 30))
    }

    func testRetinaScaleDividesPixelsAndDoesNotUseThePrimaryScale() {
        let image = CapturedWindow(
            pixelWidth: 800,
            pixelHeight: 600,
            frame: HintRect(x: 100, y: 50, width: 400, height: 300),
            backingScale: 2
        )
        let line = HintRect(x: 0.1, y: 0.9, width: 0.4, height: 0.05)
        XCTAssertEqual(
            VisionHintGeometry.screenRect(normalized: line, image: image),
            HintRect(x: 140, y: 65, width: 160, height: 15)
        )
    }

    func testConversationLinesMergeIntoRowsAndOverlapsDrop() {
        let rows = VisionHintGeometry.mergeRows([
            HintRect(x: 80, y: 100, width: 200, height: 18),
            HintRect(x: 300, y: 100, width: 40, height: 14),
            HintRect(x: 80, y: 122, width: 220, height: 16),
            HintRect(x: 80, y: 180, width: 200, height: 18),
            HintRect(x: 300, y: 180, width: 40, height: 14),
            HintRect(x: 80, y: 202, width: 220, height: 16),
        ])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].y, 100)
        XCTAssertEqual(rows[0].x, 80)
        XCTAssertEqual(rows[1].y, 180)

        let deduped = VisionHintGeometry.dedupe([
            HintRect(x: 0, y: 0, width: 100, height: 40),
            HintRect(x: 10, y: 4, width: 30, height: 20),
            HintRect(x: 200, y: 0, width: 20, height: 20),
        ])
        XCTAssertEqual(deduped.count, 2)
        XCTAssertTrue(deduped.contains(HintRect(x: 200, y: 0, width: 20, height: 20)))
    }

    func testTargetsKeepSingleLettersAndRankButtonsAheadOfRows() {
        let image = CapturedWindow(
            pixelWidth: 200,
            pixelHeight: 100,
            frame: HintRect(x: 0, y: 0, width: 200, height: 100),
            backingScale: 1
        )
        let boxes = [
            VisionBox(text: "Ada", normalized: HintRect(x: 0.1, y: 0.7, width: 0.4, height: 0.1), kind: .text),
            VisionBox(text: "hello", normalized: HintRect(x: 0.1, y: 0.58, width: 0.5, height: 0.1), kind: .text),
            VisionBox(text: "", normalized: HintRect(x: 0.8, y: 0.1, width: 0.1, height: 0.15), kind: .rectangle),
        ]
        let targets = VisionHintGeometry.targets(boxes: boxes, image: image)
        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[0].identifier, "vision/1")
        let session = HintSession(targets: targets, click: .plain)
        XCTAssertEqual(session.markers.map(\.text), ["F", "J"])
        XCTAssertEqual(
            VisionHintGeometry.logLine(permission: "granted", pixelWidth: 800, pixelHeight: 600, boxes: 12, hits: 4),
            "vision permission=granted image=800x600 boxes=12 hits=4"
        )
    }

    func testVisionRunsWhenTheTreeIsEmptyOrTheAppIsListed() {
        XCTAssertTrue(VisionHintPolicy.shouldCapture(
            axHitCount: 0,
            bundleIdentifier: "com.apple.Safari",
            visionBundles: ["com.tencent.xinWeChat"]
        ))
        XCTAssertFalse(VisionHintPolicy.shouldCapture(
            axHitCount: 3,
            bundleIdentifier: "com.apple.Safari",
            visionBundles: ["com.tencent.xinWeChat"]
        ))
        XCTAssertTrue(VisionHintPolicy.shouldCapture(
            axHitCount: 3,
            bundleIdentifier: "com.tencent.xinWeChat",
            visionBundles: ["com.tencent.xinWeChat"]
        ))
    }

    /// Text recognition time grows with the pixel count. A Retina screenshot
    /// of a large window is four times the pixels of the same window at 1x,
    /// and the text in it is far larger than recognition needs.
    func testCaptureScaleCapsTheLongSideAndNeverGoesBelowOnePixelPerPoint() {
        // A small window is captured at the screen's own scale.
        XCTAssertEqual(VisionCaptureSizing.scale(width: 900, height: 700, backingScale: 2), 2)
        // 1440 x 900 at 2x would be 2880 wide. The long side is capped.
        let large = VisionCaptureSizing.scale(width: 1440, height: 900, backingScale: 2)
        XCTAssertEqual(large * 1440, VisionCaptureSizing.maximumLongSide, accuracy: 0.001)
        XCTAssertLessThan(large, 2)
        XCTAssertGreaterThan(large, 1)
        // A tall window is capped by its height.
        let tall = VisionCaptureSizing.scale(width: 800, height: 1400, backingScale: 2)
        XCTAssertEqual(tall * 1400, VisionCaptureSizing.maximumLongSide, accuracy: 0.001)
        // A window wider than the cap is still captured at one pixel per point.
        XCTAssertEqual(VisionCaptureSizing.scale(width: 3000, height: 1200, backingScale: 2), 1)
        XCTAssertEqual(VisionCaptureSizing.scale(width: 3000, height: 1200, backingScale: 1), 1)
        // Nonsense in, the screen's scale out.
        XCTAssertEqual(VisionCaptureSizing.scale(width: 0, height: 0, backingScale: 2), 2)
        XCTAssertEqual(VisionCaptureSizing.scale(width: 900, height: 700, backingScale: 0), 1)
        XCTAssertEqual(VisionCaptureSizing.scale(width: .nan, height: 700, backingScale: 2), 2)

        let pixels = VisionCaptureSizing.pixelSize(width: 1440, height: 900, backingScale: 2)
        XCTAssertEqual(pixels.width, Int(VisionCaptureSizing.maximumLongSide))
        XCTAssertEqual(pixels.height, 1375)
        XCTAssertLessThan(
            Double(pixels.width * pixels.height),
            Double(2880 * 1800) * 0.6,
            "the capped capture has well under two thirds of the pixels"
        )
    }
}

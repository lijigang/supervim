#if canImport(AppKit)
import AppKit
import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// The label the overlay draws is option A: yellow in light and in dark
/// appearance, with typed letters faded. These tests draw the real views
/// into a bitmap and read pixels back.
final class HintLabelRenderingTests: XCTestCase {
    private static let scale: CGFloat = 2

    @MainActor
    func testTheBadgeViewDrawsTheShippedYellowLabelInBothAppearances() throws {
        let view = HintBadgeView(label: "F", typedPrefix: "")
        plainSettings(view)
        XCTAssertEqual(view.style, .amber)
        XCTAssertEqual(view.style, HintLabelStyle.shipped)
        let margin = CGFloat(HintLabelStyle.shipped.spec.margin)
        let body = view.bounds.insetBy(dx: margin, dy: margin)
        XCTAssertGreaterThanOrEqual(body.height, 21)
        XCTAssertGreaterThanOrEqual(body.width, body.height)

        var fills: [Pixel] = []
        for dark in [false, true] {
            let image = try render(view, dark: dark)
            // Right of the letter, inside the edge and the highlight.
            let fill = image.pixel(x: body.maxX - 3, y: body.midY)
            XCTAssertGreaterThan(fill.alpha, 0.98, "dark=\(dark)")
            XCTAssertGreaterThan(fill.red, 0.9, "dark=\(dark)")
            XCTAssertGreaterThan(fill.green, 0.7, "dark=\(dark)")
            XCTAssertLessThan(fill.green, 0.95, "dark=\(dark)")
            XCTAssertLessThan(fill.blue, 0.5, "dark=\(dark)")
            // The letter is near-black on it.
            XCTAssertLessThan(image.darkest(in: body.insetBy(dx: 3, dy: 4)), 0.25, "dark=\(dark)")
            fills.append(fill)
        }
        XCTAssertEqual(fills[0].red, fills[1].red, accuracy: 0.02)
        XCTAssertEqual(fills[0].green, fills[1].green, accuracy: 0.02)
        XCTAssertEqual(fills[0].blue, fills[1].blue, accuracy: 0.02)
    }

    @MainActor
    func testATypedLetterFadesAndTheLetterStillToTypeDoesNotChange() throws {
        let plain = HintBadgeView(label: "ZF", typedPrefix: "")
        let typed = HintBadgeView(label: "ZF", typedPrefix: "z")
        plainSettings(plain)
        plainSettings(typed)
        XCTAssertEqual(plain.bounds.size, typed.bounds.size, "typing must not resize a label")
        let spec = HintLabelStyle.shipped.spec
        let margin = CGFloat(spec.margin)
        let body = plain.bounds.insetBy(dx: margin, dy: margin)

        // Where the Z ends and the F begins, as the painter sets them.
        let font = StyledHintPainter.font(for: spec)
        let tracking = CGFloat(spec.tracking)
        func advance(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font, .kern: tracking]).width
        }
        let ink = advance("ZF") - tracking
        let boundary = body.midX - ink / 2 + advance("Z") - tracking / 2
        let left = NSRect(x: body.minX + 3, y: body.minY + 4, width: boundary - 1 - (body.minX + 3), height: body.height - 8)
        let right = NSRect(x: boundary + 1, y: body.minY + 4, width: body.maxX - 3 - (boundary + 1), height: body.height - 8)
        XCTAssertGreaterThan(left.width, 4)
        XCTAssertGreaterThan(right.width, 4)

        for dark in [false, true] {
            let before = try render(plain, dark: dark)
            let after = try render(typed, dark: dark)
            XCTAssertLessThan(before.darkest(in: left), 0.25, "Z before the key, dark=\(dark)")
            XCTAssertLessThan(before.darkest(in: right), 0.25, "F before the key, dark=\(dark)")
            XCTAssertGreaterThan(after.darkest(in: left), 0.35, "Z after the key is faded, dark=\(dark)")
            XCTAssertLessThan(after.darkest(in: right), 0.25, "F after the key, dark=\(dark)")
            // Still a letter: the faded Z is darker than the bare fill.
            XCTAssertLessThan(
                after.darkest(in: left),
                after.pixel(x: body.maxX - 3, y: body.midY).brightness - 0.08,
                "dark=\(dark)"
            )
            XCTAssertLessThan(before.largestDifference(from: after, in: right), 0.02, "dark=\(dark)")
            XCTAssertGreaterThan(before.largestDifference(from: after, in: left), 0.2, "dark=\(dark)")
        }
    }

    @MainActor
    func testOneCanvasRedrawsNewLabelsInTheShippedStyle() throws {
        let canvas = HintCanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        XCTAssertEqual(canvas.style, HintLabelStyle.shipped)
        let margin = CGFloat(HintLabelStyle.shipped.spec.margin)
        let oneSize = HintLabelRenderer.size(for: "F", style: .shipped)
        let twoSize = HintLabelRenderer.size(for: "ZF", style: .shipped)
        let one = NSRect(origin: NSPoint(x: 10, y: 20), size: oneSize)
        let two = NSRect(origin: NSPoint(x: 90, y: 20), size: twoSize)
        func fillPoint(_ frame: NSRect) -> NSPoint {
            NSPoint(x: frame.maxX - margin - 3, y: frame.midY)
        }

        canvas.replace(
            [HintCanvasView.Badge(label: "F", frame: one), HintCanvasView.Badge(label: "ZF", frame: two)],
            typedPrefix: ""
        )
        let all = try render(canvas, dark: false)
        for frame in [one, two] {
            let fill = all.pixel(x: fillPoint(frame).x, y: fillPoint(frame).y)
            XCTAssertGreaterThan(fill.red, 0.9)
            XCTAssertLessThan(fill.blue, 0.5)
            XCTAssertGreaterThan(fill.alpha, 0.98)
        }
        XCTAssertEqual(all.pixel(x: 70, y: 70).alpha, 0, accuracy: 0.01, "the canvas is clear between labels")

        // A key: the same canvas gets the labels that are left.
        canvas.replace([HintCanvasView.Badge(label: "ZF", frame: two)], typedPrefix: "z")
        let left = try render(canvas, dark: false)
        XCTAssertEqual(left.pixel(x: fillPoint(one).x, y: fillPoint(one).y).alpha, 0, accuracy: 0.01)
        XCTAssertGreaterThan(left.pixel(x: fillPoint(two).x, y: fillPoint(two).y).red, 0.9)
        XCTAssertGreaterThan(all.largestDifference(from: left, in: two.insetBy(dx: margin + 3, dy: margin + 4)), 0.2)

        canvas.replace([], typedPrefix: "")
        let none = try render(canvas, dark: false)
        XCTAssertEqual(none.pixel(x: fillPoint(two).x, y: fillPoint(two).y).alpha, 0, accuracy: 0.01)
    }

    /// The machine's accessibility display settings do not decide the test.
    @MainActor
    private func plainSettings(_ view: HintBadgeView) {
        view.forcesIncreaseContrast = false
        view.forcesDifferentiateWithoutColor = false
        view.forcesReduceTransparency = false
    }

    // MARK: Drawing

    private struct Pixel {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var alpha: CGFloat

        var brightness: CGFloat {
            0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
    }

    /// A drawn view. Points are the view's own, origin bottom-left.
    private struct Picture {
        let rep: NSBitmapImageRep
        let scale: CGFloat

        func pixel(x: CGFloat, y: CGFloat) -> Pixel {
            pixel(column: Int((x * scale).rounded(.down)), row: rep.pixelsHigh - 1 - Int((y * scale).rounded(.down)))
        }

        private func pixel(column: Int, row: Int) -> Pixel {
            let x = min(max(column, 0), rep.pixelsWide - 1)
            let y = min(max(row, 0), rep.pixelsHigh - 1)
            guard let color = rep.colorAt(x: x, y: y) else {
                return Pixel(red: 0, green: 0, blue: 0, alpha: 0)
            }
            return Pixel(
                red: color.redComponent,
                green: color.greenComponent,
                blue: color.blueComponent,
                alpha: color.alphaComponent
            )
        }

        private func pixels(in rect: NSRect) -> [(Int, Int)] {
            let firstColumn = Int((rect.minX * scale).rounded(.up))
            let lastColumn = Int((rect.maxX * scale).rounded(.down)) - 1
            let firstRow = rep.pixelsHigh - Int((rect.maxY * scale).rounded(.down))
            let lastRow = rep.pixelsHigh - 1 - Int((rect.minY * scale).rounded(.up))
            guard firstColumn <= lastColumn, firstRow <= lastRow else {
                return []
            }
            var all: [(Int, Int)] = []
            for row in firstRow...lastRow {
                for column in firstColumn...lastColumn {
                    all.append((column, row))
                }
            }
            return all
        }

        func darkest(in rect: NSRect) -> CGFloat {
            pixels(in: rect).map { pixel(column: $0.0, row: $0.1).brightness }.min() ?? 1
        }

        func largestDifference(from other: Picture, in rect: NSRect) -> CGFloat {
            var largest: CGFloat = 0
            for (column, row) in pixels(in: rect) {
                let mine = pixel(column: column, row: row)
                let theirs = other.pixel(column: column, row: row)
                largest = max(
                    largest,
                    abs(mine.red - theirs.red),
                    abs(mine.green - theirs.green),
                    abs(mine.blue - theirs.blue),
                    abs(mine.alpha - theirs.alpha)
                )
            }
            return largest
        }
    }

    /// Calls the view's own `draw` into a clear bitmap at 2x.
    @MainActor
    private func render(_ view: NSView, dark: Bool) throws -> Picture {
        let scale = Self.scale
        let appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
        view.appearance = appearance
        let bounds = view.bounds
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((bounds.width * scale).rounded(.up)),
            pixelsHigh: Int((bounds.height * scale).rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        let current = cg.ctm.a
        if current > 0, abs(current - scale) > 0.01 {
            cg.scaleBy(x: scale / current, y: scale / current)
        }
        appearance.performAsCurrentDrawingAppearance {
            view.draw(bounds)
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return Picture(rep: rep, scale: scale)
    }
}
#endif

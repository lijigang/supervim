#if canImport(AppKit)
import AppKit
import SupervimCore

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Something a hint pass would label. `frame` has its origin at the top-left
/// of the scene and y down, like an accessibility frame.
struct SceneTarget {
    var frame: NSRect
    var role: String?
    var subrole: String?
}

/// Colors of the mock windows for one appearance.
struct ScenePalette {
    let dark: Bool
    let chrome: NSColor
    let toolbar: NSColor
    let page: NSColor
    let raised: NSColor
    let field: NSColor
    let text: NSColor
    let secondary: NSColor
    let tertiary: NSColor
    let link: NSColor
    let separator: NSColor
    let accent: NSColor
    let selection: NSColor

    init(dark: Bool) {
        self.dark = dark
        chrome = dark ? rgb(0x2A2A2D) : rgb(0xE4E4E7)
        toolbar = dark ? rgb(0x38383B) : rgb(0xF6F6F7)
        page = dark ? rgb(0x1C1C1E) : rgb(0xFFFFFF)
        raised = dark ? rgb(0x2C2C2E) : rgb(0xF2F2F5)
        field = dark ? rgb(0x1F1F21) : rgb(0xE9E9EC)
        text = dark ? rgb(0xF5F5F7) : rgb(0x1D1D1F)
        secondary = dark ? rgb(0xA1A1A6) : rgb(0x6E6E73)
        tertiary = dark ? rgb(0x6E6E73) : rgb(0xA1A1A6)
        link = dark ? rgb(0x5AA9FF) : rgb(0x0A66D8)
        separator = dark ? rgb(0xFFFFFF, 0.12) : rgb(0x000000, 0.12)
        accent = dark ? rgb(0x0A84FF) : rgb(0x0071E3)
        selection = dark ? rgb(0x3A3A3D) : rgb(0xDCDCDF)
    }
}

/// Draws a mock window and records what in it can be clicked, in one pass,
/// so a target's frame is always the frame of what was drawn. With
/// `drawing` off nothing is painted and only the targets are collected.
/// Coordinates have their origin at the top-left, y down.
@MainActor
final class SceneBuilder {
    let palette: ScenePalette
    let drawing: Bool
    private(set) var targets: [SceneTarget] = []

    init(dark: Bool, drawing: Bool) {
        self.palette = ScenePalette(dark: dark)
        self.drawing = drawing
    }

    var dark: Bool { palette.dark }

    func target(_ frame: NSRect, role: String?, subrole: String? = nil) {
        targets.append(SceneTarget(frame: frame, role: role, subrole: subrole))
    }

    func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) {
        guard drawing else {
            return
        }
        color.setFill()
        if radius > 0 {
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        } else {
            rect.fill()
        }
    }

    func stroke(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0, width: CGFloat = 1) {
        guard drawing else {
            return
        }
        let path = NSBezierPath(
            roundedRect: rect.insetBy(dx: width / 2, dy: width / 2),
            xRadius: max(radius - width / 2, 0),
            yRadius: max(radius - width / 2, 0)
        )
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    func oval(_ rect: NSRect, _ color: NSColor) {
        guard drawing else {
            return
        }
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    func hairline(x: CGFloat, y: CGFloat, width: CGFloat) {
        fill(NSRect(x: x, y: y, width: width, height: 1), palette.separator)
    }

    func verticalHairline(x: CGFloat, y: CGFloat, height: CGFloat) {
        fill(NSRect(x: x, y: y, width: 1, height: height), palette.separator)
    }

    func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    func measure(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSSize {
        let measured = (string as NSString).size(withAttributes: [.font: font(size, weight)])
        return NSSize(width: ceil(measured.width), height: ceil(measured.height))
    }

    /// Draws one line of text with its top-left at `(x, y)` and returns the
    /// rectangle it takes. A `maxWidth` truncates with an ellipsis.
    @discardableResult
    func text(
        _ string: String,
        x: CGFloat,
        y: CGFloat,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor,
        underline: Bool = false,
        kern: CGFloat = 0,
        maxWidth: CGFloat? = nil
    ) -> NSRect {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(size, weight),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        if underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if kern != 0 {
            attributes[.kern] = kern
        }
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let natural = attributed.size()
        var rect = NSRect(x: x, y: y, width: ceil(natural.width), height: ceil(natural.height))
        if let maxWidth, rect.width > maxWidth {
            rect.size.width = maxWidth
        }
        if drawing {
            attributed.draw(in: rect)
        }
        return rect
    }

    /// One line of text centered in `rect`.
    func centeredText(
        _ string: String,
        in rect: NSRect,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor
    ) {
        let measured = measure(string, size: size, weight: weight)
        text(
            string,
            x: rect.midX - measured.width / 2,
            y: rect.midY - measured.height / 2,
            size: size,
            weight: weight,
            color: color
        )
    }

    /// One line of text whose right edge is at `right`.
    @discardableResult
    func trailingText(
        _ string: String,
        right: CGFloat,
        y: CGFloat,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor
    ) -> NSRect {
        let measured = measure(string, size: size, weight: weight)
        return text(string, x: right - measured.width, y: y, size: size, weight: weight, color: color)
    }

    /// A text link, recorded as a target.
    @discardableResult
    func link(
        _ string: String,
        x: CGFloat,
        y: CGFloat,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor? = nil,
        underline: Bool = false
    ) -> NSRect {
        let rect = text(
            string, x: x, y: y, size: size, weight: weight,
            color: color ?? palette.link, underline: underline
        )
        target(rect, role: "AXLink")
        return rect
    }

    /// Words wrapped to `width`. A run marked as a link is kept on one line,
    /// underlined, and recorded as a target. Returns the y below the last line.
    @discardableResult
    func paragraph(
        _ runs: [(text: String, isLink: Bool)],
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        size: CGFloat,
        lineHeight: CGFloat
    ) -> CGFloat {
        var cursorX = x
        var cursorY = y
        for run in runs {
            let pieces: [String]
            if run.isLink {
                pieces = [run.text]
            } else {
                pieces = run.text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            }
            for (index, piece) in pieces.enumerated() {
                let isLast = index == pieces.count - 1
                let word = run.isLink || isLast ? piece : piece + " "
                if word.isEmpty {
                    continue
                }
                let wordWidth = measure(word, size: size).width
                if cursorX + wordWidth > x + width, cursorX > x {
                    cursorX = x
                    cursorY += lineHeight
                }
                if run.isLink {
                    link(word, x: cursorX, y: cursorY, size: size, underline: true)
                } else {
                    text(word, x: cursorX, y: cursorY, size: size, color: palette.text)
                }
                cursorX += wordWidth
            }
        }
        return cursorY + lineHeight
    }

    /// An SF Symbol centered on `center`. A name this system does not have
    /// is drawn as a small ring, so a missing symbol never fails a render.
    func symbol(
        _ name: String,
        center: NSPoint,
        pointSize: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor
    ) {
        guard drawing else {
            return
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else {
            let ring = NSBezierPath(ovalIn: NSRect(
                x: center.x - pointSize / 2 + 1,
                y: center.y - pointSize / 2 + 1,
                width: pointSize - 2,
                height: pointSize - 2
            ))
            ring.lineWidth = 1.5
            color.setStroke()
            ring.stroke()
            return
        }
        let size = image.size
        image.draw(
            in: NSRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    /// A square icon button: the symbol is drawn and the square is a target.
    func iconButton(
        _ name: String,
        in rect: NSRect,
        pointSize: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor
    ) {
        symbol(name, center: NSPoint(x: rect.midX, y: rect.midY), pointSize: pointSize, weight: weight, color: color)
        target(rect, role: "AXButton")
    }

    /// A rounded square with one character on it, standing in for a picture.
    func avatar(_ glyph: String, in rect: NSRect, color: NSColor, radius: CGFloat = 5) {
        fill(rect, color, radius: radius)
        centeredText(glyph, in: rect, size: rect.height * 0.42, weight: .medium, color: .white)
    }
}

/// A mock window: its size, and the function that draws it.
@MainActor
struct PreviewScene {
    let name: String
    let size: NSSize
    let build: @MainActor (SceneBuilder) -> Void

    func targets() -> [SceneTarget] {
        let builder = SceneBuilder(dark: false, drawing: false)
        build(builder)
        return builder.targets
    }

    /// The scene's targets as a hint pass would label them: ranked by
    /// `HintRanking`, then named by `HintSession`.
    func session() -> HintSession {
        let all = targets()
        let items = all.enumerated().map { index, target in
            HintRankItem(
                role: target.role,
                subrole: target.subrole,
                frame: HintRect(
                    x: Double(target.frame.minX),
                    y: Double(target.frame.minY),
                    width: Double(target.frame.width),
                    height: Double(target.frame.height)
                ),
                index: index
            )
        }
        let window = HintRect(x: 0, y: 0, width: Double(size.width), height: Double(size.height))
        let ranked = HintRanking.order(items, window: window).map { item in
            HintTarget(frame: item.frame, identifier: String(item.index))
        }
        return HintSession(targets: ranked, click: .plain)
    }
}

/// Paints a scene. Flipped, so the scene's y runs down.
@MainActor
final class SceneView: NSView {
    private let scene: PreviewScene

    init(scene: PreviewScene) {
        self.scene = scene
        super.init(frame: NSRect(origin: .zero, size: scene.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        scene.build(SceneBuilder(dark: dark, drawing: true))
    }
}
#endif

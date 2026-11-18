#if canImport(AppKit)
import AppKit
import QuartzCore
import SupervimCore

@MainActor
enum ChromeFont {
    static func mono(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func rounded(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return base
    }

    static func system(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
}

@MainActor
enum ChromeNSColor {
    static func color(_ source: ChromeColor, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: source.red, green: source.green, blue: source.blue, alpha: alpha)
    }
}

@MainActor
enum ChromeAppearance {
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

@MainActor
func chromeDraw(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left
) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineBreakMode = .byTruncatingTail
    let attributed = NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
    )
    attributed.draw(in: rect)
}

/// Draws hint labels. One painter is made per drawing pass: it resolves the
/// colors, the font and the accessibility settings once, and then draws any
/// number of labels with them.
///
/// A label is a near-opaque gray pill with a hairline edge and a soft
/// shadow, the green cursor block on the left, and SF Mono Semibold 12.
/// Characters already typed turn green. They keep the same font, so a label
/// does not change width while it is being typed.
@MainActor
struct HintBadgePainter {
    var dark: Bool
    var contrast: Bool
    var differentiate: Bool
    var opaque: Bool

    private let font: NSFont
    private let fill: NSColor
    private let stroke: NSColor
    private let cursor: NSColor
    private let shadow: NSShadow
    private let clearShadow = NSShadow()
    private let matched: [NSAttributedString.Key: Any]
    private let remainder: [NSAttributedString.Key: Any]

    static let font = ChromeFont.mono(12, weight: .semibold)

    init(
        appearance: NSAppearance,
        contrast: Bool? = nil,
        differentiate: Bool? = nil,
        reduceTransparency: Bool? = nil
    ) {
        let workspace = NSWorkspace.shared
        let dark = ChromeAppearance.isDark(appearance)
        let contrast = contrast ?? workspace.accessibilityDisplayShouldIncreaseContrast
        let differentiate = differentiate ?? workspace.accessibilityDisplayShouldDifferentiateWithoutColor
        let opaque = contrast || (reduceTransparency ?? workspace.accessibilityDisplayShouldReduceTransparency)
        let font = Self.font
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.45 : 0.24)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = contrast ? 0 : 3
        var matched: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ChromeNSColor.color(dark ? ChromePalette.darkMatched : ChromePalette.lightMatched),
        ]
        if differentiate {
            matched[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        self.dark = dark
        self.contrast = contrast
        self.differentiate = differentiate
        self.opaque = opaque
        self.font = font
        self.fill = ChromeNSColor.color(
            dark ? ChromePalette.darkFill : ChromePalette.lightFill,
            alpha: opaque ? 1 : CGFloat(dark ? ChromePalette.darkFillAlpha : ChromePalette.lightFillAlpha)
        )
        self.stroke = ChromeNSColor.color(
            dark ? ChromePalette.darkStroke : ChromePalette.lightStroke,
            alpha: contrast ? 0.9 : CGFloat(dark ? ChromePalette.darkHairlineAlpha : ChromePalette.lightHairlineAlpha)
        )
        self.cursor = ChromeNSColor.color(ChromePalette.iconGreen)
        self.shadow = shadow
        self.matched = matched
        self.remainder = [
            .font: font,
            .foregroundColor: ChromeNSColor.color(dark ? ChromePalette.darkText : ChromePalette.lightText),
        ]
    }

    /// Outer size of a label, shadow margin included.
    static func size(for label: String) -> NSSize {
        let width = (label as NSString).size(withAttributes: [.font: font]).width
        let size = HintBadgeMetrics.size(
            textWidth: Double(width),
            textHeight: Double(font.ascender - font.descender)
        )
        return NSSize(width: size.width, height: size.height)
    }

    func draw(label: String, typedPrefix: String, in frame: NSRect) {
        let margin = CGFloat(HintBadgeMetrics.shadowMargin)
        let pill = frame.insetBy(dx: margin, dy: margin)
        let radius = CGFloat(HintBadgeMetrics.cornerRadius)
        let path = NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius)

        shadow.set()
        fill.setFill()
        path.fill()
        clearShadow.set()

        let line: CGFloat = contrast ? 1.5 : 1
        let edge = NSBezierPath(
            roundedRect: pill.insetBy(dx: line / 2, dy: line / 2),
            xRadius: radius - line / 2,
            yRadius: radius - line / 2
        )
        edge.lineWidth = line
        stroke.setStroke()
        edge.stroke()

        let cursorHeight = min(CGFloat(HintBadgeMetrics.cursorHeight), pill.height - 6)
        let cursorWidth = CGFloat(HintBadgeMetrics.cursorWidth)
        let bar = NSRect(
            x: pill.minX + CGFloat(HintBadgeMetrics.textPaddingX),
            y: pill.midY - cursorHeight / 2,
            width: cursorWidth,
            height: cursorHeight
        )
        cursor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: cursorWidth / 2, yRadius: cursorWidth / 2).fill()

        let split = HintLabelHighlight.split(label: label, typedPrefix: typedPrefix)
        var textX = bar.maxX + CGFloat(HintBadgeMetrics.cursorGap)
        let baseline = pill.midY - (font.ascender + font.descender) / 2
        if !split.matched.isEmpty {
            let text = split.matched as NSString
            text.draw(at: NSPoint(x: textX, y: baseline), withAttributes: matched)
            textX += text.size(withAttributes: matched).width
        }
        if !split.remainder.isEmpty {
            (split.remainder as NSString).draw(at: NSPoint(x: textX, y: baseline), withAttributes: remainder)
        }
    }
}

/// One hint label as a view. The overlay draws its labels on one canvas;
/// this view is the same drawing for the snapshot tool.
@MainActor
public final class HintBadgeView: NSView {
    public let label: String
    public let typedPrefix: String
    public var forcesIncreaseContrast: Bool?
    public var forcesDifferentiateWithoutColor: Bool?
    public var forcesReduceTransparency: Bool?

    public init(label: String, typedPrefix: String) {
        self.label = label
        self.typedPrefix = typedPrefix
        super.init(frame: .zero)
        frame.size = badgeSize
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public override var isOpaque: Bool { false }

    public var badgeSize: NSSize {
        HintBadgePainter.size(for: label)
    }

    public override func draw(_ dirtyRect: NSRect) {
        HintBadgePainter(
            appearance: effectiveAppearance,
            contrast: forcesIncreaseContrast,
            differentiate: forcesDifferentiateWithoutColor,
            reduceTransparency: forcesReduceTransparency
        ).draw(label: label, typedPrefix: typedPrefix, in: bounds)
    }
}

/// Every hint label on one screen, drawn by one view. A keystroke replaces
/// the list and redraws; no view is created or removed.
@MainActor
final class HintCanvasView: NSView {
    struct Badge {
        var label: String
        var frame: NSRect
    }

    private var badges: [Badge] = []
    private var typedPrefix = ""

    override var isOpaque: Bool { false }

    func replace(_ badges: [Badge], typedPrefix: String) {
        self.badges = badges
        self.typedPrefix = typedPrefix
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !badges.isEmpty else {
            return
        }
        let painter = HintBadgePainter(appearance: effectiveAppearance)
        for badge in badges where badge.frame.intersects(dirtyRect) {
            painter.draw(label: badge.label, typedPrefix: typedPrefix, in: badge.frame)
        }
    }
}

/// Small copy of the app icon, used on the help sheet, the banner, and the windows.
@MainActor
public final class IconMarkView: NSView {
    private let side: CGFloat

    public init(side: CGFloat) {
        self.side = side
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: side, height: side)
    }

    public override func draw(_ dirtyRect: NSRect) {
        IconMarkDrawing.draw(in: bounds.insetBy(dx: 0.5, dy: 0.5))
    }
}

/// Shortcut sheet. Vibrancy sits under a translucent gray tint so the type
/// stays in the icon palette on a desktop, and stays readable in a snapshot.
@MainActor
public final class HelpSheetView: NSView {
    static let cornerRadius: CGFloat = 16
    public let sheetLayout: HelpSheetLayout
    private let effect = NSVisualEffectView()
    private let canvas: HelpCanvas

    public init(page: HelpPage) {
        let sheetLayout = HelpChrome.layout(page: page)
        self.sheetLayout = sheetLayout
        self.canvas = HelpCanvas(layout: sheetLayout)
        super.init(frame: NSRect(x: 0, y: 0, width: sheetLayout.width, height: sheetLayout.height))
        effect.material = .hudWindow
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.frame = bounds
        effect.autoresizingMask = [.width, .height]
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Self.cornerRadius
        effect.layer?.masksToBounds = true
        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        addSubview(effect)
        addSubview(canvas)
        refreshAppearance()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { false }

    public override func draw(_ dirtyRect: NSRect) {
        let dark = ChromeAppearance.isDark(effectiveAppearance)
        let fill = dark ? ChromePalette.darkFill : ChromePalette.lightFill
        ChromeNSColor.color(fill, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    public func refreshAppearance() {
        let flat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        effect.isHidden = flat
        effect.layer?.cornerRadius = Self.cornerRadius
        effect.layer?.masksToBounds = true
        canvas.needsDisplay = true
    }
}

@MainActor
private final class HelpCanvas: NSView {
    let sheetLayout: HelpSheetLayout

    init(layout: HelpSheetLayout) {
        self.sheetLayout = layout
        super.init(frame: NSRect(x: 0, y: 0, width: layout.width, height: layout.height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ChromeAppearance.isDark(effectiveAppearance)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let palette = HelpPalette(dark: dark, contrast: contrast)
        let fonts = HelpFonts()

        let margin = CGFloat(HelpMetrics.margin)
        let markSide: CGFloat = 20
        let mark = NSRect(x: margin, y: margin + 1, width: markSide, height: markSide)
        IconMarkDrawing.draw(in: mark, flipped: true)
        chromeDraw(
            "Shortcuts",
            in: NSRect(x: mark.maxX + 9, y: margin, width: 220, height: 22),
            font: fonts.title,
            color: palette.text
        )
        drawCloseHint(palette: palette, fonts: fonts)

        let ruleY = margin + CGFloat(HelpMetrics.titleBlock) - 2
        palette.rule.setStroke()
        let rule = NSBezierPath()
        rule.move(to: NSPoint(x: margin, y: ruleY))
        rule.line(to: NSPoint(x: bounds.width - margin, y: ruleY))
        rule.lineWidth = contrast ? 1.5 : 1
        rule.stroke()

        // One key cap width per column of the sheet, so the descriptions
        // in a column start on the same line.
        var keyColumns: [Double: CGFloat] = [:]
        for section in sheetLayout.sections {
            for row in section.rows {
                let width = capWidth(row.keys, font: fonts.cap, limit: CGFloat(row.frame.width) * 0.46)
                keyColumns[row.frame.x] = max(keyColumns[row.frame.x] ?? 0, width)
            }
        }

        for section in sheetLayout.sections {
            drawHeader(section, palette: palette, fonts: fonts)
            for row in section.rows {
                drawRow(
                    row,
                    keyColumn: keyColumns[row.frame.x] ?? 26,
                    palette: palette,
                    fonts: fonts,
                    contrast: contrast
                )
            }
        }

        let border = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: HelpSheetView.cornerRadius,
            yRadius: HelpSheetView.cornerRadius
        )
        border.lineWidth = contrast ? 1.5 : 1
        palette.stroke.setStroke()
        border.stroke()
    }

    private func capWidth(_ keys: String, font: NSFont, limit: CGFloat) -> CGFloat {
        let textWidth = ceil((keys as NSString).size(withAttributes: [.font: font]).width)
        return min(max(textWidth + 14, 26), limit)
    }

    /// "?" and "esc" as key caps at the right of the title, then "to close".
    private func drawCloseHint(palette: HelpPalette, fonts: HelpFonts) {
        let margin = CGFloat(HelpMetrics.margin)
        let label = "to close"
        let labelWidth = ceil((label as NSString).size(withAttributes: [.font: fonts.note]).width)
        var x = bounds.width - margin - labelWidth
        let midY = margin + 11
        chromeDraw(
            label,
            in: NSRect(x: x, y: midY - 7, width: labelWidth + 2, height: 14),
            font: fonts.note,
            color: palette.secondary
        )
        for keys in ["esc", "?"] {
            let width = capWidth(keys, font: fonts.smallCap, limit: 60)
            x -= width + 6
            drawCap(
                keys,
                in: NSRect(x: x, y: midY - 9, width: width, height: 18),
                font: fonts.smallCap,
                palette: palette,
                contrast: false
            )
        }
    }

    /// The green cursor block, then the section name in small capitals.
    private func drawHeader(_ section: HelpPlacedSection, palette: HelpPalette, fonts: HelpFonts) {
        let header = section.header
        let bar = NSRect(x: header.x, y: header.y + (header.height - 9) / 2, width: 2.5, height: 9)
        palette.accent.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.25, yRadius: 1.25).fill()
        let title = NSAttributedString(
            string: section.title.uppercased(),
            attributes: [
                .font: fonts.header,
                .foregroundColor: palette.secondary,
                .kern: 0.7,
            ]
        )
        title.draw(in: NSRect(x: header.x + 8, y: header.y + 1, width: header.width - 8, height: header.height))
    }

    private func drawCap(
        _ keys: String,
        in rect: NSRect,
        font: NSFont,
        palette: HelpPalette,
        contrast: Bool
    ) {
        // The lip under the cap is what makes it read as a key.
        let lip = NSBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: 1), xRadius: 5, yRadius: 5)
        palette.capLip.setFill()
        lip.fill()
        let cap = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        palette.capFill.setFill()
        cap.fill()
        let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5)
        edge.lineWidth = contrast ? 1.25 : 1
        palette.stroke.setStroke()
        edge.stroke()
        let lineHeight = ceil(font.ascender - font.descender)
        chromeDraw(
            keys,
            in: NSRect(x: rect.minX + 2, y: rect.midY - lineHeight / 2, width: rect.width - 4, height: lineHeight),
            font: font,
            color: palette.text,
            alignment: .center
        )
    }

    private func drawRow(
        _ row: HelpPlacedRow,
        keyColumn: CGFloat,
        palette: HelpPalette,
        fonts: HelpFonts,
        contrast: Bool
    ) {
        let capHeight: CGFloat = 20
        let capRect = NSRect(
            x: row.frame.x,
            y: row.frame.y + (row.frame.height - capHeight) / 2,
            width: capWidth(row.keys, font: fonts.cap, limit: CGFloat(row.frame.width) * 0.46),
            height: capHeight
        )
        drawCap(row.keys, in: capRect, font: fonts.cap, palette: palette, contrast: contrast)
        let textX = CGFloat(row.frame.x) + keyColumn + 10
        let available = CGFloat(row.frame.maxX) - textX
        if row.note.isEmpty {
            chromeDraw(
                row.summary,
                in: NSRect(x: textX, y: row.frame.y + 3, width: available, height: 18),
                font: fonts.summary,
                color: palette.text
            )
        } else {
            chromeDraw(
                row.summary,
                in: NSRect(x: textX, y: row.frame.y + 2, width: available, height: 16),
                font: fonts.summary,
                color: palette.text
            )
            chromeDraw(
                row.note,
                in: NSRect(x: textX, y: row.frame.y + 18, width: available, height: 14),
                font: fonts.note,
                color: palette.secondary
            )
        }
    }
}

@MainActor
private struct HelpFonts {
    let title = ChromeFont.rounded(17, weight: .semibold)
    let header = ChromeFont.rounded(10.5, weight: .semibold)
    let summary = ChromeFont.system(13, weight: .regular)
    let note = ChromeFont.system(11, weight: .regular)
    let cap = ChromeFont.mono(11.5, weight: .medium)
    let smallCap = ChromeFont.mono(10.5, weight: .medium)
}

@MainActor
private struct HelpPalette {
    let text: NSColor
    let secondary: NSColor
    let stroke: NSColor
    let rule: NSColor
    let capFill: NSColor
    let capLip: NSColor
    let accent: NSColor

    init(dark: Bool, contrast: Bool) {
        let line = dark ? ChromePalette.darkStroke : ChromePalette.lightStroke
        let hairline = CGFloat(dark ? ChromePalette.darkHairlineAlpha : ChromePalette.lightHairlineAlpha)
        text = ChromeNSColor.color(dark ? ChromePalette.darkText : ChromePalette.lightText)
        secondary = ChromeNSColor.color(dark ? ChromePalette.darkSecondary : ChromePalette.lightSecondary)
        stroke = ChromeNSColor.color(line, alpha: contrast ? 0.9 : hairline)
        rule = ChromeNSColor.color(line, alpha: contrast ? 0.9 : hairline * 0.55)
        capFill = ChromeNSColor.color(dark ? ChromePalette.darkKeyCap : ChromePalette.lightKeyCap)
        capLip = dark
            ? NSColor.black.withAlphaComponent(0.45)
            : ChromeNSColor.color(ChromePalette.lightStroke, alpha: 0.2)
        accent = ChromeNSColor.color(ChromePalette.iconGreen)
    }
}

/// The short "nothing to click" toast: a capsule in the label's own style,
/// with the green cursor block before the text. Opaque enough to read on
/// any window.
@MainActor
public final class BannerView: NSView {
    public let message: String
    private static let font = ChromeFont.system(13, weight: .medium)
    private static let inset: CGFloat = 6

    public init(message: String) {
        self.message = message
        let textWidth = ceil((message as NSString).size(withAttributes: [.font: Self.font]).width)
        let width = min(max(textWidth + 50 + Self.inset * 2, 180), 520)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 34 + Self.inset * 2))
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public override var isOpaque: Bool { false }

    public override func draw(_ dirtyRect: NSRect) {
        let dark = ChromeAppearance.isDark(effectiveAppearance)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let flat = contrast || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let fill = dark ? ChromePalette.darkFill : ChromePalette.lightFill
        let alpha: CGFloat = flat ? 1 : (dark ? CGFloat(ChromePalette.darkFillAlpha) : CGFloat(ChromePalette.lightFillAlpha))
        let text = ChromeNSColor.color(dark ? ChromePalette.darkText : ChromePalette.lightText)
        let stroke = ChromeNSColor.color(
            dark ? ChromePalette.darkStroke : ChromePalette.lightStroke,
            alpha: contrast ? 0.9 : CGFloat(dark ? ChromePalette.darkHairlineAlpha : ChromePalette.lightHairlineAlpha)
        )
        let rect = bounds.insetBy(dx: Self.inset, dy: Self.inset)
        let radius = rect.height / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.5 : 0.22)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = contrast ? 0 : 5
        shadow.set()
        ChromeNSColor.color(fill, alpha: alpha).setFill()
        path.fill()
        NSShadow().set()
        let line: CGFloat = contrast ? 1.5 : 1
        let edge = NSBezierPath(
            roundedRect: rect.insetBy(dx: line / 2, dy: line / 2),
            xRadius: radius - line / 2,
            yRadius: radius - line / 2
        )
        edge.lineWidth = line
        stroke.setStroke()
        edge.stroke()

        let bar = NSRect(x: rect.minX + 16, y: rect.midY - 7, width: 3, height: 14)
        ChromeNSColor.color(ChromePalette.iconGreen).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        chromeDraw(
            message,
            in: NSRect(x: bar.maxX + 9, y: rect.midY - 9, width: rect.maxX - bar.maxX - 25, height: 18),
            font: Self.font,
            color: text
        )
    }
}

@MainActor
enum IconMarkDrawing {
    /// `flipped` is true inside a view whose y axis runs down, so the
    /// gradient still goes from light at the top to darker at the bottom.
    static func draw(in rect: NSRect, flipped: Bool = false) {
        let radius = rect.width * 0.24
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGradient(colors: [
            ChromeNSColor.color(ChromePalette.iconGrayTop),
            ChromeNSColor.color(ChromePalette.iconGrayBottom),
        ])?.draw(in: path, angle: flipped ? 90 : -90)
        let edge = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: radius - 0.5,
            yRadius: radius - 0.5
        )
        ChromeNSColor.color(ChromePalette.lightStroke, alpha: 0.16).setStroke()
        edge.lineWidth = 1
        edge.stroke()
        let cursorWidth = max(2, (rect.width * 0.15).rounded())
        let cursorHeight = (rect.height * 0.46).rounded()
        let cursor = NSRect(
            x: rect.midX - cursorWidth / 2,
            y: rect.midY - cursorHeight / 2,
            width: cursorWidth,
            height: cursorHeight
        )
        ChromeNSColor.color(ChromePalette.iconGreen).setFill()
        NSBezierPath(roundedRect: cursor, xRadius: cursorWidth / 2, yRadius: cursorWidth / 2).fill()
    }
}

/// Template image for the menu-bar status item. The system tints it.
@MainActor
public enum MenuBarGlyphImage {
    public static func image(for kind: MenuBarGlyphKind) -> NSImage {
        let side: CGFloat = 16
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSColor.black.setFill()
        draw(kind, in: NSRect(x: 0, y: 0, width: side, height: side))
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = kind.rawValue
        return image
    }

    /// Each glyph is built from the same rounded bar the app icon uses:
    /// one block for Normal, a thin beam with serifs for Insert, two bars
    /// for Paused, and a ring for anything else.
    public static func draw(_ kind: MenuBarGlyphKind, in rect: NSRect) {
        func bar(_ frame: NSRect, radius: CGFloat) {
            NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
        }
        switch kind {
        case .normal:
            bar(NSRect(x: rect.midX - 2.5, y: rect.minY + 2, width: 5, height: rect.height - 4), radius: 1.5)
        case .insert:
            bar(NSRect(x: rect.midX - 0.75, y: rect.minY + 2.5, width: 1.5, height: rect.height - 5), radius: 0.75)
            bar(NSRect(x: rect.midX - 3.5, y: rect.maxY - 3.5, width: 7, height: 1.5), radius: 0.75)
            bar(NSRect(x: rect.midX - 3.5, y: rect.minY + 2, width: 7, height: 1.5), radius: 0.75)
        case .paused:
            let height = rect.height - 5
            let y = rect.minY + 2.5
            bar(NSRect(x: rect.midX - 4.5, y: y, width: 3, height: height), radius: 1)
            bar(NSRect(x: rect.midX + 1.5, y: y, width: 3, height: height), radius: 1)
        case .other:
            let ring = NSBezierPath(ovalIn: NSRect(x: rect.midX - 5, y: rect.midY - 5, width: 10, height: 10))
            ring.appendOval(in: NSRect(x: rect.midX - 3.25, y: rect.midY - 3.25, width: 6.5, height: 6.5))
            ring.windingRule = .evenOdd
            ring.fill()
        }
    }
}

/// Floating notice for a hint pass that found nothing. Separate from the label panel.
@MainActor
public final class TransientNoticePanel {
    public static let shared = TransientNoticePanel()

    private var panel: NSPanel?
    private var shownMessage: String?

    public func show(_ message: String) {
        guard !message.isEmpty else {
            hide()
            return
        }
        guard shownMessage != message else {
            return
        }
        shownMessage = message
        let view = BannerView(message: message)
        let panel = ensurePanel()
        panel.contentView = view
        panel.hasShadow = false
        var frame = view.frame
        if let visible = FloatingScreen.underMouse()?.visibleFrame {
            let maxX = max(visible.minX + 12, visible.maxX - frame.width - 12)
            frame.origin.x = min(max(visible.midX - frame.width / 2, visible.minX + 12), maxX)
            frame.origin.y = visible.maxY - frame.height - 28
        }
        panel.setFrame(frame, display: true)
        reveal(panel)
    }

    public func hide() {
        guard shownMessage != nil else {
            return
        }
        shownMessage = nil
        panel?.alphaValue = 1
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }
        let created = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = false
        created.ignoresMouseEvents = true
        created.hidesOnDeactivate = false
        created.becomesKeyOnlyIfNeeded = false
        created.level = .statusBar
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        created.isReleasedWhenClosed = false
        created.animationBehavior = .none
        panel = created
        return created
    }

    private func reveal(_ panel: NSPanel) {
        let duration = ChromeMotion.appearDuration(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        if duration == 0 {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }
}

enum FloatingScreen {
    @MainActor
    static func underMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let frames = screens.map { screen in
            DisplayFrame(
                x: Double(screen.frame.origin.x),
                y: Double(screen.frame.origin.y),
                width: Double(screen.frame.width),
                height: Double(screen.frame.height),
                backingScale: Double(screen.backingScaleFactor)
            )
        }
        if let index = OverlayScreen.index(
            containingX: Double(mouse.x),
            y: Double(mouse.y),
            screens: frames
        ), screens.indices.contains(index) {
            return screens[index]
        }
        return NSScreen.main ?? screens.first
    }
}
#endif

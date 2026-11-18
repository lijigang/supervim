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
        effect.layer?.cornerRadius = 14
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
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    public func refreshAppearance() {
        let flat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        effect.isHidden = flat
        effect.layer?.cornerRadius = 14
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
        let text = ChromeNSColor.color(dark ? ChromePalette.darkText : ChromePalette.lightText)
        let secondary = ChromeNSColor.color(dark ? ChromePalette.darkSecondary : ChromePalette.lightSecondary)
        let stroke = ChromeNSColor.color(
            dark ? ChromePalette.darkStroke : ChromePalette.lightStroke,
            alpha: contrast ? 0.9 : (dark ? 0.24 : 0.14)
        )
        let capFill = ChromeNSColor.color(dark ? ChromePalette.darkKeyCap : ChromePalette.lightKeyCap)

        let titleFont = ChromeFont.rounded(18, weight: .semibold)
        let subtitleFont = ChromeFont.system(12, weight: .regular)
        let headerFont = ChromeFont.rounded(11, weight: .semibold)
        let summaryFont = ChromeFont.system(13, weight: .medium)
        let noteFont = ChromeFont.system(11, weight: .regular)
        let capFont = ChromeFont.mono(12, weight: .semibold)

        let titleRect = NSRect(x: HelpMetrics.margin, y: HelpMetrics.margin, width: 220, height: 22)
        chromeDraw("Shortcuts", in: titleRect, font: titleFont, color: text)
        let subtitleRect = NSRect(
            x: bounds.width - HelpMetrics.margin - 220,
            y: HelpMetrics.margin + 4,
            width: 220,
            height: 16
        )
        chromeDraw("? or Esc to close", in: subtitleRect, font: subtitleFont, color: secondary, alignment: .right)

        let ruleY = HelpMetrics.margin + HelpMetrics.titleBlock - 2
        stroke.setStroke()
        let rule = NSBezierPath()
        rule.move(to: NSPoint(x: HelpMetrics.margin, y: ruleY))
        rule.line(to: NSPoint(x: bounds.width - HelpMetrics.margin, y: ruleY))
        rule.lineWidth = contrast ? 1.5 : 1
        rule.stroke()

        for section in sheetLayout.sections {
            chromeDraw(
                section.title.uppercased(),
                in: NSRect(x: section.header.x, y: section.header.y, width: section.header.width, height: section.header.height),
                font: headerFont,
                color: secondary
            )
            for row in section.rows {
                drawRow(
                    row,
                    capFont: capFont,
                    summaryFont: summaryFont,
                    noteFont: noteFont,
                    text: text,
                    secondary: secondary,
                    capFill: capFill,
                    stroke: stroke,
                    contrast: contrast
                )
            }
        }

        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        border.lineWidth = contrast ? 1.5 : 1
        stroke.setStroke()
        border.stroke()
    }

    private func drawRow(
        _ row: HelpPlacedRow,
        capFont: NSFont,
        summaryFont: NSFont,
        noteFont: NSFont,
        text: NSColor,
        secondary: NSColor,
        capFill: NSColor,
        stroke: NSColor,
        contrast: Bool
    ) {
        let textWidth = ceil((row.keys as NSString).size(withAttributes: [.font: capFont]).width)
        let capWidth = min(max(textWidth + 12, 22), row.frame.width * 0.46)
        let capHeight: CGFloat = 18
        let capRect = NSRect(
            x: row.frame.x,
            y: row.frame.y + (row.frame.height - capHeight) / 2,
            width: capWidth,
            height: capHeight
        )
        let cap = NSBezierPath(roundedRect: capRect, xRadius: 5, yRadius: 5)
        capFill.setFill()
        cap.fill()
        stroke.setStroke()
        cap.lineWidth = contrast ? 1.25 : 1
        cap.stroke()
        chromeDraw(
            row.keys,
            in: NSRect(x: capRect.minX + 2, y: capRect.midY - 7, width: capRect.width - 4, height: 14),
            font: capFont,
            color: text,
            alignment: .center
        )
        let textX = capRect.maxX + 8
        let textWidthAvailable = row.frame.maxX - textX
        if row.note.isEmpty {
            chromeDraw(
                row.summary,
                in: NSRect(x: textX, y: row.frame.y + 3, width: textWidthAvailable, height: 18),
                font: summaryFont,
                color: text
            )
        } else {
            chromeDraw(
                row.summary,
                in: NSRect(x: textX, y: row.frame.y + 2, width: textWidthAvailable, height: 16),
                font: summaryFont,
                color: text
            )
            chromeDraw(
                row.note,
                in: NSRect(x: textX, y: row.frame.y + 18, width: textWidthAvailable, height: 14),
                font: noteFont,
                color: secondary
            )
        }
    }
}

/// The short "nothing to click" toast. Opaque enough to read on any window.
@MainActor
public final class BannerView: NSView {
    public let message: String

    public init(message: String) {
        self.message = message
        let font = ChromeFont.system(13, weight: .semibold)
        let textWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width)
        let width = min(max(textWidth + 64, 220), 520)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 44))
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
            alpha: contrast ? 0.9 : (dark ? 0.28 : 0.16)
        )
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = contrast ? 0 : 6
        shadow.set()
        ChromeNSColor.color(fill, alpha: alpha).setFill()
        path.fill()
        NSShadow().set()
        stroke.setStroke()
        path.lineWidth = contrast ? 1.5 : 1
        path.stroke()

        let mark = NSRect(x: 14, y: bounds.midY - 8, width: 16, height: 16)
        IconMarkDrawing.draw(in: mark)
        let font = ChromeFont.system(13, weight: .semibold)
        chromeDraw(
            message,
            in: NSRect(x: 38, y: bounds.midY - 9, width: bounds.width - 52, height: 18),
            font: font,
            color: text
        )
    }
}

@MainActor
enum IconMarkDrawing {
    static func draw(in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
        NSGradient(colors: [
            ChromeNSColor.color(ChromePalette.iconGrayTop),
            ChromeNSColor.color(ChromePalette.iconGrayBottom),
        ])?.draw(in: path, angle: -90)
        ChromeNSColor.color(ChromePalette.lightStroke, alpha: 0.14).setStroke()
        path.lineWidth = 1
        path.stroke()
        let cursorWidth = max(2, rect.width * 0.16)
        let cursorHeight = rect.height * 0.46
        let cursor = NSRect(
            x: rect.midX - cursorWidth / 2,
            y: rect.midY - cursorHeight / 2,
            width: cursorWidth,
            height: cursorHeight
        )
        ChromeNSColor.color(ChromePalette.iconGreen).setFill()
        NSBezierPath(roundedRect: cursor, xRadius: 1, yRadius: 1).fill()
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

    public static func draw(_ kind: MenuBarGlyphKind, in rect: NSRect) {
        switch kind {
        case .normal:
            let bar = NSRect(x: rect.midX - 2, y: rect.minY + 2, width: 4, height: rect.height - 4)
            NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
        case .insert:
            let stem = NSRect(x: rect.midX - 0.6, y: rect.minY + 3, width: 1.2, height: rect.height - 6)
            stem.fill()
            NSRect(x: rect.midX - 4, y: rect.maxY - 3.4, width: 8, height: 1.4).fill()
            NSRect(x: rect.midX - 4, y: rect.minY + 2, width: 8, height: 1.4).fill()
        case .paused:
            let height = rect.height - 5
            let y = rect.minY + 2.5
            NSRect(x: rect.midX - 4.5, y: y, width: 3, height: height).fill()
            NSRect(x: rect.midX + 1.5, y: y, width: 3, height: height).fill()
        case .other:
            let dot = NSRect(x: rect.midX - 3, y: rect.midY - 3, width: 6, height: 6)
            NSBezierPath(ovalIn: dot).fill()
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
        panel.hasShadow = true
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
        created.hasShadow = true
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

#if canImport(AppKit)
import AppKit
import CoreText
import SupervimCore

/// Draws a hint label in whichever style was asked for. The shipped style
/// and the other redesign options go to `StyledHintPainter`; `classic`
/// goes to `HintBadgePainter`. One renderer is made per drawing pass.
@MainActor
struct HintLabelRenderer {
    private let classic: HintBadgePainter?
    private let styled: StyledHintPainter?

    init(
        style: HintLabelStyle,
        appearance: NSAppearance,
        contrast: Bool? = nil,
        differentiate: Bool? = nil,
        reduceTransparency: Bool? = nil
    ) {
        if style == .classic {
            classic = HintBadgePainter(
                appearance: appearance,
                contrast: contrast,
                differentiate: differentiate,
                reduceTransparency: reduceTransparency
            )
            styled = nil
        } else {
            classic = nil
            styled = StyledHintPainter(
                style: style,
                appearance: appearance,
                contrast: contrast,
                differentiate: differentiate,
                reduceTransparency: reduceTransparency
            )
        }
    }

    /// Outer size of a label: the body and the clear margin around it.
    static func size(for label: String, style: HintLabelStyle) -> NSSize {
        if style == .classic {
            return HintBadgePainter.size(for: label)
        }
        return StyledHintPainter.size(for: label, style: style)
    }

    func draw(
        label: String,
        typedPrefix: String,
        in frame: NSRect,
        tipX: CGFloat? = nil,
        tailDown: Bool = false
    ) {
        if let classic {
            classic.draw(label: label, typedPrefix: typedPrefix, in: frame)
        } else if let styled {
            styled.draw(label: label, typedPrefix: typedPrefix, in: frame, tipX: tipX, tailDown: tailDown)
        }
    }
}

/// The outline of a candidate label: a rounded body, and the pointer that
/// is part of the same path so the edge runs around both.
@MainActor
enum HintLabelOutline {
    enum Pointer {
        case none
        /// The body's top-left corner is drawn out to `tip`. `base` is how
        /// far along each edge the corner starts.
        case corner(tip: NSPoint, base: CGFloat)
        /// A triangle on the top edge, or on the bottom edge when `down`.
        case caret(tipX: CGFloat, halfWidth: CGFloat, height: CGFloat, down: Bool)

        /// The same pointer for an outline `distance` inside this one.
        func inset(by distance: CGFloat) -> Pointer {
            switch self {
            case .none:
                return .none
            case .corner(let tip, let base):
                return .corner(
                    tip: NSPoint(x: tip.x + distance * 1.58, y: tip.y - distance * 1.58),
                    base: max(base - distance * 1.16, 0)
                )
            case .caret(let tipX, let halfWidth, let height, let down):
                return .caret(
                    tipX: tipX,
                    halfWidth: max(halfWidth - distance * 0.45, 0),
                    height: max(height - distance * 0.5, 0),
                    down: down
                )
            }
        }
    }

    /// Coordinates have y up, as in the label canvas.
    static func path(body: NSRect, radius: CGFloat, pointer: Pointer) -> NSBezierPath {
        let r = max(min(radius, body.width / 2, body.height / 2), 0)
        switch pointer {
        case .none:
            return NSBezierPath(roundedRect: body, xRadius: r, yRadius: r)
        case .corner(let tip, let base):
            return cornerPath(body: body, radius: r, tip: tip, base: base)
        case .caret(let tipX, let halfWidth, let height, let down):
            guard height >= 2, halfWidth >= 1.5, body.width >= halfWidth * 2 + 3 else {
                return NSBezierPath(roundedRect: body, xRadius: r, yRadius: r)
            }
            let path = caretPath(body: body, radius: r, tipX: tipX, halfWidth: halfWidth, height: height)
            if down {
                path.transform(using: AffineTransform(
                    m11: 1, m12: 0, m21: 0, m22: -1, tX: 0, tY: body.minY + body.maxY
                ))
            }
            return path
        }
    }

    private static func cornerPath(body: NSRect, radius r: CGFloat, tip: NSPoint, base: CGFloat) -> NSBezierPath {
        let reach = min(max(base, r), body.width - r, body.height - r)
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: NSPoint(x: body.minX + reach, y: body.maxY))
        path.line(to: NSPoint(x: body.maxX - r, y: body.maxY))
        appendCorner(path, center: NSPoint(x: body.maxX - r, y: body.maxY - r), radius: r, from: 90, to: 0)
        path.line(to: NSPoint(x: body.maxX, y: body.minY + r))
        appendCorner(path, center: NSPoint(x: body.maxX - r, y: body.minY + r), radius: r, from: 0, to: -90)
        path.line(to: NSPoint(x: body.minX + r, y: body.minY))
        appendCorner(path, center: NSPoint(x: body.minX + r, y: body.minY + r), radius: r, from: 270, to: 180)
        path.line(to: NSPoint(x: body.minX, y: body.maxY - reach))
        path.close()
        return path
    }

    /// Caret on the top edge. When the caret's foot falls on a rounded
    /// corner, as on a one-letter capsule, the foot is put on the arc.
    private static func caretPath(
        body: NSRect,
        radius r: CGFloat,
        tipX: CGFloat,
        halfWidth: CGFloat,
        height: CGFloat
    ) -> NSBezierPath {
        let top = body.maxY
        let arcY = top - r
        let leftCenter = body.minX + r
        let rightCenter = body.maxX - r
        let tx = min(max(tipX, body.minX + halfWidth + 1.5), body.maxX - halfWidth - 1.5)
        let leftFoot = tx - halfWidth
        let rightFoot = tx + halfWidth

        func angle(center: CGFloat, x: CGFloat) -> CGFloat {
            acos(min(max((x - center) / r, -1), 1)) * 180 / .pi
        }
        func arcHeight(at degrees: CGFloat) -> CGFloat {
            arcY + r * sin(degrees * .pi / 180)
        }

        let path = NSBezierPath()
        path.move(to: NSPoint(x: body.minX, y: arcY))
        if r > 0, leftFoot < leftCenter {
            let stop = angle(center: leftCenter, x: leftFoot)
            path.appendArc(
                withCenter: NSPoint(x: leftCenter, y: arcY),
                radius: r, startAngle: 180, endAngle: stop, clockwise: true
            )
        } else {
            appendCorner(path, center: NSPoint(x: leftCenter, y: arcY), radius: r, from: 180, to: 90)
            path.line(to: NSPoint(x: leftFoot, y: top))
        }
        let tip = NSPoint(x: tx, y: top + height)
        if r > 0, rightFoot > rightCenter {
            let start = angle(center: rightCenter, x: rightFoot)
            let foot = NSPoint(x: rightFoot, y: arcHeight(at: start))
            path.appendArc(from: tip, to: foot, radius: 0.9)
            path.line(to: foot)
            path.appendArc(
                withCenter: NSPoint(x: rightCenter, y: arcY),
                radius: r, startAngle: start, endAngle: 0, clockwise: true
            )
        } else {
            let foot = NSPoint(x: rightFoot, y: top)
            path.appendArc(from: tip, to: foot, radius: 0.9)
            path.line(to: foot)
            path.line(to: NSPoint(x: rightCenter, y: top))
            appendCorner(path, center: NSPoint(x: rightCenter, y: arcY), radius: r, from: 90, to: 0)
        }
        path.line(to: NSPoint(x: body.maxX, y: body.minY + r))
        appendCorner(path, center: NSPoint(x: rightCenter, y: body.minY + r), radius: r, from: 0, to: -90)
        path.line(to: NSPoint(x: leftCenter, y: body.minY))
        appendCorner(path, center: NSPoint(x: leftCenter, y: body.minY + r), radius: r, from: 270, to: 180)
        path.close()
        return path
    }

    private static func appendCorner(
        _ path: NSBezierPath,
        center: NSPoint,
        radius: CGFloat,
        from start: CGFloat,
        to end: CGFloat
    ) {
        guard radius > 0 else {
            return
        }
        path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    }
}

/// Draws the shipped label and the other redesign options from `HintLabelSpec` and
/// `HintLabelPalette`. The letters are capitals, set on their cap height in
/// the middle of the body. The whole label is one line of text in one font:
/// typing changes colors only, so a label keeps its width and its letters
/// keep their places.
@MainActor
struct StyledHintPainter {
    let style: HintLabelStyle

    private let spec: HintLabelSpec
    private let contrast: Bool
    private let differentiate: Bool
    private let font: NSFont
    private let capHeight: CGFloat
    private let tracking: CGFloat
    private let gradient: NSGradient?
    private let flatFill: NSColor
    private let edge: NSColor
    private let rim: NSColor?
    private let shadow: NSShadow
    private let text: CGColor
    private let typed: CGColor
    private let typedMark: NSColor
    private let typedFill: NSColor?
    private let accent: NSColor

    private static let fontKey = NSAttributedString.Key(rawValue: kCTFontAttributeName as String)
    private static let kernKey = NSAttributedString.Key(rawValue: kCTKernAttributeName as String)
    private static let colorKey = NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String)

    init(
        style: HintLabelStyle,
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
        let spec = style.spec
        let palette = style.palette(dark: dark)
        let font = Self.font(for: spec)
        let fillAlpha: CGFloat = opaque ? 1 : CGFloat(palette.fillAlpha)
        let top = ChromeNSColor.color(palette.fillTop, alpha: fillAlpha)
        let bottom = ChromeNSColor.color(palette.fillBottom, alpha: fillAlpha)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(CGFloat(palette.shadowAlpha))
        shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(palette.shadowDrop))
        shadow.shadowBlurRadius = contrast ? 0 : CGFloat(palette.shadowBlur)

        self.style = style
        self.spec = spec
        self.contrast = contrast
        self.differentiate = differentiate
        self.font = font
        self.capHeight = font.capHeight
        self.tracking = CGFloat(spec.tracking)
        self.gradient = palette.fillTop == palette.fillBottom ? nil : NSGradient(starting: top, ending: bottom)
        self.flatFill = bottom
        self.edge = ChromeNSColor.color(palette.edge, alpha: contrast ? 0.95 : CGFloat(palette.edgeAlpha))
        self.rim = palette.rim.map { ChromeNSColor.color($0, alpha: CGFloat(palette.rimAlpha)) }
        self.shadow = shadow
        self.text = ChromeNSColor.color(palette.text).cgColor
        self.typed = ChromeNSColor.color(palette.typedText, alpha: CGFloat(palette.typedAlpha)).cgColor
        self.typedMark = ChromeNSColor.color(palette.typedText, alpha: CGFloat(palette.typedAlpha))
        self.typedFill = palette.typedFill.map { ChromeNSColor.color($0) }
        self.accent = ChromeNSColor.color(palette.accent)
    }

    static func font(for spec: HintLabelSpec) -> NSFont {
        let size = CGFloat(spec.fontSize)
        let weight: NSFont.Weight
        switch spec.fontWeight {
        case .semibold:
            weight = .semibold
        case .bold:
            weight = .bold
        case .heavy:
            weight = .heavy
        }
        switch spec.fontDesign {
        case .mono:
            return ChromeFont.mono(size, weight: weight)
        case .rounded:
            return ChromeFont.rounded(size, weight: weight)
        }
    }

    /// Outer size of a label, margin included.
    static func size(for label: String, style: HintLabelStyle) -> NSSize {
        let spec = style.spec
        let font = font(for: spec)
        let tracking = CGFloat(spec.tracking)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: label,
            attributes: [fontKey: font, kernKey: NSNumber(value: Double(tracking))]
        ))
        let size = HintLabelMetrics.size(
            spec: spec,
            textWidth: Double(inkWidth(of: line, tracking: tracking)),
            capHeight: Double(font.capHeight)
        )
        return NSSize(width: size.width, height: size.height)
    }

    /// Width of the letters, without the tracking that follows the last one.
    private static func inkWidth(of line: CTLine, tracking: CGFloat) -> CGFloat {
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return width > tracking ? width - tracking : max(width, 0)
    }

    func draw(label: String, typedPrefix: String, in frame: NSRect, tipX: CGFloat?, tailDown: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let margin = CGFloat(spec.margin)
        let body = frame.insetBy(dx: margin, dy: margin)
        guard body.width > 4, body.height > 4 else {
            return
        }
        let lineWidth: CGFloat = contrast ? 1.5 : 1
        let shape = body.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let radius = max(
            CGFloat(HintLabelMetrics.radius(spec: spec, bodyHeight: Double(body.height))) - lineWidth / 2,
            0
        )
        let pointer = pointerShape(frame: frame, body: body, tipX: tipX, tailDown: tailDown)
        let path = HintLabelOutline.path(body: shape, radius: radius, pointer: pointer)
        path.lineJoinStyle = .round

        // The shadow is drawn outside the body only, so a translucent body
        // is not darkened by its own shadow.
        NSGraphicsContext.saveGraphicsState()
        let outside = NSBezierPath(rect: frame.insetBy(dx: -24, dy: -24))
        outside.append(path)
        outside.windingRule = .evenOdd
        outside.addClip()
        shadow.set()
        NSColor.black.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        if let gradient {
            gradient.draw(in: path, angle: -90)
        } else {
            flatFill.setFill()
            path.fill()
        }

        let split = HintLabelHighlight.split(label: label, typedPrefix: typedPrefix)
        let typedLength = (split.matched as NSString).length
        let totalLength = (label as NSString).length
        let attributed = NSMutableAttributedString(
            string: label,
            attributes: [
                Self.fontKey: font,
                Self.kernKey: NSNumber(value: Double(tracking)),
                Self.colorKey: text,
            ]
        )
        if typedLength > 0 {
            attributed.addAttribute(Self.colorKey, value: typed, range: NSRange(location: 0, length: typedLength))
        }
        let line = CTLineCreateWithAttributedString(attributed)
        let inkWidth = Self.inkWidth(of: line, tracking: tracking)
        let textX = ((body.midX - inkWidth / 2) * 2).rounded() / 2
        let baseline = ((body.midY - capHeight / 2) * 2).rounded() / 2
        let typedEnd = typedLength > 0
            ? textX + CGFloat(CTLineGetOffsetForStringIndex(line, typedLength, nil))
            : textX

        if spec.typed == .inverse, typedLength > 0, let typedFill {
            let cut = typedLength >= totalLength ? frame.maxX + 24 : typedEnd - tracking / 2
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            typedFill.setFill()
            NSRect(
                x: frame.minX - 24,
                y: frame.minY - 24,
                width: cut - (frame.minX - 24),
                height: frame.height + 48
            ).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        if let rim, !contrast {
            let inner = HintLabelOutline.path(
                body: shape.insetBy(dx: 1, dy: 1),
                radius: max(radius - 1, 0),
                pointer: pointer.inset(by: 1)
            )
            inner.lineWidth = 1
            inner.lineJoinStyle = .round
            rim.setStroke()
            inner.stroke()
        }

        path.lineWidth = lineWidth
        edge.setStroke()
        path.stroke()

        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: textX, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()

        if spec.typed == .dimWithCursor, typedLength > 0, typedLength < totalLength {
            let next = (label as NSString).rangeOfComposedCharacterSequence(at: typedLength)
            let end = textX + CGFloat(CTLineGetOffsetForStringIndex(line, next.location + next.length, nil)) - tracking
            let bar = NSRect(x: typedEnd, y: body.minY + 2.5, width: max(end - typedEnd, 2), height: 2)
            accent.setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
        }
        if differentiate, spec.typed == .recolor, typedLength > 0 {
            let rule = NSRect(
                x: textX,
                y: baseline - 3,
                width: max(typedEnd - tracking - textX, 2),
                height: 1.5
            )
            typedMark.setFill()
            rule.fill()
        }
    }

    private func pointerShape(
        frame: NSRect,
        body: NSRect,
        tipX: CGFloat?,
        tailDown: Bool
    ) -> HintLabelOutline.Pointer {
        switch spec.pointer {
        case .none:
            return .none
        case .corner:
            return .corner(
                tip: NSPoint(x: frame.minX + 0.5, y: frame.maxY - 0.5),
                base: CGFloat(HintLabelMetrics.cornerBase)
            )
        case .caret:
            // No tip: the label rests on its target and needs no caret.
            guard let tipX else {
                return .none
            }
            return .caret(
                tipX: tipX,
                halfWidth: CGFloat(HintLabelMetrics.caretHalfWidth),
                height: CGFloat(HintLabelMetrics.caretHeight),
                down: tailDown
            )
        }
    }
}
#endif

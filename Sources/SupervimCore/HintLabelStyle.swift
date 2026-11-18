import Foundation

/// How a hint label looks. `amber` is what ships: option A of the redesign,
/// in light and in dark appearance. `classic` is the v0.1.5 gray pill it
/// replaced. `ink`, `cursor` and `glass` are options B to D, which were not
/// chosen. The overlay draws `shipped` only; the others are drawn by the
/// preview tool, which keeps the comparison in `docs/label-redesign`
/// reproducible. There is no setting that selects a style.
public enum HintLabelStyle: String, CaseIterable, Equatable, Sendable {
    case classic
    case amber
    case ink
    case cursor
    case glass

    public static let shipped: HintLabelStyle = .amber
    /// Options A to D of the redesign, in that order.
    public static let candidates: [HintLabelStyle] = [.amber, .ink, .cursor, .glass]

    public var optionLetter: String? {
        switch self {
        case .classic:
            return nil
        case .amber:
            return "A"
        case .ink:
            return "B"
        case .cursor:
            return "C"
        case .glass:
            return "D"
        }
    }

    public var title: String {
        switch self {
        case .classic:
            return "Classic"
        case .amber:
            return "Amber tag"
        case .ink:
            return "Ink pill"
        case .cursor:
            return "Cursor block"
        case .glass:
            return "Glass"
        }
    }
}

public enum HintLabelFontDesign: String, Equatable, Sendable {
    case mono
    case rounded

    public var familyName: String {
        switch self {
        case .mono:
            return "SF Mono"
        case .rounded:
            return "SF Pro Rounded"
        }
    }
}

public enum HintLabelFontWeight: String, Equatable, Sendable {
    case semibold
    case bold
    case heavy
}

/// What ties a label to its target.
public enum HintLabelPointer: String, Equatable, Sendable {
    /// The label lies on the top-left of the target and has no mark.
    case none
    /// The label lies on the top-left of the target, and its own top-left
    /// corner is drawn out to a point that touches the target's corner.
    case corner
    /// The label hangs under the target and a small triangle on its top edge
    /// touches the target. Near the bottom of a screen it sits above instead.
    case caret
}

/// How the letters already typed differ from the letters still to type.
public enum HintTypedTreatment: String, Equatable, Sendable {
    /// Typed letters take another color.
    case recolor
    /// Typed letters fade.
    case dim
    /// Typed letters swap ink and paper, like a terminal selection.
    case inverse
    /// Typed letters fade and a short bar sits under the next letter.
    case dimWithCursor
}

/// The numbers a style is drawn from. Lengths are in points.
public struct HintLabelSpec: Equatable, Sendable {
    public var fontDesign: HintLabelFontDesign
    public var fontWeight: HintLabelFontWeight
    public var fontSize: Double
    /// Extra space after each letter.
    public var tracking: Double
    public var paddingX: Double
    /// Space above and below the capital letters. Labels are uppercase, so
    /// the body is sized on cap height and not on the full line height.
    public var paddingY: Double
    /// `nil` is a capsule: the radius is half the body height.
    public var cornerRadius: Double?
    /// Clear space around the body, inside the label's frame. The shadow and
    /// the pointer are drawn in it.
    public var margin: Double
    public var pointer: HintLabelPointer
    public var typed: HintTypedTreatment

    public init(
        fontDesign: HintLabelFontDesign,
        fontWeight: HintLabelFontWeight,
        fontSize: Double,
        tracking: Double,
        paddingX: Double,
        paddingY: Double,
        cornerRadius: Double?,
        margin: Double,
        pointer: HintLabelPointer,
        typed: HintTypedTreatment
    ) {
        self.fontDesign = fontDesign
        self.fontWeight = fontWeight
        self.fontSize = fontSize
        self.tracking = tracking
        self.paddingX = paddingX
        self.paddingY = paddingY
        self.cornerRadius = cornerRadius
        self.margin = margin
        self.pointer = pointer
        self.typed = typed
    }
}

/// The colors a style is drawn from, for one appearance.
public struct HintLabelPalette: Equatable, Sendable {
    public var fillTop: ChromeColor
    public var fillBottom: ChromeColor
    public var fillAlpha: Double
    /// One-point outline of the body.
    public var edge: ChromeColor
    public var edgeAlpha: Double
    /// One-point highlight just inside the outline.
    public var rim: ChromeColor?
    public var rimAlpha: Double
    /// Letters still to type.
    public var text: ChromeColor
    /// Letters already typed.
    public var typedText: ChromeColor
    public var typedAlpha: Double
    /// Paper under the typed letters, for `HintTypedTreatment.inverse`.
    public var typedFill: ChromeColor?
    /// The bar under the next letter, for `HintTypedTreatment.dimWithCursor`.
    public var accent: ChromeColor
    public var shadowAlpha: Double
    public var shadowBlur: Double
    public var shadowDrop: Double

    public init(
        fillTop: ChromeColor,
        fillBottom: ChromeColor,
        fillAlpha: Double,
        edge: ChromeColor,
        edgeAlpha: Double,
        rim: ChromeColor?,
        rimAlpha: Double,
        text: ChromeColor,
        typedText: ChromeColor,
        typedAlpha: Double,
        typedFill: ChromeColor?,
        accent: ChromeColor,
        shadowAlpha: Double,
        shadowBlur: Double,
        shadowDrop: Double
    ) {
        self.fillTop = fillTop
        self.fillBottom = fillBottom
        self.fillAlpha = fillAlpha
        self.edge = edge
        self.edgeAlpha = edgeAlpha
        self.rim = rim
        self.rimAlpha = rimAlpha
        self.text = text
        self.typedText = typedText
        self.typedAlpha = typedAlpha
        self.typedFill = typedFill
        self.accent = accent
        self.shadowAlpha = shadowAlpha
        self.shadowBlur = shadowBlur
        self.shadowDrop = shadowDrop
    }

    /// What the typed letters look like on `fill`, with their fade applied.
    public func typedInk(on fill: ChromeColor) -> ChromeColor {
        typedText.composited(over: typedFill ?? fill, alpha: typedAlpha)
    }

    /// The body's two fill colors as they land on an opaque `backdrop`.
    public func fills(over backdrop: ChromeColor) -> [ChromeColor] {
        [fillTop, fillBottom].map { $0.composited(over: backdrop, alpha: fillAlpha) }
    }
}

extension HintLabelStyle {
    public var spec: HintLabelSpec {
        switch self {
        case .classic:
            return HintLabelSpec(
                fontDesign: .mono,
                fontWeight: .semibold,
                fontSize: 12,
                tracking: 0,
                paddingX: HintBadgeMetrics.textPaddingX,
                paddingY: HintBadgeMetrics.textPaddingY,
                cornerRadius: HintBadgeMetrics.cornerRadius,
                margin: HintBadgeMetrics.shadowMargin,
                pointer: .none,
                typed: .recolor
            )
        case .amber:
            return HintLabelSpec(
                fontDesign: .rounded,
                fontWeight: .bold,
                fontSize: 15,
                tracking: 0.4,
                paddingX: 6,
                paddingY: 5,
                cornerRadius: 6,
                margin: 4,
                pointer: .corner,
                typed: .dim
            )
        case .ink:
            return HintLabelSpec(
                fontDesign: .mono,
                fontWeight: .bold,
                fontSize: 14,
                tracking: 0.6,
                paddingX: 8.5,
                paddingY: 5.5,
                cornerRadius: nil,
                margin: 6,
                pointer: .caret,
                typed: .recolor
            )
        case .cursor:
            return HintLabelSpec(
                fontDesign: .mono,
                fontWeight: .heavy,
                fontSize: 15,
                tracking: 0,
                paddingX: 5.5,
                paddingY: 4.75,
                cornerRadius: 3.5,
                margin: 4,
                pointer: .corner,
                typed: .inverse
            )
        case .glass:
            return HintLabelSpec(
                fontDesign: .rounded,
                fontWeight: .heavy,
                fontSize: 16,
                tracking: 0.5,
                paddingX: 9,
                paddingY: 5,
                cornerRadius: nil,
                margin: 6,
                pointer: .caret,
                typed: .dimWithCursor
            )
        }
    }

    public func palette(dark: Bool) -> HintLabelPalette {
        switch self {
        case .classic:
            return HintLabelPalette(
                fillTop: dark ? ChromePalette.darkFill : ChromePalette.lightFill,
                fillBottom: dark ? ChromePalette.darkFill : ChromePalette.lightFill,
                fillAlpha: dark ? ChromePalette.darkFillAlpha : ChromePalette.lightFillAlpha,
                edge: dark ? ChromePalette.darkStroke : ChromePalette.lightStroke,
                edgeAlpha: dark ? ChromePalette.darkHairlineAlpha : ChromePalette.lightHairlineAlpha,
                rim: nil,
                rimAlpha: 0,
                text: dark ? ChromePalette.darkText : ChromePalette.lightText,
                typedText: dark ? ChromePalette.darkMatched : ChromePalette.lightMatched,
                typedAlpha: 1,
                typedFill: nil,
                accent: ChromePalette.iconGreen,
                shadowAlpha: dark ? 0.45 : 0.24,
                shadowBlur: 3,
                shadowDrop: 1
            )
        case .amber:
            // The same yellow in both appearances: the label is found by its
            // color, and a page does not change color with the system.
            return HintLabelPalette(
                fillTop: ChromeColor(hex: 0xFFE25A),
                fillBottom: ChromeColor(hex: 0xFFC619),
                fillAlpha: 1,
                edge: ChromeColor(hex: 0x7A4E00),
                edgeAlpha: dark ? 0.9 : 0.72,
                rim: ChromeColor(hex: 0xFFFFFF),
                rimAlpha: 0.5,
                text: ChromeColor(hex: 0x231700),
                typedText: ChromeColor(hex: 0x231700),
                typedAlpha: 0.3,
                typedFill: nil,
                accent: ChromeColor(hex: 0x231700),
                shadowAlpha: dark ? 0.55 : 0.3,
                shadowBlur: 4,
                shadowDrop: 1.5
            )
        case .ink:
            // Dark in both appearances. On a dark page the outline turns
            // light so the pill still has an edge.
            return HintLabelPalette(
                fillTop: ChromeColor(hex: 0x2A2A30),
                fillBottom: ChromeColor(hex: 0x131316),
                fillAlpha: 0.96,
                edge: dark ? ChromeColor(hex: 0xFFFFFF) : ChromeColor(hex: 0x000000),
                edgeAlpha: dark ? 0.5 : 0.6,
                rim: dark ? nil : ChromeColor(hex: 0xFFFFFF),
                rimAlpha: dark ? 0 : 0.2,
                text: ChromeColor(hex: 0xFFFFFF),
                typedText: ChromePalette.iconGreen,
                typedAlpha: 1,
                typedFill: nil,
                accent: ChromePalette.iconGreen,
                shadowAlpha: dark ? 0.6 : 0.36,
                shadowBlur: 5,
                shadowDrop: 2
            )
        case .cursor:
            return HintLabelPalette(
                fillTop: ChromeColor(hex: 0x3DD366),
                fillBottom: ChromeColor(hex: 0x2FBF53),
                fillAlpha: 1,
                edge: ChromeColor(hex: 0x063D17),
                edgeAlpha: dark ? 0.9 : 0.7,
                rim: ChromeColor(hex: 0xFFFFFF),
                rimAlpha: 0.28,
                text: ChromeColor(hex: 0x02170A),
                typedText: ChromeColor(hex: 0x4BE077),
                typedAlpha: 1,
                typedFill: ChromeColor(hex: 0x0A3518),
                accent: ChromePalette.iconGreen,
                shadowAlpha: dark ? 0.55 : 0.3,
                shadowBlur: 4,
                shadowDrop: 1.5
            )
        case .glass:
            if dark {
                return HintLabelPalette(
                    fillTop: ChromeColor(hex: 0x38383E),
                    fillBottom: ChromeColor(hex: 0x1F1F23),
                    fillAlpha: 0.88,
                    edge: ChromeColor(hex: 0x000000),
                    edgeAlpha: 0.6,
                    rim: ChromeColor(hex: 0xFFFFFF),
                    rimAlpha: 0.3,
                    text: ChromeColor(hex: 0xFFFFFF),
                    typedText: ChromeColor(hex: 0xFFFFFF),
                    typedAlpha: 0.32,
                    typedFill: nil,
                    accent: ChromePalette.iconGreen,
                    shadowAlpha: 0.6,
                    shadowBlur: 7,
                    shadowDrop: 2.5
                )
            }
            return HintLabelPalette(
                fillTop: ChromeColor(hex: 0xFFFFFF),
                fillBottom: ChromeColor(hex: 0xEDEDF2),
                fillAlpha: 0.88,
                edge: ChromeColor(hex: 0x000000),
                edgeAlpha: 0.3,
                rim: ChromeColor(hex: 0xFFFFFF),
                rimAlpha: 0.9,
                text: ChromeColor(hex: 0x0B0B0D),
                typedText: ChromeColor(hex: 0x0B0B0D),
                typedAlpha: 0.3,
                typedFill: nil,
                accent: ChromeColor(hex: 0x1E9E44),
                shadowAlpha: 0.3,
                shadowBlur: 7,
                shadowDrop: 2.5
            )
        }
    }
}

/// Sizes of a candidate label. `classic` keeps `HintBadgeMetrics`.
public enum HintLabelMetrics {
    /// Half the width of the caret where it meets the body.
    public static let caretHalfWidth = 4.5
    public static let caretHeight = 5.0
    /// How far along each edge the drawn-out corner starts.
    public static let cornerBase = 7.0
    /// The caret's tip is put this far along a wide target, and in the
    /// middle of a narrow one.
    public static let caretLead = 24.0
    /// The caret's tip is put at most this far below the top of a tall
    /// target, so the label stays next to the target's first line.
    public static let caretDepth = 28.0
    /// The caret's tip stays this far inside the bottom edge of a short target.
    public static let caretInset = 4.0
    /// A caret label's body may reach this far into another target before
    /// the place under its own target counts as taken.
    public static let crowdSlack = 3.0
    /// A label resting on its target has its body this far inside the
    /// target's left edge, and this far below the top of a tall target.
    public static let restInset = 2.0
    /// A resting label is centred vertically on a target that is at most
    /// this much taller than the label's body.
    public static let restCentering = 8.0

    /// Body of the label, without the margin.
    public static func bodySize(spec: HintLabelSpec, textWidth: Double, capHeight: Double) -> HintBadgeSize {
        let height = (max(capHeight, 0) + spec.paddingY * 2).rounded(.up)
        let minimum = spec.cornerRadius == nil ? height + 4 : height
        let width = max((max(textWidth, 0) + spec.paddingX * 2).rounded(.up), minimum)
        return HintBadgeSize(width: width, height: height)
    }

    /// Frame handed to placement: the body and the margin around it.
    public static func size(spec: HintLabelSpec, textWidth: Double, capHeight: Double) -> HintBadgeSize {
        let body = bodySize(spec: spec, textWidth: textWidth, capHeight: capHeight)
        return HintBadgeSize(width: body.width + spec.margin * 2, height: body.height + spec.margin * 2)
    }

    public static func radius(spec: HintLabelSpec, bodyHeight: Double) -> Double {
        min(spec.cornerRadius ?? bodyHeight / 2, bodyHeight / 2)
    }
}

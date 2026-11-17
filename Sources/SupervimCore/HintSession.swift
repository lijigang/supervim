import Foundation

public struct HintPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Rectangle in the coordinate space the caller already chose.
/// This type does not flip AppKit or Quartz origins.
public struct HintRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// A label needs a positive area and a finite center to click.
    public var isUsable: Bool {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else {
            return false
        }
        guard width > 0, height > 0 else {
            return false
        }
        let centerX = x + width / 2
        let centerY = y + height / 2
        return centerX.isFinite && centerY.isFinite
    }

    public var origin: HintPoint {
        HintPoint(x: x, y: y)
    }

    public var center: HintPoint {
        HintPoint(x: x + width / 2, y: y + height / 2)
    }
}

public struct HintTarget: Equatable, Sendable {
    public var frame: HintRect
    public var identifier: String?
    public var canAccessibilityPress: Bool

    public init(frame: HintRect, identifier: String? = nil, canAccessibilityPress: Bool = false) {
        self.frame = frame
        self.identifier = identifier
        self.canAccessibilityPress = canAccessibilityPress
    }
}

/// One label drawn on an element. `text` is the uppercase display form.
/// `anchor` is the element's origin, which sits on the frame.
public struct HintMarker: Equatable, Sendable {
    public var index: Int
    public var text: String
    public var anchor: HintPoint
    /// Accessibility frame size. The anchor is the top-left in accessibility space.
    public var elementWidth: Double
    public var elementHeight: Double

    public init(
        index: Int,
        text: String,
        anchor: HintPoint,
        elementWidth: Double = 0,
        elementHeight: Double = 0
    ) {
        self.index = index
        self.text = text
        self.anchor = anchor
        self.elementWidth = elementWidth
        self.elementHeight = elementHeight
    }
}

/// A finished label. The caller clicks `point` with `click`.
/// `index` is into the usable targets, after unusable frames were dropped.
public struct HintActivation: Equatable, Sendable {
    public var index: Int
    public var click: HintClick
    public var point: HintPoint
    public var identifier: String?
    public var canAccessibilityPress: Bool

    public init(
        index: Int,
        click: HintClick,
        point: HintPoint,
        identifier: String?,
        canAccessibilityPress: Bool = false
    ) {
        self.index = index
        self.click = click
        self.point = point
        self.identifier = identifier
        self.canAccessibilityPress = canAccessibilityPress
    }
}

public enum HintSessionOutcome: Equatable, Sendable {
    case showing([HintMarker])
    case activated(HintActivation)
    case cancelled
    case inactive
}

public enum HintKeyResolution: Equatable, Sendable {
    case input(HintLabelInput)
    case cancel
}

/// Maps a key the event interpreter already accepted onto a hint input.
///
/// `backspaceKeyCode` is the ANSI Delete virtual key, `0x33`. It belongs to the
/// same unconfirmed virtual-key table as `SystemKeyTranslation`. Escape and any
/// other unnamed key cancel. A character is a hint character even when Shift,
/// Control, Option, or Command is held; those modifiers do not change `f` into `F`.
public enum HintTyping {
    public static let backspaceKeyCode: UInt16 = 0x33

    public static func resolve(_ event: KeyEvent, keyCode: UInt16? = nil) -> HintKeyResolution {
        switch event.identity {
        case .character(let character):
            return .input(.character(character))
        case .escape:
            return .cancel
        case .unnamed:
            if keyCode == backspaceKeyCode {
                return .input(.backspace)
            }
            return .cancel
        }
    }
}

/// One `f` or `F` labeling pass over targets the caller already collected.
///
/// Labels come from `HintLabeler`. A partial prefix only filters. The click
/// happens when the typed text equals one full label. Invalid input and
/// `cancel()` leave the session inactive and do not activate. This value does
/// not draw and does not click.
public struct HintSession: Sendable {
    public let click: HintClick

    private var targets: [HintTarget]
    private var labeler: HintLabeler
    private var active: Bool

    public init(targets: [HintTarget], click: HintClick) {
        let usable = targets.filter(\.frame.isUsable)
        self.targets = usable
        self.labeler = HintLabeler(elementCount: usable.count)
        self.click = click
        self.active = !usable.isEmpty
    }

    public var isActive: Bool {
        active
    }

    public var markers: [HintMarker] {
        guard active else {
            return []
        }
        return Self.markers(for: labeler.filter, targets: targets)
    }

    public mutating func handle(_ input: HintLabelInput) -> HintSessionOutcome {
        guard active else {
            return .inactive
        }
        switch labeler.handle(input) {
        case .noMatch:
            active = false
            return .cancelled
        case .selected(let query):
            guard let index = query.selectedIndex, targets.indices.contains(index) else {
                active = false
                return .cancelled
            }
            active = false
            let target = targets[index]
            return .activated(
                HintActivation(
                    index: index,
                    click: click,
                    point: HintGeometry.clickPoint(element: target.frame),
                    identifier: target.identifier,
                    canAccessibilityPress: target.canAccessibilityPress
                )
            )
        case .pending(let query):
            return .showing(Self.markers(for: query, targets: targets))
        }
    }

    public mutating func cancel() -> HintSessionOutcome {
        guard active else {
            return .inactive
        }
        active = false
        return .cancelled
    }

    private static func markers(for query: HintQuery, targets: [HintTarget]) -> [HintMarker] {
        query.matches.compactMap { label in
            guard targets.indices.contains(label.index) else {
                return nil
            }
            let target = targets[label.index]
            return HintMarker(
                index: label.index,
                text: label.displayText,
                anchor: target.frame.origin,
                elementWidth: target.frame.width,
                elementHeight: target.frame.height
            )
        }
    }
}

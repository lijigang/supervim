import Foundation
import SupervimCore

public struct ActuatorPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ActuatorRect: Equatable, Sendable {
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

    /// Inclusive on every edge. A non-positive size contains nothing.
    /// Non-finite coordinates contain nothing.
    public func contains(_ point: ActuatorPoint) -> Bool {
        guard width > 0, height > 0, point.x.isFinite, point.y.isFinite else {
            return false
        }
        return point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
    }
}

/// One accessibility scroll area the caller already found.
/// `depth` is larger for a more deeply nested area.
/// `travel*` is the remaining distance in that direction, in points.
/// Zero or less means that edge is already reached.
/// `contentWidth` / `contentHeight` are the full scrolled size.
/// Nil means the caller does not know it.
public struct ScrollArea: Equatable, Sendable {
    public var identifier: String
    public var frame: ActuatorRect
    public var depth: Int
    public var containsPointer: Bool
    public var isFocusContainer: Bool
    public var visibleWidth: Double
    public var visibleHeight: Double
    public var travelLeft: Double
    public var travelDown: Double
    public var travelUp: Double
    public var travelRight: Double
    public var contentWidth: Double?
    public var contentHeight: Double?

    public init(
        identifier: String,
        frame: ActuatorRect,
        depth: Int,
        containsPointer: Bool,
        isFocusContainer: Bool,
        visibleWidth: Double,
        visibleHeight: Double,
        travelLeft: Double,
        travelDown: Double,
        travelUp: Double,
        travelRight: Double,
        contentWidth: Double?,
        contentHeight: Double?
    ) {
        self.identifier = identifier
        self.frame = frame
        self.depth = depth
        self.containsPointer = containsPointer
        self.isFocusContainer = isFocusContainer
        self.visibleWidth = visibleWidth
        self.visibleHeight = visibleHeight
        self.travelLeft = travelLeft
        self.travelDown = travelDown
        self.travelUp = travelUp
        self.travelRight = travelRight
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
    }
}

public struct ActuationContext: Equatable, Sendable {
    public var bundleIdentifier: String
    public var pointer: ActuatorPoint?
    public var scrollAreas: [ScrollArea]

    public init(bundleIdentifier: String, pointer: ActuatorPoint? = nil, scrollAreas: [ScrollArea] = []) {
        self.bundleIdentifier = bundleIdentifier
        self.pointer = pointer
        self.scrollAreas = scrollAreas
    }
}

public enum ClickKind: Equatable, Sendable {
    /// `f`. May use AXPress when the element supports it.
    case plain
    /// `F`. Left click with Command held. Never a context menu.
    case command
}

public struct ClickRequest: Equatable, Sendable {
    public var point: ActuatorPoint
    public var kind: ClickKind
    public var elementID: String?
    public var canAccessibilityPress: Bool

    public init(
        point: ActuatorPoint,
        kind: ClickKind,
        elementID: String? = nil,
        canAccessibilityPress: Bool = false
    ) {
        self.point = point
        self.kind = kind
        self.elementID = elementID
        self.canAccessibilityPress = canAccessibilityPress
    }
}

/// The actuator posts left clicks only. `F` is not a right-click.
public enum MouseButton: Equatable, Sendable {
    case left
}

public enum ActuatorEffect: Equatable, Sendable {
    case accessibilityPress(elementID: String)
    case mouseClick(point: ActuatorPoint, button: MouseButton, modifiers: KeyModifiers)
    /// Pixel wheel event aimed at the pointer. Positive vertical is up.
    /// Positive horizontal is to the right. Same sign as a Quartz scroll wheel.
    case pointerScroll(
        targetID: String,
        direction: ScrollDirection,
        amount: ScrollAmount,
        location: ActuatorPoint,
        horizontal: Int,
        vertical: Int
    )
    /// Accessibility scroll-bar change for a focus target, or for an edge.
    /// `pixels` is the magnitude. `scrollRange` is content size minus visible
    /// size. Nil means jump to the edge instead of nudging by pixels.
    case focusScroll(
        targetID: String,
        direction: ScrollDirection,
        amount: ScrollAmount,
        pixels: Int,
        scrollRange: Double?
    )
    case shortcut(KeyCombo)
}

public enum ActuatorOutcome: Equatable, Sendable {
    case performed([ActuatorEffect])
    case passedThrough
    case notActuatorWork
}

/// Bundle ids for the apps where yy, history, and tab shortcuts are promised.
///
/// Decision, not confirmed by the owner. The spec names Safari and Chromium
/// and does not list bundle identifiers. Chromium-family here is Chrome,
/// Chromium, Edge, Brave, Arc, and Vivaldi. Firefox and Opera are not included.
/// Comparison is exact: case and surrounding spaces are significant.
public enum PromisedApplications {
    public static let browserBundleIdentifiers: [String] = [
        "com.apple.Safari",
        "com.google.Chrome",
        "org.chromium.Chromium",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi",
    ]

    public static func isPromisedBrowser(_ bundleIdentifier: String) -> Bool {
        browserBundleIdentifiers.contains(bundleIdentifier)
    }
}

/// Mark on every event the actuator synthesizes.
/// The event tap passes a record with this source user data through and does
/// not parse it. ASCII "SVM1".
public enum SynthesizedEventMark {
    public static let userData: Int64 = 0x5356_4D31
}

public protocol ActuatorPosting: AnyObject, Sendable {
    func post(_ effect: ActuatorEffect)
}

/// Scroll hit rule.
///
/// The actuator scrolls one area, or it passes the action through.
/// It never scrolls a window that neither contains the pointer nor contains the focus.
///
/// 1. Pointer chain. Consider areas whose `containsPointer` flag is set and
///    whose frame contains the pointer. A nil pointer matches nothing.
///    Order them by `depth` descending, then by `identifier` ascending.
///    Walk that order and take the first area that can move in the requested
///    direction.
/// 2. Focus chain. If no pointer area can move, walk areas with
///    `isFocusContainer` in the same order, skipping an identifier already
///    considered, and take the first that can move.
/// 3. Otherwise pass through. Do not scroll a different window.
///
/// An area can move when its remaining travel in that direction is greater
/// than zero. Travel of zero or less is already at that edge, so the walk
/// continues. The pointer chain is finished before any focus-only area is
/// considered. That matches Vimium: the scroller under the cursor wins.
///
/// Point and half-page scrolls under the pointer become a pixel wheel event
/// aimed at the pointer. The same scrolls on a focus-only area become an
/// accessibility scroll-bar nudge, and only when that area's content size
/// on the axis is known, finite, and larger than its visible size.
/// A wheel event is not used for an edge, because a finite pixel delta is
/// not the end of the range. Edge scrolls set the accessibility scroll bar
/// to that edge, including when the pointer is over the area.
/// If a distance cannot be computed, that area is skipped. If nothing
/// remains, pass through.
public enum ScrollHitRule {
    public static func effect(
        areas: [ScrollArea],
        pointer: ActuatorPoint?,
        direction: ScrollDirection,
        amount: ScrollAmount
    ) -> ActuatorEffect? {
        let pointerAreas = ordered(areas.filter { isPointerTarget($0, pointer: pointer) })
        var seen: Set<String> = []
        for area in pointerAreas {
            seen.insert(area.identifier)
            if let effect = make(area, pointer: pointer, direction: direction, amount: amount, underPointer: true) {
                return effect
            }
        }
        let focusAreas = ordered(areas.filter(\.isFocusContainer))
        for area in focusAreas where !seen.contains(area.identifier) {
            if let effect = make(area, pointer: pointer, direction: direction, amount: amount, underPointer: false) {
                return effect
            }
        }
        return nil
    }

    private static func isPointerTarget(_ area: ScrollArea, pointer: ActuatorPoint?) -> Bool {
        guard area.containsPointer, let pointer else {
            return false
        }
        return area.frame.contains(pointer)
    }

    private static func ordered(_ areas: [ScrollArea]) -> [ScrollArea] {
        areas.sorted { lhs, rhs in
            if lhs.depth != rhs.depth {
                return lhs.depth > rhs.depth
            }
            return lhs.identifier < rhs.identifier
        }
    }

    private static func make(
        _ area: ScrollArea,
        pointer: ActuatorPoint?,
        direction: ScrollDirection,
        amount: ScrollAmount,
        underPointer: Bool
    ) -> ActuatorEffect? {
        guard travel(area, direction) > 0 else {
            return nil
        }
        switch amount {
        case .edge:
            return .focusScroll(
                targetID: area.identifier,
                direction: direction,
                amount: amount,
                pixels: 0,
                scrollRange: nil
            )
        case .points(let points):
            guard let pixels = pointCount(points) else {
                return nil
            }
            return pixelEffect(
                area,
                pointer: pointer,
                direction: direction,
                amount: amount,
                pixels: pixels,
                underPointer: underPointer
            )
        case .fractionOfPage(let numerator, let denominator):
            guard let pixels = fractionCount(
                numerator: numerator,
                denominator: denominator,
                visible: visibleSize(area, direction)
            ) else {
                return nil
            }
            return pixelEffect(
                area,
                pointer: pointer,
                direction: direction,
                amount: amount,
                pixels: pixels,
                underPointer: underPointer
            )
        }
    }

    private static func pixelEffect(
        _ area: ScrollArea,
        pointer: ActuatorPoint?,
        direction: ScrollDirection,
        amount: ScrollAmount,
        pixels: Int,
        underPointer: Bool
    ) -> ActuatorEffect? {
        if underPointer, let pointer {
            let signed = signedPixels(direction: direction, magnitude: pixels)
            return .pointerScroll(
                targetID: area.identifier,
                direction: direction,
                amount: amount,
                location: pointer,
                horizontal: signed.horizontal,
                vertical: signed.vertical
            )
        }
        guard let range = scrollRange(area, direction: direction) else {
            return nil
        }
        return .focusScroll(
            targetID: area.identifier,
            direction: direction,
            amount: amount,
            pixels: pixels,
            scrollRange: range
        )
    }

    private static func travel(_ area: ScrollArea, _ direction: ScrollDirection) -> Double {
        switch direction {
        case .left:
            return area.travelLeft
        case .down:
            return area.travelDown
        case .up:
            return area.travelUp
        case .right:
            return area.travelRight
        }
    }

    private static func visibleSize(_ area: ScrollArea, _ direction: ScrollDirection) -> Double {
        switch direction {
        case .left, .right:
            return area.visibleWidth
        case .up, .down:
            return area.visibleHeight
        }
    }

    private static func scrollRange(_ area: ScrollArea, direction: ScrollDirection) -> Double? {
        let content: Double?
        switch direction {
        case .left, .right:
            content = area.contentWidth
        case .up, .down:
            content = area.contentHeight
        }
        guard let content, content.isFinite else {
            return nil
        }
        let visible = visibleSize(area, direction)
        guard visible.isFinite, content > visible else {
            return nil
        }
        let range = content - visible
        guard range.isFinite, range > 0 else {
            return nil
        }
        return range
    }

    private static func pointCount(_ points: Int) -> Int? {
        guard points > 0, points <= Int(Int32.max) else {
            return nil
        }
        return points
    }

    /// Half a page rounds to the nearest point, with a tie moving away from zero.
    /// The result has to fit in a Quartz wheel delta. Otherwise the area is skipped.
    private static func fractionCount(numerator: Int, denominator: Int, visible: Double) -> Int? {
        guard numerator > 0, denominator > 0, visible.isFinite, visible > 0 else {
            return nil
        }
        let raw = visible * Double(numerator) / Double(denominator)
        guard raw.isFinite else {
            return nil
        }
        let rounded = raw.rounded(.toNearestOrAwayFromZero)
        guard rounded >= 1, rounded <= Double(Int32.max) else {
            return nil
        }
        return Int(rounded)
    }

    private static func signedPixels(direction: ScrollDirection, magnitude: Int) -> (horizontal: Int, vertical: Int) {
        switch direction {
        case .left:
            return (-magnitude, 0)
        case .right:
            return (magnitude, 0)
        case .up:
            return (0, magnitude)
        case .down:
            return (0, -magnitude)
        }
    }
}

/// Turns CommandMap actions into click, scroll, and shortcut effects.
/// The recording poster in tests is the stand-in for the system poster.
/// This type does not move the pointer itself.
public final class ActionActuator: @unchecked Sendable {
    private let poster: any ActuatorPosting

    public init(poster: any ActuatorPosting) {
        self.poster = poster
    }

    public func perform(_ action: Action, context: ActuationContext) -> ActuatorOutcome {
        switch plan(action, context: context) {
        case .notActuatorWork:
            return .notActuatorWork
        case .pass:
            return .passedThrough
        case .effects(let effects):
            for effect in effects {
                poster.post(effect)
            }
            return .performed(effects)
        }
    }

    public func click(_ request: ClickRequest) -> ActuatorOutcome {
        guard request.point.x.isFinite, request.point.y.isFinite else {
            return .passedThrough
        }
        let effect = clickEffect(request)
        poster.post(effect)
        return .performed([effect])
    }

    private func clickEffect(_ request: ClickRequest) -> ActuatorEffect {
        switch request.kind {
        case .command:
            return .mouseClick(point: request.point, button: .left, modifiers: .command)
        case .plain:
            if request.canAccessibilityPress, let identifier = trimmed(request.elementID) {
                return .accessibilityPress(elementID: identifier)
            }
            return .mouseClick(point: request.point, button: .left, modifiers: [])
        }
    }

    private func trimmed(_ identifier: String?) -> String? {
        guard let identifier else {
            return nil
        }
        let stripped = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    private enum Plan {
        case notActuatorWork
        case pass
        case effects([ActuatorEffect])
    }

    private func plan(_ action: Action, context: ActuationContext) -> Plan {
        switch action {
        case .beginHint, .showHelp, .focusFirstInput, .passNextKey, .escape, .enterInsert:
            return .notActuatorWork
        case .scroll(let direction, let amount):
            guard let effect = ScrollHitRule.effect(
                areas: context.scrollAreas,
                pointer: context.pointer,
                direction: direction,
                amount: amount
            ) else {
                return .pass
            }
            return .effects([effect])
        case .sendShortcut(let combo):
            if restrictsToPromisedBrowsers(action), !PromisedApplications.isPromisedBrowser(context.bundleIdentifier) {
                return .pass
            }
            guard SystemKeyTranslation.virtualKeyCode(forUnshifted: combo.character) != nil else {
                return .pass
            }
            return .effects([.shortcut(combo)])
        case .sequence(let steps):
            if restrictsToPromisedBrowsers(action), !PromisedApplications.isPromisedBrowser(context.bundleIdentifier) {
                return .pass
            }
            var effects: [ActuatorEffect] = []
            for step in steps {
                switch plan(step, context: context) {
                case .notActuatorWork:
                    return .notActuatorWork
                case .pass:
                    return .pass
                case .effects(let part):
                    effects.append(contentsOf: part)
                }
            }
            return .effects(effects)
        }
    }

    /// yy, history, and tab shortcuts are promised only for the allowlist.
    /// Close, new, reload, and find are not limited to those apps.
    private func restrictsToPromisedBrowsers(_ action: Action) -> Bool {
        switch action {
        case .sendShortcut(let combo):
            return isHistoryOrTab(combo)
        case .sequence(let steps):
            return isCopyURL(steps) || steps.contains(where: restrictsToPromisedBrowsers)
        case .scroll, .beginHint, .showHelp, .focusFirstInput, .passNextKey, .escape, .enterInsert:
            return false
        }
    }

    private func isHistoryOrTab(_ combo: KeyCombo) -> Bool {
        guard combo.character == "[" || combo.character == "]" else {
            return false
        }
        return combo.modifiers == .command || combo.modifiers == [.command, .shift]
    }

    private func isCopyURL(_ steps: [Action]) -> Bool {
        guard steps.count == 2,
              case .sendShortcut(let first) = steps[0],
              case .sendShortcut(let second) = steps[1]
        else {
            return false
        }
        return first == KeyCombo("l", modifiers: .command) && second == KeyCombo("c", modifiers: .command)
    }
}

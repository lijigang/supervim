import Foundation
import SupervimCore

/// Where to post a wheel when the accessibility tree has no scroll area.
///
/// The pointer is used when it is inside the front window. Otherwise the
/// wheel is posted at the window center. There is no wheel when the window
/// itself is missing: that case is logged and the key is not a silent swallow
/// from this type. The caller decides whether a held composer still swallows.
public enum ScrollFallback {
    public enum Source: Equatable, Sendable {
        case pointer
        case windowCenter
    }

    public struct Aim: Equatable, Sendable {
        public var point: ActuatorPoint
        public var source: Source

        public init(point: ActuatorPoint, source: Source) {
            self.point = point
            self.source = source
        }

        public func logLine(direction: ScrollDirection) -> String {
            let sourceName = source == .pointer ? "pointer" : "window-center"
            return "scroll-fallback direction=\(ScrollFallback.name(direction)) reason=no-scroll-area source=\(sourceName) x=\(point.x) y=\(point.y)"
        }
    }

    public static func aim(pointer: ActuatorPoint?, window: ActuatorRect?) -> Aim? {
        guard let window, usable(window) else {
            return nil
        }
        if let pointer, pointer.x.isFinite, pointer.y.isFinite, window.contains(pointer) {
            return Aim(point: pointer, source: .pointer)
        }
        return Aim(
            point: ActuatorPoint(x: window.x + window.width / 2, y: window.y + window.height / 2),
            source: .windowCenter
        )
    }

    public static func wheel(
        direction: ScrollDirection,
        amount: ScrollAmount,
        aim: Aim,
        window: ActuatorRect
    ) -> ActuatorEffect? {
        switch amount {
        case .edge:
            return .edgeScroll(
                targetID: "window",
                direction: direction,
                location: aim.point,
                role: nil
            )
        case .points(let points):
            guard let pixels = pointCount(points) else {
                return nil
            }
            let signed = signedPixels(direction: direction, magnitude: pixels)
            return .pointerScroll(
                targetID: "window",
                direction: direction,
                amount: amount,
                location: aim.point,
                horizontal: signed.horizontal,
                vertical: signed.vertical
            )
        case .fractionOfPage(let numerator, let denominator):
            let visible: Double
            switch direction {
            case .left, .right:
                visible = window.width
            case .up, .down:
                visible = window.height
            }
            guard let pixels = fractionCount(
                numerator: numerator,
                denominator: denominator,
                visible: visible
            ) else {
                return nil
            }
            let signed = signedPixels(direction: direction, magnitude: pixels)
            return .pointerScroll(
                targetID: "window",
                direction: direction,
                amount: amount,
                location: aim.point,
                horizontal: signed.horizontal,
                vertical: signed.vertical
            )
        }
    }

    public static func missLine(direction: ScrollDirection) -> String {
        "scroll-fallback direction=\(name(direction)) reason=no-window"
    }

    public static func targetLine(effect: ActuatorEffect, direction: ScrollDirection) -> String {
        switch effect {
        case .pointerScroll(let targetID, _, _, let location, _, _):
            return "scroll-target id=\(targetID) direction=\(name(direction)) x=\(location.x) y=\(location.y)"
        case .focusScroll(let targetID, _, _, _, _):
            return "scroll-target id=\(targetID) direction=\(name(direction)) x=- y=-"
        case .edgeScroll(let targetID, _, let location, _):
            return "scroll-target id=\(targetID) direction=\(name(direction)) x=\(location.x) y=\(location.y)"
        default:
            return "scroll-target id=- direction=\(name(direction)) x=- y=-"
        }
    }

    public static func name(_ direction: ScrollDirection) -> String {
        switch direction {
        case .left:
            return "left"
        case .right:
            return "right"
        case .up:
            return "up"
        case .down:
            return "down"
        }
    }

    private static func usable(_ window: ActuatorRect) -> Bool {
        window.width > 0 && window.height > 0 && window.x.isFinite && window.y.isFinite
            && window.width.isFinite && window.height.isFinite
    }

    private static func pointCount(_ points: Int) -> Int? {
        guard points > 0, points <= Int(Int32.max) else {
            return nil
        }
        return points
    }

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

/// The front window's accessibility frame when the accessibility tree has none.
/// The macOS reader uses `CGWindowList`. Tests supply a stand-in.
public protocol FrontWindowReading: AnyObject, Sendable {
    func frontWindowFrame() -> ActuatorRect?
}

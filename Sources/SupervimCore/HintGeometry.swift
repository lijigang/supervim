import Foundation

/// One display in the global coordinate space.
/// Index 0 is `NSScreen.screens[0]`, the primary screen. It is not
/// `NSScreen.main` and it is not the screen that contains the window.
/// `backingScale` is points-to-pixels. Placement stays in points.
public struct DisplayFrame: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var backingScale: Double

    public init(x: Double, y: Double, width: Double, height: Double, backingScale: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.backingScale = backingScale
    }
}

/// Accessibility frames and AppKit frames for one hint pass.
///
/// `AXPosition` is global, origin at the top-left of the primary screen, y down.
/// `NSWindow` is global, origin at the bottom-left of that same screen, y up.
/// `nsY = primaryHeight - axY - height`. x is shared, including negative x on
/// a display to the left of the primary. Scale is not applied.
public enum HintGeometry {
    /// Badge rect in AppKit points. The badge sits on the top of the element
    /// so its center stays inside the accessibility frame.
    public static func labelRect(
        element: HintRect,
        badgeWidth: Double,
        badgeHeight: Double,
        screens: [DisplayFrame]
    ) -> HintRect? {
        guard let primary = screens.first,
              primary.height.isFinite, primary.height > 0,
              element.isUsable,
              badgeWidth.isFinite, badgeHeight.isFinite,
              badgeWidth > 0, badgeHeight > 0
        else {
            return nil
        }
        _ = primary.backingScale
        let elementBottom = primary.height - element.y - element.height
        let badgeY = elementBottom + element.height - badgeHeight
        return HintRect(x: element.x, y: badgeY, width: badgeWidth, height: badgeHeight)
    }

    /// Quartz and accessibility share the top-left origin. The click is the
    /// center of the accessibility frame, not the flipped AppKit point.
    public static func clickPoint(element: HintRect) -> HintPoint {
        element.center
    }

    /// Global badge rects become one panel frame plus origins local to that frame.
    /// The panel is the union, so labels on two displays stay in one window.
    public static func arrange(badges: [HintRect]) -> (frame: HintRect, local: [HintRect])? {
        let usable = badges.filter(\.isUsable)
        guard let first = usable.first else {
            return nil
        }
        var minX = first.x
        var minY = first.y
        var maxX = first.x + first.width
        var maxY = first.y + first.height
        for badge in usable.dropFirst() {
            minX = min(minX, badge.x)
            minY = min(minY, badge.y)
            maxX = max(maxX, badge.x + badge.width)
            maxY = max(maxY, badge.y + badge.height)
        }
        let frame = HintRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let local = usable.map { badge in
            HintRect(x: badge.x - minX, y: badge.y - minY, width: badge.width, height: badge.height)
        }
        return (frame, local)
    }
}

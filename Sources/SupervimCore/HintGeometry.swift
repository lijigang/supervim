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

    /// The part of `element` that is actually on screen.
    ///
    /// Zero, non-finite, and fully off-window frames are dropped. A frame that
    /// hangs outside the window or the scroll/web viewport is clipped to the
    /// visible intersection, so the label and the click use that same rect.
    /// A huge box that only slivers into the viewport is dropped.
    public static func visibleElement(
        _ element: HintRect,
        window: HintRect?,
        viewports: [HintRect] = []
    ) -> HintRect? {
        guard element.isUsable else {
            return nil
        }
        var frame = element
        if let window {
            guard window.isUsable, let hit = intersection(frame, window) else {
                return nil
            }
            frame = hit
        }
        let containing = viewports.filter { viewport in
            viewport.isUsable && contains(viewport, element.center)
        }
        if let container = containing.min(by: { area($0) < area($1) }) {
            guard let hit = intersection(frame, container), usablePiece(hit, original: element) else {
                return nil
            }
            frame = hit
        } else if let best = bestOverlap(element, viewports: viewports) {
            let visible = best.hit
            let mostlyOutside = area(element) > area(visible) * 4
            let sliver = area(visible) < max(64, area(best.viewport) * 0.05)
            if mostlyOutside && sliver {
                return nil
            }
            if let hit = intersection(frame, visible), usablePiece(hit, original: element) {
                frame = hit
            }
        }
        guard usablePiece(frame, original: element) else {
            return nil
        }
        return frame
    }

    /// The part of `element` that its own containers leave visible.
    ///
    /// `ancestors` are the frames of the scroll and web areas the element is
    /// inside, outermost first. A frame that cannot hold a point is skipped.
    /// The element is cut by the window and then by each of them. An area
    /// elsewhere in the window is not part of the chain and does not clip.
    /// A huge box that only slivers into the innermost area is dropped.
    public static func visibleElement(
        _ element: HintRect,
        window: HintRect?,
        ancestors: [HintRect]
    ) -> HintRect? {
        guard element.isUsable else {
            return nil
        }
        var frame = element
        if let window {
            guard window.isUsable, let hit = intersection(frame, window) else {
                return nil
            }
            frame = hit
        }
        var innermost: HintRect?
        for ancestor in ancestors where ancestor.isUsable {
            guard let hit = intersection(frame, ancestor) else {
                return nil
            }
            frame = hit
            innermost = ancestor
        }
        if let innermost {
            let mostlyOutside = area(element) > area(frame) * 4
            let sliver = area(frame) < max(64, area(innermost) * 0.05)
            if mostlyOutside && sliver {
                return nil
            }
        }
        guard usablePiece(frame, original: element) else {
            return nil
        }
        return frame
    }

    /// Label, click, and the screen that contains the click.
    /// The click is the center of the clipped frame. Scale is not applied.
    public static func place(
        element: HintRect,
        window: HintRect?,
        viewports: [HintRect] = [],
        badgeWidth: Double,
        badgeHeight: Double,
        screens: [DisplayFrame]
    ) -> PlacedHint? {
        guard let visible = visibleElement(element, window: window, viewports: viewports),
              let label = labelRect(
                element: visible,
                badgeWidth: badgeWidth,
                badgeHeight: badgeHeight,
                screens: screens
              )
        else {
            return nil
        }
        let click = clickPoint(element: visible)
        let screenIndex = screenIndex(containingAX: click, screens: screens) ?? 0
        return PlacedHint(visible: visible, label: label, click: click, screenIndex: screenIndex)
    }

    /// Accessibility frame of one AppKit screen.
    /// Screen frames use the primary screen's bottom-left. Accessibility uses
    /// that screen's top-left, y down. x is shared, including a negative x.
    public static func accessibilityFrame(of screen: DisplayFrame, primaryHeight: Double) -> HintRect {
        HintRect(
            x: screen.x,
            y: primaryHeight - (screen.y + screen.height),
            width: screen.width,
            height: screen.height
        )
    }

    public static func screenIndex(containingAX point: HintPoint, screens: [DisplayFrame]) -> Int? {
        guard let primary = screens.first, primary.height > 0, point.x.isFinite, point.y.isFinite else {
            return nil
        }
        for (index, screen) in screens.enumerated() {
            let ax = accessibilityFrame(of: screen, primaryHeight: primary.height)
            if contains(ax, point) {
                return index
            }
        }
        return nil
    }

    /// Moves later badges off earlier ones. The click point is not a badge
    /// and is left where `clickPoint` put it.
    public static func nudge(_ labels: [HintRect]) -> [HintRect] {
        var placed: [HintRect] = []
        for label in labels {
            var next = label
            guard next.isUsable else {
                placed.append(next)
                continue
            }
            var steps = 0
            while steps < 16, let other = placed.first(where: { intersects($0, next) }) {
                let shift = other.x + other.width - next.x + 2
                next.x += shift > 0 ? shift : 2
                steps += 1
            }
            placed.append(next)
        }
        return placed
    }

    /// One panel per screen. A window that crosses two displays is not used,
    /// because those displays can have different backing scales.
    public static func panels(labels: [HintRect], screens: [DisplayFrame]) -> [HintPanelPlacement] {
        let usable = labels.enumerated().filter { $0.element.isUsable }
        guard !usable.isEmpty else {
            return []
        }
        if screens.isEmpty {
            let badges = usable.map(\.element)
            guard let arranged = arrange(badges: badges) else {
                return []
            }
            let items = zip(usable, arranged.local).map { entry, local in
                HintPanelItem(sourceIndex: entry.offset, local: local)
            }
            return [HintPanelPlacement(screenIndex: 0, frame: arranged.frame, items: items, backingScale: 1)]
        }
        var groups: [Int: [(offset: Int, label: HintRect)]] = [:]
        for entry in usable {
            let index = screens.firstIndex { containsScreen($0, entry.element.center) }
                ?? nearestIndex(screens, point: entry.element.center)
            groups[index, default: []].append((entry.offset, entry.element))
        }
        return groups.keys.sorted().compactMap { index in
            guard let group = groups[index], screens.indices.contains(index) else {
                return nil
            }
            guard let arranged = arrange(badges: group.map(\.label)) else {
                return nil
            }
            let items = zip(group, arranged.local).map { entry, local in
                HintPanelItem(sourceIndex: entry.offset, local: local)
            }
            return HintPanelPlacement(
                screenIndex: index,
                frame: arranged.frame,
                items: items,
                backingScale: screens[index].backingScale
            )
        }
    }

    private static func bestOverlap(
        _ element: HintRect,
        viewports: [HintRect]
    ) -> (viewport: HintRect, hit: HintRect)? {
        var best: (viewport: HintRect, hit: HintRect)?
        for viewport in viewports where viewport.isUsable {
            guard let hit = intersection(element, viewport) else {
                continue
            }
            if best == nil || area(hit) > area(best!.hit) {
                best = (viewport, hit)
            }
        }
        return best
    }

    private static func usablePiece(_ frame: HintRect, original: HintRect) -> Bool {
        guard frame.isUsable else {
            return false
        }
        if frame.width < 4 || frame.height < 4 {
            return original.width < 4 || original.height < 4
        }
        return true
    }

    private static func intersection(_ lhs: HintRect, _ rhs: HintRect) -> HintRect? {
        guard lhs.isUsable, rhs.isUsable else {
            return nil
        }
        let x = max(lhs.x, rhs.x)
        let y = max(lhs.y, rhs.y)
        let maxX = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let maxY = min(lhs.y + lhs.height, rhs.y + rhs.height)
        guard maxX > x, maxY > y else {
            return nil
        }
        return HintRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    private static func intersects(_ lhs: HintRect, _ rhs: HintRect) -> Bool {
        intersection(lhs, rhs) != nil
    }

    private static func contains(_ frame: HintRect, _ point: HintPoint) -> Bool {
        guard frame.isUsable, point.x.isFinite, point.y.isFinite else {
            return false
        }
        return point.x >= frame.x && point.x <= frame.x + frame.width
            && point.y >= frame.y && point.y <= frame.y + frame.height
    }

    private static func containsScreen(_ screen: DisplayFrame, _ point: HintPoint) -> Bool {
        guard screen.width > 0, screen.height > 0, point.x.isFinite, point.y.isFinite else {
            return false
        }
        return point.x >= screen.x && point.x <= screen.x + screen.width
            && point.y >= screen.y && point.y <= screen.y + screen.height
    }

    private static func nearestIndex(_ screens: [DisplayFrame], point: HintPoint) -> Int {
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, screen) in screens.enumerated() {
            let cx = min(max(point.x, screen.x), screen.x + screen.width)
            let cy = min(max(point.y, screen.y), screen.y + screen.height)
            let dx = point.x - cx
            let dy = point.y - cy
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private static func area(_ frame: HintRect) -> Double {
        let value = frame.width * frame.height
        return value.isFinite && value > 0 ? value : 0
    }
}

public struct PlacedHint: Equatable, Sendable {
    public var visible: HintRect
    public var label: HintRect
    public var click: HintPoint
    public var screenIndex: Int

    public init(visible: HintRect, label: HintRect, click: HintPoint, screenIndex: Int) {
        self.visible = visible
        self.label = label
        self.click = click
        self.screenIndex = screenIndex
    }
}

public struct HintPanelItem: Equatable, Sendable {
    public var sourceIndex: Int
    public var local: HintRect

    public init(sourceIndex: Int, local: HintRect) {
        self.sourceIndex = sourceIndex
        self.local = local
    }
}

public struct HintPanelPlacement: Equatable, Sendable {
    public var screenIndex: Int
    public var frame: HintRect
    public var items: [HintPanelItem]
    public var backingScale: Double

    public init(screenIndex: Int, frame: HintRect, items: [HintPanelItem], backingScale: Double) {
        self.screenIndex = screenIndex
        self.frame = frame
        self.items = items
        self.backingScale = backingScale
    }
}

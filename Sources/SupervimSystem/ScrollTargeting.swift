import Foundation
import SupervimCore

/// Where a scroll goes, and whether the pointer has to move first.
public struct ScrollAim: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable {
        /// A scroll area under the pointer. The wheel is posted where the pointer is.
        case underPointer = "under-pointer"
        /// The pointer is in the front window and no better area is known.
        case pointer
        /// The focused area, or the largest one. The pointer is moved to its center.
        case area
        /// No area is known and the pointer is not in the window.
        case windowCenter = "window-center"
    }

    public var targetID: String
    public var role: String?
    public var location: ActuatorPoint
    public var movesPointer: Bool
    public var source: Source
    /// Visible size of the target in points: width, then height.
    public var page: (width: Double, height: Double)?

    public static func == (lhs: ScrollAim, rhs: ScrollAim) -> Bool {
        lhs.targetID == rhs.targetID && lhs.role == rhs.role && lhs.location == rhs.location
            && lhs.movesPointer == rhs.movesPointer && lhs.source == rhs.source
            && lhs.page?.width == rhs.page?.width && lhs.page?.height == rhs.page?.height
    }
}

/// Picks the scroll target for `j` `k` `h` `l` `d` `u` `gg` `G`.
///
/// macOS delivers a wheel event to the view under the pointer. The event's
/// own location does not redirect it. So a scroll either goes where the
/// pointer already is, or the pointer is moved first.
///
/// 1. A scroll area under the pointer that can scroll on the requested axis
///    takes the wheel where the pointer is. The deepest one names the target.
/// 2. Otherwise the best area is the deepest scrollable one that holds the
///    focus, or else the largest scrollable one. The focused text input
///    itself is never the best area while Normal is held on it.
/// 3. With the pointer in the front window, the pointer moves to the best
///    area only when that area covers at least half the window, or when
///    Normal is held on a text input. A smaller area somewhere else may be
///    the wrong pane, so the wheel is posted where the pointer is.
/// 4. With the pointer outside the front window, it moves to the best area,
///    or to the window center when there is none.
/// 5. With no window and no area, the wheel is posted at the pointer.
///    With no pointer either, the key passes through.
/// 6. While Normal is held on a text input, a wheel that would land on that
///    input goes to the window center instead, or nowhere.
///
/// Remaining travel is not consulted. It was read when focus last changed
/// and says nothing about where the page is now. An area counts as
/// scrollable on an axis when its travel on that axis was not zero in both
/// directions, which is false only for content that fits.
public enum ScrollTargeting {
    public static let dominantWindowShare = 0.5
    public static let unknownPage = 600.0

    public static func aim(context: ActuationContext, direction: ScrollDirection) -> ScrollAim? {
        guard let found = unguarded(context: context, direction: direction) else {
            return nil
        }
        // Normal held on a text input must never scroll that input.
        guard let composer = usable(context.composerFrame), composer.contains(found.location) else {
            return found
        }
        guard let window = usable(context.windowFrame), !composer.contains(center(window)) else {
            return nil
        }
        return ScrollAim(
            targetID: "window",
            role: nil,
            location: center(window),
            movesPointer: true,
            source: .windowCenter,
            page: (window.width, window.height)
        )
    }

    private static func unguarded(context: ActuationContext, direction: ScrollDirection) -> ScrollAim? {
        let pointer = usable(context.pointer)
        let window = usable(context.windowFrame)
        let areas = candidates(context, direction: direction)

        if let pointer,
           let hit = deepest(areas.filter { $0.frame.contains(pointer) }) {
            return make(hit, at: pointer, moves: false, source: .underPointer)
        }
        let holding = context.composerFrame != nil
        let focused = holding ? nil : deepest(areas.filter(\.isFocusContainer))
        let best = focused ?? largest(areas)
        let inWindow = pointer.map { point in window?.contains(point) ?? true } ?? false
        if inWindow, let pointer {
            if let best, holding || dominates(best, window: window) {
                return make(best, at: center(best.frame), moves: true, source: .area)
            }
            return ScrollAim(
                targetID: "window",
                role: nil,
                location: pointer,
                movesPointer: false,
                source: .pointer,
                page: window.map { ($0.width, $0.height) }
            )
        }
        if let best {
            return make(best, at: center(best.frame), moves: true, source: .area)
        }
        if let window {
            return ScrollAim(
                targetID: "window",
                role: nil,
                location: center(window),
                movesPointer: true,
                source: .windowCenter,
                page: (window.width, window.height)
            )
        }
        if let pointer {
            return ScrollAim(
                targetID: "window",
                role: nil,
                location: pointer,
                movesPointer: false,
                source: .pointer,
                page: nil
            )
        }
        return nil
    }

    /// The pointer move, when one is needed, then the wheel or the edge scroll.
    public static func effects(
        context: ActuationContext,
        direction: ScrollDirection,
        amount: ScrollAmount
    ) -> [ActuatorEffect]? {
        guard let aim = aim(context: context, direction: direction) else {
            return nil
        }
        let scroll: ActuatorEffect
        switch amount {
        case .edge:
            scroll = .edgeScroll(
                targetID: aim.targetID,
                direction: direction,
                location: aim.location,
                role: aim.role
            )
        case .points(let points):
            guard points > 0, points <= Int(Int32.max) else {
                return nil
            }
            scroll = wheel(aim, direction: direction, amount: amount, pixels: points)
        case .fractionOfPage(let numerator, let denominator):
            guard numerator > 0, denominator > 0 else {
                return nil
            }
            let page: Double
            switch direction {
            case .left, .right:
                page = aim.page?.width ?? unknownPage
            case .up, .down:
                page = aim.page?.height ?? unknownPage
            }
            let raw = (page * Double(numerator) / Double(denominator)).rounded(.toNearestOrAwayFromZero)
            guard raw.isFinite, raw >= 1, raw <= Double(Int32.max) else {
                return nil
            }
            scroll = wheel(aim, direction: direction, amount: amount, pixels: Int(raw))
        }
        return aim.movesPointer ? [.pointerMove(to: aim.location), scroll] : [scroll]
    }

    public static func logLine(_ aim: ScrollAim, direction: ScrollDirection) -> String {
        "scroll-target id=\(aim.targetID) direction=\(ScrollFallback.name(direction)) source=\(aim.source.rawValue)"
            + " move=\(aim.movesPointer ? 1 : 0) x=\(aim.location.x) y=\(aim.location.y)"
    }

    private static func wheel(
        _ aim: ScrollAim,
        direction: ScrollDirection,
        amount: ScrollAmount,
        pixels: Int
    ) -> ActuatorEffect {
        let horizontal: Int
        let vertical: Int
        switch direction {
        case .left:
            (horizontal, vertical) = (-pixels, 0)
        case .right:
            (horizontal, vertical) = (pixels, 0)
        case .up:
            (horizontal, vertical) = (0, pixels)
        case .down:
            (horizontal, vertical) = (0, -pixels)
        }
        return .pointerScroll(
            targetID: aim.targetID,
            direction: direction,
            amount: amount,
            location: aim.location,
            horizontal: horizontal,
            vertical: vertical
        )
    }

    private static func candidates(_ context: ActuationContext, direction: ScrollDirection) -> [ScrollArea] {
        var seen = Set<String>()
        var result: [ScrollArea] = []
        for area in context.scrollAreas + context.structuralAreas {
            guard seen.insert(area.identifier).inserted else {
                continue
            }
            guard usable(area.frame) != nil, scrollable(area, direction) else {
                continue
            }
            if let composer = context.composerFrame, ContentScroll.isFocusedInput(area, composer) {
                continue
            }
            result.append(area)
        }
        return result
    }

    private static func scrollable(_ area: ScrollArea, _ direction: ScrollDirection) -> Bool {
        switch direction {
        case .left, .right:
            return area.travelLeft > 0 || area.travelRight > 0
        case .up, .down:
            return area.travelUp > 0 || area.travelDown > 0
        }
    }

    private static func make(
        _ area: ScrollArea,
        at location: ActuatorPoint,
        moves: Bool,
        source: ScrollAim.Source
    ) -> ScrollAim {
        ScrollAim(
            targetID: area.identifier,
            role: area.role,
            location: location,
            movesPointer: moves,
            source: source,
            page: (area.visibleWidth, area.visibleHeight)
        )
    }

    private static func deepest(_ areas: [ScrollArea]) -> ScrollArea? {
        areas.max { lhs, rhs in
            if lhs.depth != rhs.depth {
                return lhs.depth < rhs.depth
            }
            let left = size(lhs.frame)
            let right = size(rhs.frame)
            if left != right {
                return left > right
            }
            return lhs.identifier > rhs.identifier
        }
    }

    private static func largest(_ areas: [ScrollArea]) -> ScrollArea? {
        areas.max { lhs, rhs in
            let left = size(lhs.frame)
            let right = size(rhs.frame)
            if left != right {
                return left < right
            }
            return lhs.identifier > rhs.identifier
        }
    }

    private static func dominates(_ area: ScrollArea, window: ActuatorRect?) -> Bool {
        guard let window else {
            return false
        }
        let x = max(area.frame.x, window.x)
        let y = max(area.frame.y, window.y)
        let maxX = min(area.frame.x + area.frame.width, window.x + window.width)
        let maxY = min(area.frame.y + area.frame.height, window.y + window.height)
        guard maxX > x, maxY > y else {
            return false
        }
        return (maxX - x) * (maxY - y) >= size(window) * dominantWindowShare
    }

    private static func size(_ rect: ActuatorRect) -> Double {
        let value = rect.width * rect.height
        return value.isFinite && value > 0 ? value : 0
    }

    private static func center(_ rect: ActuatorRect) -> ActuatorPoint {
        ActuatorPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
    }

    private static func usable(_ point: ActuatorPoint?) -> ActuatorPoint? {
        guard let point, point.x.isFinite, point.y.isFinite else {
            return nil
        }
        return point
    }

    private static func usable(_ rect: ActuatorRect?) -> ActuatorRect? {
        guard let rect, rect.x.isFinite, rect.y.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0
        else {
            return nil
        }
        return rect
    }
}

import Foundation
import SupervimCore

/// One scroll bar copied from an accessibility element.
///
/// `contentLength` is the full scrolled size in points. Nil means the reader
/// does not know it. A 0...1 bar is not treated as a point length.
public struct ScrollBarReading: Equatable, Sendable {
    public var value: Double
    public var minimum: Double
    public var maximum: Double
    public var contentLength: Double?

    public init(value: Double, minimum: Double, maximum: Double, contentLength: Double?) {
        self.value = value
        self.minimum = minimum
        self.maximum = maximum
        self.contentLength = contentLength
    }
}

/// Scroll areas from one window read. `ready` is false when the walk was cut
/// off. In that case `areas` is empty: a partial list is not a target list.
public struct ScrollCatalog: Equatable, Sendable {
    public var areas: [ScrollArea]
    public var ready: Bool
    /// `AXScrollArea` / `AXWebArea` frames, including ones with no scroll bar.
    /// Electron history lists often have no bar. The key path uses these only
    /// while Normal is held over a text input. They are not `areas`.
    public var structural: [ScrollArea]

    public init(areas: [ScrollArea], ready: Bool, structural: [ScrollArea] = []) {
        self.areas = areas
        self.ready = ready
        self.structural = structural
    }
}

/// Path key shared by the catalog and the live accessibility element store.
/// An empty path is the window root. A child path is indexes joined by `/`.
public enum ScrollTargetIdentity {
    public static func identifier(path: [Int]) -> String {
        if path.isEmpty {
            return "root"
        }
        return path.map(String.init).joined(separator: "/")
    }
}

/// Scroll targets copied from a window that was already read off the key hook.
///
/// A node with no usable scroll bar is not a target. Role `AXScrollArea` alone
/// is not enough: without a bar there is nothing to measure, and scrolling it
/// would be a guess. A bar is usable when value, minimum, and maximum are
/// finite and maximum is greater than minimum.
///
/// Remaining travel is in points when `contentLength` is finite and greater
/// than the visible side. Otherwise travel is 1 when the bar is off that edge
/// and 0 when it is on the edge, and the content length stays nil. A later
/// focus-only point scroll can still pass through when the length is unknown.
///
/// `containsPointer` is true only when the pointer lies in the frame, including
/// the edges. `isFocusContainer` uses the same test for the focus point.
/// The window root is identifier `root` at depth 0. A child uses its index
/// path joined by `/`, and its depth is the path length.
/// A frame that is not finite and positive is skipped.
/// Truncation drops every area. A partial tree is not a target list: a deeper
/// area under the pointer may have been cut off, and the key must pass through
/// rather than scroll a guess.
public enum ScrollAreaCatalog {
    public static func collect(
        window: AccessibilityElement,
        pointer: ActuatorPoint?,
        focus: ActuatorPoint?,
        limits: TreeWalkLimits = .standard
    ) -> ScrollCatalog {
        var areas: [ScrollArea] = []
        var structural: [ScrollArea] = []
        let truncated = walk(window, limits: limits) { node, path, isRoot in
            if let area = makeArea(node, path: path, isRoot: isRoot, pointer: pointer, focus: focus) {
                areas.append(area)
            }
            if let wheel = structuralArea(node, path: path, isRoot: isRoot) {
                structural.append(wheel)
            }
        }
        if truncated {
            return ScrollCatalog(areas: [], ready: false, structural: [])
        }
        return ScrollCatalog(areas: areas, ready: true, structural: structural)
    }

    /// Recomputes pointer and focus flags from frames. Does not walk a tree.
    /// A nil pointer or focus clears that flag, including a stale `true`.
    public static func retarget(
        _ areas: [ScrollArea],
        pointer: ActuatorPoint?,
        focus: ActuatorPoint?
    ) -> [ScrollArea] {
        areas.map { area in
            var copy = area
            copy.containsPointer = contains(area.frame, pointer)
            copy.isFocusContainer = contains(area.frame, focus)
            return copy
        }
    }

    /// Center of a positive finite frame. Nil when the frame cannot hold a point.
    public static func focusPoint(of frame: ElementFrame?) -> ActuatorPoint? {
        guard let frame,
              frame.x.isFinite, frame.y.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0
        else {
            return nil
        }
        return ActuatorPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
    }

    private struct Axis {
        var towardMinimum: Double
        var towardMaximum: Double
        var content: Double?
    }

    private static func makeArea(
        _ node: AccessibilityElement,
        path: [Int],
        isRoot: Bool,
        pointer: ActuatorPoint?,
        focus: ActuatorPoint?
    ) -> ScrollArea? {
        guard let rect = usableRect(node.frame) else {
            return nil
        }
        let vertical = measure(node.verticalScroll, visible: rect.height)
        let horizontal = measure(node.horizontalScroll, visible: rect.width)
        if vertical == nil, horizontal == nil {
            return nil
        }
        return ScrollArea(
            identifier: ScrollTargetIdentity.identifier(path: isRoot ? [] : path),
            frame: rect,
            depth: isRoot ? 0 : path.count,
            containsPointer: contains(rect, pointer),
            isFocusContainer: contains(rect, focus),
            visibleWidth: rect.width,
            visibleHeight: rect.height,
            travelLeft: horizontal?.towardMinimum ?? 0,
            travelDown: vertical?.towardMaximum ?? 0,
            travelUp: vertical?.towardMinimum ?? 0,
            travelRight: horizontal?.towardMaximum ?? 0,
            contentWidth: horizontal?.content,
            contentHeight: vertical?.content,
            role: node.role,
            isTextInput: false
        )
    }

    /// A web or scroll area with a positive frame can take a wheel event even
    /// when it has no accessibility scroll bar. Travel is 1 so the aim rule
    /// does not treat the unknown edge as "already there".
    private static func structuralArea(
        _ node: AccessibilityElement,
        path: [Int],
        isRoot: Bool
    ) -> ScrollArea? {
        guard node.role == "AXScrollArea" || node.role == "AXWebArea" else {
            return nil
        }
        guard let rect = usableRect(node.frame) else {
            return nil
        }
        return ScrollArea(
            identifier: ScrollTargetIdentity.identifier(path: isRoot ? [] : path),
            frame: rect,
            depth: isRoot ? 0 : path.count,
            containsPointer: false,
            isFocusContainer: false,
            visibleWidth: rect.width,
            visibleHeight: rect.height,
            travelLeft: 1,
            travelDown: 1,
            travelUp: 1,
            travelRight: 1,
            contentWidth: nil,
            contentHeight: nil,
            role: node.role,
            isTextInput: false
        )
    }

    private static func measure(_ bar: ScrollBarReading?, visible: Double) -> Axis? {
        guard let bar, bar.value.isFinite, bar.minimum.isFinite, bar.maximum.isFinite else {
            return nil
        }
        let span = bar.maximum - bar.minimum
        guard span.isFinite, span > 0 else {
            return nil
        }
        let towardMinimum = (bar.value - bar.minimum) / span
        let towardMaximum = (bar.maximum - bar.value) / span
        guard towardMinimum.isFinite, towardMaximum.isFinite else {
            return nil
        }
        if let length = bar.contentLength, length.isFinite {
            if visible.isFinite, visible > 0, length > visible {
                let range = length - visible
                return Axis(
                    towardMinimum: points(towardMinimum * range),
                    towardMaximum: points(towardMaximum * range),
                    content: length
                )
            }
            return Axis(towardMinimum: 0, towardMaximum: 0, content: length)
        }
        return Axis(
            towardMinimum: towardMinimum > 0 ? 1 : 0,
            towardMaximum: towardMaximum > 0 ? 1 : 0,
            content: nil
        )
    }

    private static func points(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else {
            return 0
        }
        return value
    }

    private static func usableRect(_ frame: ElementFrame?) -> ActuatorRect? {
        guard let frame,
              frame.x.isFinite, frame.y.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0
        else {
            return nil
        }
        return ActuatorRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    private static func contains(_ rect: ActuatorRect, _ point: ActuatorPoint?) -> Bool {
        guard let point else {
            return false
        }
        return rect.contains(point)
    }

    private final class Cursor {
        var visited = 0
        var truncated = false
        let limits: TreeWalkLimits

        init(limits: TreeWalkLimits) {
            self.limits = limits
        }
    }

    private static func walk(
        _ root: AccessibilityElement,
        limits: TreeWalkLimits,
        _ body: (AccessibilityElement, [Int], Bool) -> Void
    ) -> Bool {
        let cursor = Cursor(limits: limits)
        visit(root, path: [], depth: 0, isRoot: true, cursor: cursor, body: body)
        return cursor.truncated
    }

    private static func visit(
        _ node: AccessibilityElement,
        path: [Int],
        depth: Int,
        isRoot: Bool,
        cursor: Cursor,
        body: (AccessibilityElement, [Int], Bool) -> Void
    ) {
        if cursor.truncated {
            return
        }
        cursor.visited += 1
        body(node, path, isRoot)
        if node.children.isEmpty {
            if node.childrenTruncated {
                cursor.truncated = true
            }
            return
        }
        if cursor.visited >= cursor.limits.maxNodes || depth >= cursor.limits.maxDepth {
            cursor.truncated = true
            return
        }
        for (index, child) in node.children.enumerated() {
            visit(child, path: path + [index], depth: depth + 1, isRoot: false, cursor: cursor, body: body)
            if cursor.truncated {
                return
            }
            if cursor.visited >= cursor.limits.maxNodes, index + 1 < node.children.count {
                cursor.truncated = true
                return
            }
        }
        if node.childrenTruncated {
            cursor.truncated = true
        }
    }
}

/// Scroll areas, focus point, and first-input query cached off the key hook.
public struct CommandSnapshot: Equatable, Sendable {
    public var scrollAreas: [ScrollArea]
    public var scrollCatalogReady: Bool
    public var firstInput: EditableInputQuery
    public var focusPoint: ActuatorPoint?
    public var structuralAreas: [ScrollArea]

    public init(
        scrollAreas: [ScrollArea],
        scrollCatalogReady: Bool,
        firstInput: EditableInputQuery,
        focusPoint: ActuatorPoint?,
        structuralAreas: [ScrollArea] = []
    ) {
        self.scrollAreas = scrollAreas
        self.scrollCatalogReady = scrollCatalogReady
        self.firstInput = firstInput
        self.focusPoint = focusPoint
        self.structuralAreas = structuralAreas
    }

    public static let unavailable = CommandSnapshot(
        scrollAreas: [],
        scrollCatalogReady: false,
        firstInput: .unavailable,
        focusPoint: nil
    )
}

/// Builds a snapshot from a window that was read outside the key hook.
/// The pointer is not part of the snapshot. The session reads it when the key arrives.
public enum CommandSnapshotBuilder {
    public static func make(
        window: AccessibilityRead<AccessibilityElement>,
        focusedFrame: ElementFrame?,
        firstInput: EditableInputQuery,
        limits: TreeWalkLimits = .standard
    ) -> CommandSnapshot {
        let focus = ScrollAreaCatalog.focusPoint(of: focusedFrame)
        switch window {
        case .unavailable:
            return CommandSnapshot(
                scrollAreas: [],
                scrollCatalogReady: false,
                firstInput: firstInput,
                focusPoint: focus,
                structuralAreas: []
            )
        case .value(let element):
            let catalog = ScrollAreaCatalog.collect(
                window: element,
                pointer: nil,
                focus: focus,
                limits: limits
            )
            return CommandSnapshot(
                scrollAreas: catalog.areas,
                scrollCatalogReady: catalog.ready,
                firstInput: firstInput,
                focusPoint: focus,
                structuralAreas: catalog.ready ? catalog.structural : []
            )
        }
    }
}

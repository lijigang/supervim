import Foundation

/// One box from an on-device vision pass.
///
/// `normalized` is Vision's bounding box: origin at the bottom-left of the
/// image, both axes 0...1, y up. It is not a screen point.
public struct VisionBox: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case text
        case rectangle
    }

    public var text: String
    public var normalized: HintRect
    public var kind: Kind

    public init(text: String, normalized: HintRect, kind: Kind) {
        self.text = text
        self.normalized = normalized
        self.kind = kind
    }
}

/// The captured front window. `frame` is in accessibility points: origin at
/// the top-left of the primary display, y down. `backingScale` is the scale
/// of the screen that contains the window, pixels per point.
public struct CapturedWindow: Equatable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var frame: HintRect
    public var backingScale: Double

    public init(pixelWidth: Int, pixelHeight: Int, frame: HintRect, backingScale: Double) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.frame = frame
        self.backingScale = backingScale
    }
}

/// When a hint pass may leave the accessibility tree and read the screen.
/// Accessibility stays first. Vision runs when that pass found nothing, and
/// also for bundle ids in the configured list.
public enum VisionHintPolicy {
    public static func shouldCapture(
        axHitCount: Int,
        bundleIdentifier: String,
        visionBundles: [String]
    ) -> Bool {
        if axHitCount <= 0 {
            return true
        }
        return visionBundles.contains(bundleIdentifier)
    }
}

/// Turns vision boxes into hint targets in accessibility coordinates.
///
/// Nothing here captures the screen or leaves the machine. Normalized
/// bottom-left boxes become pixels, then points divided by that screen's
/// scale, then accessibility points added to the window origin.
public enum VisionHintGeometry {
    public static func screenRect(normalized: HintRect, image: CapturedWindow) -> HintRect? {
        guard normalized.isUsable, image.frame.isUsable else {
            return nil
        }
        guard image.backingScale > 0, image.backingScale.isFinite else {
            return nil
        }
        guard image.pixelWidth > 0, image.pixelHeight > 0 else {
            return nil
        }
        let pixelX = normalized.x * Double(image.pixelWidth)
        let pixelW = normalized.width * Double(image.pixelWidth)
        let pixelH = normalized.height * Double(image.pixelHeight)
        let pixelY = (1 - normalized.y - normalized.height) * Double(image.pixelHeight)
        guard pixelW > 0, pixelH > 0, pixelX.isFinite, pixelY.isFinite else {
            return nil
        }
        let scale = image.backingScale
        let rect = HintRect(
            x: image.frame.x + pixelX / scale,
            y: image.frame.y + pixelY / scale,
            width: pixelW / scale,
            height: pixelH / scale
        )
        return rect.isUsable ? rect : nil
    }

    /// Lines of one list item, such as a WeChat name and its preview, become
    /// one row. A larger gap starts the next row.
    public static func mergeRows(_ boxes: [HintRect]) -> [HintRect] {
        let lines = groupLines(boxes.filter(\.isUsable))
        return groupRows(lines)
    }

    /// Drops a box that sits mostly inside a larger box.
    public static func dedupe(_ boxes: [HintRect], coverage: Double = 0.7) -> [HintRect] {
        let sorted = boxes.filter(\.isUsable).sorted { area($0) > area($1) }
        var kept: [HintRect] = []
        for box in sorted {
            let covered = kept.contains { existing in
                guard let hit = intersection(box, existing) else {
                    return false
                }
                let smaller = min(area(box), area(existing))
                return smaller > 0 && area(hit) / smaller >= coverage
            }
            if !covered {
                kept.append(box)
            }
        }
        return kept
    }

    /// Text lines become rows. A rectangle that sits on a row is dropped.
    /// A rectangle that does not is a button. `HintRanking` orders the result,
    /// and `HintSession` still assigns single letters first.
    public static func targets(boxes: [VisionBox], image: CapturedWindow) -> [HintTarget] {
        let converted: [(VisionBox, HintRect)] = boxes.compactMap { box in
            guard let rect = screenRect(normalized: box.normalized, image: image) else {
                return nil
            }
            return (box, rect)
        }
        let text = converted.filter { $0.0.kind == .text }.map(\.1)
        let rectangles = converted.filter { $0.0.kind == .rectangle }.map(\.1)
        let rows = mergeRows(dedupe(text))
        let icons = dedupe(rectangles).filter { icon in
            !rows.contains { row in
                guard let hit = intersection(icon, row), area(icon) > 0 else {
                    return false
                }
                return area(hit) / area(icon) >= 0.5
            }
        }
        var items: [HintRankItem] = []
        for (index, row) in rows.enumerated() {
            items.append(HintRankItem(role: "AXStaticText", subrole: nil, frame: row, index: index))
        }
        for (offset, icon) in icons.enumerated() {
            items.append(HintRankItem(
                role: "AXButton",
                subrole: nil,
                frame: icon,
                index: rows.count + offset
            ))
        }
        return HintRanking.order(items).map { item in
            HintTarget(frame: item.frame, identifier: "vision/\(item.index)", canAccessibilityPress: false)
        }
    }

    public static func logLine(
        permission: String,
        pixelWidth: Int,
        pixelHeight: Int,
        boxes: Int,
        hits: Int
    ) -> String {
        "vision permission=\(permission) image=\(pixelWidth)x\(pixelHeight) boxes=\(boxes) hits=\(hits)"
    }

    private static func groupLines(_ boxes: [HintRect]) -> [HintRect] {
        let sorted = boxes.sorted { lhs, rhs in
            if lhs.y != rhs.y {
                return lhs.y < rhs.y
            }
            return lhs.x < rhs.x
        }
        var lines: [HintRect] = []
        for box in sorted {
            if let index = lines.firstIndex(where: { verticallyOverlaps($0, box) }) {
                lines[index] = union(lines[index], box)
            } else {
                lines.append(box)
            }
        }
        return lines.sorted { $0.y < $1.y }
    }

    private static func groupRows(_ lines: [HintRect]) -> [HintRect] {
        guard var current = lines.first else {
            return []
        }
        let heights = lines.map(\.height).sorted()
        let median = heights[heights.count / 2]
        let gapLimit = max(8, median * 0.85)
        var rows: [HintRect] = []
        for line in lines.dropFirst() {
            let gap = line.y - (current.y + current.height)
            if gap <= gapLimit && horizontalOverlapRatio(current, line) >= 0.25 {
                current = union(current, line)
            } else {
                rows.append(current)
                current = line
            }
        }
        rows.append(current)
        return rows
    }

    private static func verticallyOverlaps(_ lhs: HintRect, _ rhs: HintRect) -> Bool {
        let top = max(lhs.y, rhs.y)
        let bottom = min(lhs.y + lhs.height, rhs.y + rhs.height)
        let overlap = bottom - top
        guard overlap > 0 else {
            return false
        }
        return overlap >= min(lhs.height, rhs.height) * 0.4
    }

    private static func horizontalOverlapRatio(_ lhs: HintRect, _ rhs: HintRect) -> Double {
        let left = max(lhs.x, rhs.x)
        let right = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let overlap = right - left
        guard overlap > 0 else {
            return 0
        }
        let smaller = min(lhs.width, rhs.width)
        guard smaller > 0 else {
            return 0
        }
        return overlap / smaller
    }

    private static func union(_ lhs: HintRect, _ rhs: HintRect) -> HintRect {
        let x = min(lhs.x, rhs.x)
        let y = min(lhs.y, rhs.y)
        let maxX = max(lhs.x + lhs.width, rhs.x + rhs.width)
        let maxY = max(lhs.y + lhs.height, rhs.y + rhs.height)
        return HintRect(x: x, y: y, width: maxX - x, height: maxY - y)
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

    private static func area(_ frame: HintRect) -> Double {
        let value = frame.width * frame.height
        return value.isFinite && value > 0 ? value : 0
    }
}

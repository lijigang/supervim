import Foundation
import SupervimCore

/// One live node after a single round trip: its own values and the handles
/// of its children. The children have not been read yet.
public struct NodeReading<Node: Sendable>: Sendable {
    public var element: AccessibilityElement
    public var children: [Node]

    public init(element: AccessibilityElement, children: [Node]) {
        self.element = element
        self.children = children
    }
}

public enum NodeReadResult<Node: Sendable>: Sendable {
    case node(NodeReading<Node>)
    /// The element is no longer valid. The walk leaves it out.
    case gone
    /// The app did not answer within the messaging timeout. The walk stops:
    /// asking two thousand more nodes would wait that long for each.
    case unresponsive
}

/// Reads one live node. The macOS source asks for every attribute in one
/// `AXUIElementCopyMultipleAttributeValues` call. Tests count the calls.
/// `read` is called from several threads at once.
public protocol AccessibilityNodeSource: Sendable {
    associatedtype Node: Sendable
    func read(_ node: Node) -> NodeReadResult<Node>
}

public struct TreeWalkOptions: Equatable, Sendable {
    public var limits: TreeWalkLimits
    /// Wall-clock budget. When it runs out the walk returns what it has,
    /// marked truncated. Nil means no deadline.
    public var budgetMilliseconds: Double?
    /// Threads reading one level of the tree. Clamped to 1...8.
    public var workers: Int
    /// Skip the children of a node that its window and scroll areas hide.
    public var prunesHidden: Bool

    public init(
        limits: TreeWalkLimits = .standard,
        budgetMilliseconds: Double? = nil,
        workers: Int = 1,
        prunesHidden: Bool = true
    ) {
        self.limits = limits
        self.budgetMilliseconds = budgetMilliseconds
        self.workers = min(max(workers, 1), 8)
        self.prunesHidden = prunesHidden
    }
}

public struct BoundNode<Node: Sendable>: Sendable {
    /// Child indices in the copied tree, from the root.
    public var path: [Int]
    public var node: Node
}

public struct WalkedTree<Node: Sendable>: Sendable {
    /// Nil when the root itself could not be read.
    public var root: AccessibilityElement?
    /// Every node in `root`, in the order it was read, with its path.
    public var bound: [BoundNode<Node>]
    public var read: Int
    /// Nodes that were read and found hidden, so their children were not.
    public var pruned: Int
    public var truncated: Bool
    public var timedOut: Bool
    public var unresponsive: Bool
    public var levels: Int
    public var milliseconds: Double
}

/// Copies a live accessibility tree one level at a time.
///
/// Each node costs one `read`. A level is read by several threads, because
/// the time goes to waiting for the other process. Children are not read
/// when the node is outside its window or outside a scroll or web area above
/// it: nothing under it can be labelled or focused. A node with no usable
/// frame is still expanded, since a zero-size group can hold visible
/// children. Scroll bar parts and table columns are not expanded either.
///
/// The node cap, the depth cap and the deadline cut the walk the same way:
/// the parent whose children were left out is marked `childrenTruncated`.
/// Because the order is breadth-first, a cut keeps the toolbar and the
/// outline of the page and loses the deepest nodes.
public enum AccessibilityTreeWalker {
    public static func walk<Source: AccessibilityNodeSource>(
        root: Source.Node,
        source: Source,
        options: TreeWalkOptions
    ) -> WalkedTree<Source.Node> {
        let watch = TraceStopwatch()
        var entries: [Entry<Source.Node>] = []
        var frontier = [Pending<Source.Node>(node: root, parent: nil, depth: 0, clip: .unbounded)]
        var pruned = 0
        var truncated = false
        var timedOut = false
        var unresponsive = false
        var levels = 0
        let deadline = options.budgetMilliseconds

        while !frontier.isEmpty {
            let remaining = options.limits.maxNodes - entries.count
            if remaining <= 0 {
                markCut(frontier[...], in: &entries)
                truncated = true
                break
            }
            if frontier.count > remaining {
                markCut(frontier[remaining...], in: &entries)
                truncated = true
                frontier = Array(frontier[..<remaining])
            }
            if let deadline, watch.milliseconds >= deadline {
                markCut(frontier[...], in: &entries)
                truncated = true
                timedOut = true
                break
            }
            levels += 1
            let results = readLevel(frontier, source: source, workers: options.workers) {
                if let deadline {
                    return watch.milliseconds >= deadline
                }
                return false
            }
            var next: [Pending<Source.Node>] = []
            for (offset, pending) in frontier.enumerated() {
                switch results[offset] {
                case .skipped:
                    markCut(frontier[offset...offset], in: &entries)
                    truncated = true
                    timedOut = true
                case .read(.unresponsive):
                    markCut(frontier[offset...offset], in: &entries)
                    truncated = true
                    unresponsive = true
                case .read(.gone):
                    continue
                case .read(.node(let reading)):
                    let index = entries.count
                    var path: [Int] = []
                    if let parent = pending.parent {
                        path = entries[parent].path + [entries[parent].children.count]
                        entries[parent].children.append(index)
                    }
                    var entry = Entry(element: reading.element, node: pending.node, path: path)
                    let frame = usable(reading.element.frame)
                    if options.prunesHidden, let frame, pending.clip.hides(frame) {
                        pruned += 1
                    } else if FocusClassification.hidesItsChildren(reading.element.role) {
                        // Parts of the control, or a second route to the same cells.
                    } else if reading.children.isEmpty {
                        // A leaf.
                    } else if pending.depth >= options.limits.maxDepth {
                        entry.truncated = true
                        truncated = true
                    } else {
                        var clip = pending.clip
                        if let frame, index == 0 || FocusClassification.isViewport(reading.element) {
                            clip = clip.narrowed(by: frame)
                        }
                        for child in reading.children {
                            next.append(Pending(node: child, parent: index, depth: pending.depth + 1, clip: clip))
                        }
                    }
                    entries.append(entry)
                }
            }
            if unresponsive {
                markCut(next[...], in: &entries)
                break
            }
            frontier = next
        }

        return WalkedTree(
            root: entries.isEmpty ? nil : assemble(0, entries),
            bound: entries.map { BoundNode(path: $0.path, node: $0.node) },
            read: entries.count,
            pruned: pruned,
            truncated: truncated,
            timedOut: timedOut,
            unresponsive: unresponsive,
            levels: levels,
            milliseconds: watch.milliseconds
        )
    }

    private struct Entry<Node: Sendable> {
        var element: AccessibilityElement
        var node: Node
        var path: [Int]
        var children: [Int] = []
        var truncated = false
    }

    private struct Pending<Node: Sendable>: Sendable {
        var node: Node
        var parent: Int?
        var depth: Int
        var clip: Clip
    }

    /// What the nodes above leave visible. `unbounded` is a root with no frame.
    private enum Clip: Sendable {
        case unbounded
        case rect(HintRect)
        case nothing

        func hides(_ frame: HintRect) -> Bool {
            switch self {
            case .unbounded:
                return false
            case .nothing:
                return true
            case .rect(let rect):
                return intersection(rect, frame) == nil
            }
        }

        func narrowed(by frame: HintRect) -> Clip {
            switch self {
            case .unbounded:
                return .rect(frame)
            case .nothing:
                return .nothing
            case .rect(let rect):
                guard let hit = intersection(rect, frame) else {
                    return .nothing
                }
                return .rect(hit)
            }
        }
    }

    private enum LevelRead<Node: Sendable>: Sendable {
        case read(NodeReadResult<Node>)
        case skipped
    }

    private static func markCut<Node>(_ pending: ArraySlice<Pending<Node>>, in entries: inout [Entry<Node>]) {
        for item in pending {
            if let parent = item.parent {
                entries[parent].truncated = true
            }
        }
    }

    private static func assemble<Node>(_ index: Int, _ entries: [Entry<Node>]) -> AccessibilityElement {
        var element = entries[index].element
        element.children = entries[index].children.map { assemble($0, entries) }
        element.childrenTruncated = entries[index].truncated
        return element
    }

    private static func usable(_ frame: ElementFrame?) -> HintRect? {
        guard let frame else {
            return nil
        }
        let rect = HintRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        return rect.isUsable ? rect : nil
    }

    private static func intersection(_ lhs: HintRect, _ rhs: HintRect) -> HintRect? {
        let x = max(lhs.x, rhs.x)
        let y = max(lhs.y, rhs.y)
        let maxX = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let maxY = min(lhs.y + lhs.height, rhs.y + rhs.height)
        guard maxX > x, maxY > y else {
            return nil
        }
        return HintRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    /// Reads one level. A node that is not reached before `expired` turns
    /// true, or after the app stopped answering, comes back as `skipped`.
    private static func readLevel<Source: AccessibilityNodeSource>(
        _ frontier: [Pending<Source.Node>],
        source: Source,
        workers: Int,
        expired: @escaping @Sendable () -> Bool
    ) -> [LevelRead<Source.Node>] {
        let box = LevelBox<Source.Node>(count: frontier.count)
        let lanes = frontier.count < 8 ? 1 : min(workers, frontier.count)
        // Each worker takes the next node nobody has taken. A node that is
        // slow to answer holds up one worker, not a fixed share of the level.
        let work: @Sendable (Int) -> Void = { _ in
            while let index = box.claim() {
                if expired() {
                    return
                }
                let result = source.read(frontier[index].node)
                if case .unresponsive = result {
                    box.stop()
                }
                box.store(.read(result), at: index)
            }
        }
        if lanes == 1 {
            work(0)
        } else {
            DispatchQueue.concurrentPerform(iterations: lanes, execute: work)
        }
        return box.results()
    }

    private final class LevelBox<Node: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [LevelRead<Node>]
        private var halted = false
        private var next = 0

        init(count: Int) {
            values = [LevelRead<Node>](repeating: .skipped, count: count)
        }

        /// The next node to read, or nil when the level is done or the app
        /// stopped answering.
        func claim() -> Int? {
            lock.lock()
            defer { lock.unlock() }
            guard !halted, next < values.count else {
                return nil
            }
            next += 1
            return next - 1
        }

        func stop() {
            lock.lock()
            halted = true
            lock.unlock()
        }

        func store(_ value: LevelRead<Node>, at index: Int) {
            lock.lock()
            values[index] = value
            lock.unlock()
        }

        func results() -> [LevelRead<Node>] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }
}

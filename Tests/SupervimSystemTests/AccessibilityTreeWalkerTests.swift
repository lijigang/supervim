import Foundation
import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// The walker reads a live tree through a node source. The source here is a
/// fake that counts reads and can take time, so the tests can say how many
/// round trips a scan costs without a real app.
final class AccessibilityTreeWalkerTests: XCTestCase {
    func testWalkCopiesTheTreeInChildOrderAndBindsEveryPath() {
        let tree = FakeNode("AXWindow", rect(0, 0, 800, 600), [
            FakeNode("AXToolbar", rect(0, 0, 800, 40), [
                FakeNode("AXButton", rect(10, 5, 30, 30)),
                FakeNode("AXButton", rect(50, 5, 30, 30)),
            ]),
            FakeNode("AXScrollArea", rect(0, 40, 800, 560), [
                FakeNode("AXLink", rect(10, 60, 100, 20)),
            ]),
        ])
        let source = FakeSource()
        let walked = AccessibilityTreeWalker.walk(root: tree, source: source, options: options())

        XCTAssertEqual(walked.root, tree.copied())
        XCTAssertEqual(walked.bound.map(\.path), [[], [0], [1], [0, 0], [0, 1], [1, 0]])
        XCTAssertEqual(walked.bound.map(\.node.role), [
            "AXWindow", "AXToolbar", "AXScrollArea", "AXButton", "AXButton", "AXLink",
        ])
        XCTAssertEqual(walked.read, 6)
        XCTAssertEqual(source.reads, 6)
        XCTAssertEqual(walked.pruned, 0)
        XCTAssertFalse(walked.truncated)
        XCTAssertFalse(walked.timedOut)
        XCTAssertFalse(walked.unresponsive)
        XCTAssertEqual(walked.levels, 3)
    }

    func testEveryNodeIsReadExactlyOnce() {
        let tree = wideTree(branches: 12, leaves: 20)
        let source = FakeSource()
        let walked = AccessibilityTreeWalker.walk(root: tree, source: source, options: options(workers: 4))
        XCTAssertEqual(source.reads, 1 + 12 + 12 * 20)
        XCTAssertEqual(walked.read, source.reads)
        XCTAssertEqual(Set(source.readIdentifiers).count, source.reads)
    }

    func testRowsScrolledOutOfTheirListAreNotExpanded() {
        let rows = (0..<200).map { index in
            FakeNode("AXRow", rect(0, 100 + Double(index) * 30, 300, 30), [
                FakeNode("AXCell", rect(0, 100 + Double(index) * 30, 300, 30), [
                    FakeNode("AXStaticText", rect(8, 104 + Double(index) * 30, 100, 20)),
                ]),
            ])
        }
        let tree = FakeNode("AXWindow", rect(0, 0, 800, 600), [
            FakeNode("AXScrollArea", rect(0, 100, 300, 300), [
                FakeNode("AXOutline", rect(0, 100, 300, 6_000), rows),
            ]),
        ])
        let source = FakeSource()
        let walked = AccessibilityTreeWalker.walk(root: tree, source: source, options: options())

        // Ten rows are inside the list's 300 points. Those are read with
        // their cell and text. The other 190 rows are read once, to learn
        // their frame, and their 380 descendants are never asked for.
        XCTAssertEqual(source.reads, 3 + 200 + 10 * 2)
        XCTAssertEqual(walked.pruned, 190)
        XCTAssertFalse(walked.truncated)
        let outline = walked.root?.children.first?.children.first
        XCTAssertEqual(outline?.children.count, 200)
        XCTAssertEqual(outline?.children[0].children.count, 1)
        XCTAssertEqual(outline?.children[50].children.count, 0)
        XCTAssertEqual(outline?.children[50].childrenTruncated, false)

        let unpruned = FakeSource()
        var keepAll = options()
        keepAll.prunesHidden = false
        _ = AccessibilityTreeWalker.walk(root: tree, source: unpruned, options: keepAll)
        XCTAssertEqual(unpruned.reads, 3 + 200 * 3)
    }

    func testZeroSizeAndFramelessParentsAreStillExpanded() {
        let tree = FakeNode("AXWindow", rect(0, 0, 800, 600), [
            FakeNode("AXGroup", rect(0, 0, 0, 0), [FakeNode("AXButton", rect(20, 20, 60, 20))]),
            FakeNode("AXGroup", nil, [FakeNode("AXButton", rect(20, 60, 60, 20))]),
            FakeNode("AXGroup", rect(2_000, 2_000, 50, 50), [FakeNode("AXButton", rect(2_000, 2_000, 50, 50))]),
        ])
        let source = FakeSource()
        let walked = AccessibilityTreeWalker.walk(root: tree, source: source, options: options())
        XCTAssertEqual(source.reads, 6)
        XCTAssertEqual(walked.pruned, 1)
        XCTAssertEqual(walked.root?.children.map(\.children.count), [1, 1, 0])
    }

    func testScrollBarAndColumnChildrenAreNotRead() {
        let tree = FakeNode("AXWindow", rect(0, 0, 800, 600), [
            FakeNode("AXScrollBar", rect(780, 0, 20, 600), [
                FakeNode("AXButton", rect(780, 0, 20, 20)),
                FakeNode("AXValueIndicator", rect(780, 20, 20, 100)),
            ]),
            FakeNode("AXColumn", rect(0, 0, 200, 600), [FakeNode("AXCell", rect(0, 0, 200, 30))]),
        ])
        let source = FakeSource()
        let walked = AccessibilityTreeWalker.walk(root: tree, source: source, options: options())
        XCTAssertEqual(source.reads, 3)
        XCTAssertEqual(walked.root?.children.map(\.children.count), [0, 0])
        XCTAssertFalse(walked.truncated)
    }

    func testApplicationRootWithoutAFrameDoesNotPrune() {
        let tree = FakeNode("AXApplication", nil, [
            FakeNode("AXWindow", rect(0, 0, 400, 300), [FakeNode("AXButton", rect(10, 10, 40, 20))]),
            FakeNode("AXMenuBar", rect(0, -900, 1_440, 24), [FakeNode("AXMenuBarItem", rect(10, -900, 60, 24))]),
        ])
        let source = FakeSource()
        let walked = AccessibilityTreeWalker.walk(root: tree, source: source, options: options())
        XCTAssertEqual(source.reads, 5)
        XCTAssertEqual(walked.pruned, 0)
    }

    func testNodeBudgetStopsReadingAndMarksTheCut() {
        let tree = wideTree(branches: 10, leaves: 10)
        let source = FakeSource()
        let walked = AccessibilityTreeWalker.walk(
            root: tree,
            source: source,
            options: options(limits: TreeWalkLimits(maxNodes: 25, maxDepth: 32))
        )
        XCTAssertEqual(source.reads, 25)
        XCTAssertEqual(walked.read, 25)
        XCTAssertTrue(walked.truncated)
        XCTAssertFalse(walked.timedOut)
        let branches = walked.root?.children ?? []
        XCTAssertEqual(branches.count, 10)
        XCTAssertEqual(branches[0].children.count, 10)
        XCTAssertFalse(branches[0].childrenTruncated)
        XCTAssertEqual(branches[1].children.count, 4)
        XCTAssertTrue(branches[1].childrenTruncated)
        XCTAssertTrue(branches[9].childrenTruncated)
        XCTAssertEqual(branches[9].children.count, 0)
    }

    func testDepthCapLeavesDeeperChildrenUnread() {
        var deep = FakeNode("AXButton", rect(10, 10, 20, 20))
        for _ in 0..<6 {
            deep = FakeNode("AXGroup", rect(0, 0, 100, 100), [deep])
        }
        let source = FakeSource()
        let walked = AccessibilityTreeWalker.walk(
            root: deep,
            source: source,
            options: options(limits: TreeWalkLimits(maxNodes: 100, maxDepth: 3))
        )
        XCTAssertEqual(source.reads, 4)
        XCTAssertTrue(walked.truncated)
        var cursor = walked.root
        for _ in 0..<3 {
            cursor = cursor?.children.first
        }
        XCTAssertEqual(cursor?.children.count, 0)
        XCTAssertEqual(cursor?.childrenTruncated, true)
    }

    func testDeadlineReturnsTheLevelsReadSoFar() {
        // One read in the second level outlasts the budget. The other reads
        // take no time, so the result does not depend on how fast the
        // machine sleeps: the second level is complete, the third is not
        // started.
        let tree = wideTree(branches: 20, leaves: 40)
        let source = FakeSource()
        source.slowRead = (index: 5, milliseconds: 400)
        var limited = options(workers: 4)
        limited.budgetMilliseconds = 200
        let walked = AccessibilityTreeWalker.walk(root: tree, source: source, options: limited)

        XCTAssertTrue(walked.timedOut)
        XCTAssertTrue(walked.truncated)
        XCTAssertEqual(source.reads, 21)
        XCTAssertEqual(walked.root?.role, "AXWindow")
        XCTAssertEqual(walked.root?.children.count, 20)
        XCTAssertEqual(walked.root?.children.first?.children.count, 0)
        XCTAssertGreaterThanOrEqual(walked.milliseconds, 200)
    }

    func testDeadlineInsideALevelKeepsTheNodesAlreadyRead() {
        let tree = wideTree(branches: 20, leaves: 2)
        let source = FakeSource()
        source.slowRead = (index: 3, milliseconds: 300)
        var limited = options(workers: 1)
        limited.budgetMilliseconds = 150
        let walked = AccessibilityTreeWalker.walk(root: tree, source: source, options: limited)

        XCTAssertTrue(walked.timedOut)
        XCTAssertEqual(source.reads, 4)
        XCTAssertEqual(walked.root?.children.count, 3)
    }

    func testUnresponsiveAppStopsTheWalk() {
        let tree = wideTree(branches: 10, leaves: 50)
        let source = FakeSource()
        source.unresponsiveAfter = 5
        let walked = AccessibilityTreeWalker.walk(root: tree, source: source, options: options())
        XCTAssertTrue(walked.unresponsive)
        XCTAssertTrue(walked.truncated)
        XCTAssertLessThanOrEqual(source.reads, 11)
        XCTAssertEqual(walked.root?.role, "AXWindow")
    }

    func testUnresponsiveRootHasNoTree() {
        let source = FakeSource()
        source.unresponsiveAfter = 0
        let walked = AccessibilityTreeWalker.walk(
            root: FakeNode("AXWindow", rect(0, 0, 10, 10)),
            source: source,
            options: options()
        )
        XCTAssertNil(walked.root)
        XCTAssertTrue(walked.unresponsive)
        XCTAssertTrue(walked.bound.isEmpty)
    }

    func testNodesThatWentAwayAreSkippedAndKeepSiblingPaths() {
        let tree = FakeNode("AXWindow", rect(0, 0, 800, 600), [
            FakeNode("AXButton", rect(10, 10, 20, 20)),
            FakeNode("AXGone", rect(40, 10, 20, 20), [FakeNode("AXButton", rect(40, 10, 20, 20))]),
            FakeNode("AXLink", rect(70, 10, 20, 20)),
        ])
        let source = FakeSource()
        let walked = AccessibilityTreeWalker.walk(root: tree, source: source, options: options())
        XCTAssertEqual(walked.root?.children.map(\.role), ["AXButton", "AXLink"])
        XCTAssertEqual(walked.bound.map(\.path), [[], [0], [1]])
        XCTAssertEqual(walked.bound.map(\.node.role), ["AXWindow", "AXButton", "AXLink"])
        XCTAssertFalse(walked.truncated)
    }

    func testFourWorkersReadAtTheSameTimeAndCopyTheSameTree() {
        let tree = wideTree(branches: 8, leaves: 12)
        let slow = FakeSource(delayMilliseconds: 2)
        let one = AccessibilityTreeWalker.walk(root: tree, source: slow, options: options(workers: 1))
        let parallel = FakeSource(delayMilliseconds: 2)
        let four = AccessibilityTreeWalker.walk(root: tree, source: parallel, options: options(workers: 4))

        XCTAssertEqual(one.root, four.root)
        XCTAssertEqual(one.bound.map(\.path), four.bound.map(\.path))
        XCTAssertEqual(slow.reads, parallel.reads)
        // Counted, not timed: a loaded machine sleeps longer than asked, and
        // a ratio of two such runs is noise.
        XCTAssertEqual(slow.mostReadsAtOnce, 1)
        XCTAssertGreaterThan(parallel.mostReadsAtOnce, 1)
        XCTAssertLessThanOrEqual(parallel.mostReadsAtOnce, 4)
        print(
            "BENCH walker nodes=\(slow.reads) latency_ms=2 workers1_ms=\(String(format: "%.0f", one.milliseconds)) "
                + "workers4_ms=\(String(format: "%.0f", four.milliseconds)) at_once=\(parallel.mostReadsAtOnce)"
        )
    }

    func testOptionsClampWorkersAndKeepTheStandardLimits() {
        XCTAssertEqual(TreeWalkOptions(workers: 0).workers, 1)
        XCTAssertEqual(TreeWalkOptions(workers: 64).workers, 8)
        XCTAssertEqual(TreeWalkOptions().limits, .standard)
        XCTAssertNil(TreeWalkOptions().budgetMilliseconds)
        XCTAssertTrue(TreeWalkOptions().prunesHidden)
    }

    func testStructuralRolesDoNotNeedTheirActionNames() {
        for role in ["AXWindow", "AXScrollArea", "AXWebArea", "AXSplitGroup", "AXToolbar", "AXTable", "AXOutline", "AXList"] {
            XCTAssertFalse(FocusClassification.wantsActionNames(role: role), role)
        }
        for role in ["AXGroup", "AXButton", "AXImage", "AXStaticText", "AXRow", "AXCell", "AXLink", "AXCustom"] {
            XCTAssertTrue(FocusClassification.wantsActionNames(role: role), role)
        }
        XCTAssertTrue(FocusClassification.wantsActionNames(role: nil))
    }

    // MARK: Helpers

    private func options(
        limits: TreeWalkLimits = .standard,
        workers: Int = 1
    ) -> TreeWalkOptions {
        TreeWalkOptions(limits: limits, workers: workers)
    }

    private func wideTree(branches: Int, leaves: Int) -> FakeNode {
        FakeNode("AXWindow", rect(0, 0, 4_000, 4_000), (0..<branches).map { branch in
            FakeNode("AXGroup", rect(0, Double(branch) * 40, 4_000, 40), (0..<leaves).map { leaf in
                FakeNode("AXButton", rect(Double(leaf) * 40, Double(branch) * 40, 36, 36))
            })
        })
    }

    private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> ElementFrame {
        ElementFrame(x: x, y: y, width: width, height: height)
    }
}

private struct FakeNode: Sendable {
    var identifier: Int
    var role: String
    var frame: ElementFrame?
    var children: [FakeNode]

    init(_ role: String, _ frame: ElementFrame?, _ children: [FakeNode] = []) {
        identifier = FakeNodeCounter.next()
        self.role = role
        self.frame = frame
        self.children = children
    }

    func copied() -> AccessibilityElement {
        AccessibilityElement(role: role, frame: frame, children: children.map { $0.copied() })
    }
}

private enum FakeNodeCounter {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var value = 0

    static func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private final class FakeSource: AccessibilityNodeSource, @unchecked Sendable {
    private let lock = NSLock()
    private let delayMilliseconds: Double
    private var count = 0
    private var identifiers: [Int] = []
    private var inFlight = 0
    private var peak = 0
    var unresponsiveAfter: Int?
    /// The read with this index (counted from zero) sleeps this long.
    var slowRead: (index: Int, milliseconds: Double)?

    var mostReadsAtOnce: Int {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    init(delayMilliseconds: Double = 0) {
        self.delayMilliseconds = delayMilliseconds
    }

    var reads: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    var readIdentifiers: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return identifiers
    }

    func read(_ node: FakeNode) -> NodeReadResult<FakeNode> {
        lock.lock()
        let seen = count
        if let unresponsiveAfter, seen >= unresponsiveAfter {
            count += 1
            lock.unlock()
            return .unresponsive
        }
        count += 1
        identifiers.append(node.identifier)
        inFlight += 1
        peak = max(peak, inFlight)
        let pause = slowRead.flatMap { $0.index == seen ? $0.milliseconds : nil } ?? delayMilliseconds
        lock.unlock()
        if pause > 0 {
            Thread.sleep(forTimeInterval: pause / 1_000)
        }
        lock.lock()
        inFlight -= 1
        lock.unlock()
        if node.role == "AXGone" {
            return .gone
        }
        return .node(NodeReading(
            element: AccessibilityElement(role: node.role, frame: node.frame),
            children: node.children
        ))
    }
}

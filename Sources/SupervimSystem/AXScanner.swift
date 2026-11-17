import Foundation
import SupervimCore

/// Rectangle copied from an accessibility frame.
///
/// The axes stay in whatever coordinate space the reader used. This type does not
/// flip AppKit or Quartz origins, and it does not know which display is visible.
public struct ElementFrame: Equatable, Sendable {
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
}

/// One accessibility node as a value.
///
/// A focus read leaves `children` empty. A window read may include them.
/// `childrenTruncated` means the reader omitted further children after `children`.
public struct AccessibilityElement: Equatable, Sendable {
    public var role: String?
    public var subrole: String?
    public var actions: [String]
    public var editableAttribute: Bool?
    /// Stable identity of one accessibility element. Nil when the reader has none.
    public var identity: String?
    public var frame: ElementFrame?
    public var children: [AccessibilityElement]
    public var childrenTruncated: Bool
    /// Vertical bar copied off the key hook. Nil when the reader found none.
    public var verticalScroll: ScrollBarReading?
    /// Horizontal bar copied off the key hook. Nil when the reader found none.
    public var horizontalScroll: ScrollBarReading?

    public init(
        role: String? = nil,
        subrole: String? = nil,
        actions: [String] = [],
        editableAttribute: Bool? = nil,
        identity: String? = nil,
        frame: ElementFrame? = nil,
        children: [AccessibilityElement] = [],
        childrenTruncated: Bool = false,
        verticalScroll: ScrollBarReading? = nil,
        horizontalScroll: ScrollBarReading? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.actions = actions
        self.editableAttribute = editableAttribute
        self.identity = identity
        self.frame = frame
        self.children = children
        self.childrenTruncated = childrenTruncated
        self.verticalScroll = verticalScroll
        self.horizontalScroll = horizontalScroll
    }
}

public enum AccessibilityRead<Value: Equatable & Sendable>: Equatable, Sendable {
    case value(Value)
    case unavailable
}

/// Safety cap for a window walk. Not a hint-coverage guarantee.
/// `maxNodes` counts every visited node, including ones that are not clickable.
/// `maxDepth` is the root's depth, which is 0.
public struct TreeWalkLimits: Equatable, Sendable {
    public var maxNodes: Int
    public var maxDepth: Int

    public init(maxNodes: Int, maxDepth: Int) {
        self.maxNodes = max(1, maxNodes)
        self.maxDepth = max(0, maxDepth)
    }

    public static let standard = TreeWalkLimits(maxNodes: 2_000, maxDepth: 32)
}

/// How a focused node, or a node in a window walk, is classified.
///
/// The mode machine only receives `FocusEditability`. Roles Vimium would type into
/// are editable. Roles that own the keyboard (menus, sheets, dialogs) are unknown,
/// so the machine passes keys through instead of starting Normal commands.
/// A text role whose editable attribute is explicitly false is also unknown:
/// the two signals disagree, and swallowing typed characters is worse.
public enum FocusClassification {
    public static func editability(of element: AccessibilityElement) -> FocusEditability {
        if isKeyboardOwner(element.role) {
            return .unknown
        }
        if isTextEntry(element) {
            return element.editableAttribute == false ? .unknown : .editable
        }
        if element.editableAttribute == true {
            return .editable
        }
        if element.editableAttribute == false {
            return .notEditable
        }
        if let role = element.role, knownNonEditableRoles.contains(role) {
            return .notEditable
        }
        return .unknown
    }

    public static func clickableElements(
        in window: AccessibilityElement,
        limits: TreeWalkLimits
    ) -> ClickableSnapshot {
        countedClickables(in: window, limits: limits).snapshot
    }

    static func countedClickables(
        in window: AccessibilityElement,
        limits: TreeWalkLimits
    ) -> (snapshot: ClickableSnapshot, visited: Int) {
        var elements: [ClickableElement] = []
        var visited = 0
        var viewports: [HintRect] = []
        let windowRect = window.frame.map(hintRect)
        let truncated = walk(window, limits: limits) { visit in
            visited += 1
            if let frame = visit.node.frame, isViewport(visit.node) {
                let rect = hintRect(frame)
                if rect.isUsable {
                    viewports.append(rect)
                }
            }
            if !visit.isRoot, isClickable(visit.node), let raw = visit.node.frame.map(hintRect),
               let visible = HintGeometry.visibleElement(raw, window: windowRect, viewports: viewports) {
                elements.append(
                    ClickableElement(
                        role: visit.node.role,
                        subrole: visit.node.subrole,
                        actions: visit.node.actions,
                        frame: elementFrame(visible),
                        path: visit.path
                    )
                )
            }
            return false
        }
        return (ClickableSnapshot(elements: elements, truncated: truncated), visited)
    }

    static func editableCandidates(
        in window: AccessibilityElement,
        limits: TreeWalkLimits,
        inFocusedWindow: Bool
    ) -> (candidates: [InputCandidate], truncated: Bool) {
        var candidates: [InputCandidate] = []
        var viewports: [HintRect] = []
        let windowRect = window.frame.map(hintRect)
        let truncated = walk(window, limits: limits) { visit in
            if let frame = visit.node.frame, isViewport(visit.node) {
                let rect = hintRect(frame)
                if rect.isUsable {
                    viewports.append(rect)
                }
            }
            guard !visit.isRoot,
                  editability(of: visit.node) == .editable,
                  InputChoice.isTextInput(role: visit.node.role, subrole: visit.node.subrole),
                  let raw = visit.node.frame.map(hintRect),
                  let visible = HintGeometry.visibleElement(raw, window: windowRect, viewports: viewports)
            else {
                return false
            }
            candidates.append(
                InputCandidate(
                    role: visit.node.role,
                    subrole: visit.node.subrole,
                    frame: visible,
                    path: visit.path,
                    editable: true,
                    identity: visit.node.identity,
                    inFocusedWindow: inFocusedWindow
                )
            )
            return false
        }
        return (candidates, truncated)
    }

    private static func isViewport(_ element: AccessibilityElement) -> Bool {
        element.role == "AXScrollArea" || element.role == "AXWebArea"
    }

    private static func hintRect(_ frame: ElementFrame) -> HintRect {
        HintRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    private static func elementFrame(_ rect: HintRect) -> ElementFrame {
        ElementFrame(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    private static let textRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXPopUpButton",
    ]

    private static let textSubroles: Set<String> = [
        "AXSearchField",
        "AXSecureTextField",
    ]

    private static let keyboardOwnerRoles: Set<String> = [
        "AXMenu",
        "AXMenuBar",
        "AXMenuItem",
        "AXMenuBarItem",
        "AXSheet",
        "AXDialog",
        "AXSystemDialog",
    ]

    private static let knownNonEditableRoles: Set<String> = [
        "AXApplication",
        "AXBrowser",
        "AXButton",
        "AXCheckBox",
        "AXColorWell",
        "AXDisclosureTriangle",
        "AXGroup",
        "AXImage",
        "AXIncrementor",
        "AXLayoutArea",
        "AXLayoutItem",
        "AXLink",
        "AXList",
        "AXMenuButton",
        "AXOutline",
        "AXRadioButton",
        "AXRow",
        "AXScrollArea",
        "AXScrollBar",
        "AXSlider",
        "AXSplitGroup",
        "AXSplitter",
        "AXStaticText",
        "AXTab",
        "AXTabGroup",
        "AXTable",
        "AXToolbar",
        "AXWebArea",
        "AXWindow",
    ]

    private static let clickableRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXColorWell",
        "AXComboBox",
        "AXDisclosureTriangle",
        "AXIncrementor",
        "AXLink",
        "AXMenuButton",
        "AXMenuItem",
        "AXPopUpButton",
        "AXRadioButton",
        "AXSlider",
        "AXTab",
        "AXTextArea",
        "AXTextField",
    ]

    private static let clickableSubroles: Set<String> = [
        "AXCloseButton",
        "AXFullScreenButton",
        "AXMinimizeButton",
        "AXSearchField",
        "AXSecureTextField",
        "AXToolbarButton",
        "AXZoomButton",
    ]

    private static let containerRoles: Set<String> = [
        "AXApplication",
        "AXBrowser",
        "AXDialog",
        "AXGroup",
        "AXLayoutArea",
        "AXList",
        "AXMenu",
        "AXMenuBar",
        "AXOutline",
        "AXRow",
        "AXScrollArea",
        "AXScrollBar",
        "AXSheet",
        "AXSplitGroup",
        "AXSystemDialog",
        "AXTabGroup",
        "AXTable",
        "AXToolbar",
        "AXWebArea",
        "AXWindow",
    ]

    private static let pressActions: Set<String> = ["AXPress", "AXConfirm", "AXPick"]

    private static func isKeyboardOwner(_ role: String?) -> Bool {
        guard let role else { return false }
        return keyboardOwnerRoles.contains(role)
    }

    private static func isTextEntry(_ element: AccessibilityElement) -> Bool {
        if let subrole = element.subrole, textSubroles.contains(subrole) {
            return true
        }
        if let role = element.role, textRoles.contains(role) {
            return true
        }
        return false
    }

    private static func isClickable(_ element: AccessibilityElement) -> Bool {
        if element.actions.contains(where: { pressActions.contains($0) }) {
            return true
        }
        if let subrole = element.subrole, clickableSubroles.contains(subrole) {
            return true
        }
        if let role = element.role, containerRoles.contains(role) {
            return false
        }
        if let role = element.role, clickableRoles.contains(role) {
            return true
        }
        return false
    }

}

public struct ClickableElement: Equatable, Sendable {
    public var role: String?
    public var subrole: String?
    public var actions: [String]
    public var frame: ElementFrame
    /// Child indices from the window root. The root itself is not a result.
    public var path: [Int]

    public init(
        role: String? = nil,
        subrole: String? = nil,
        actions: [String] = [],
        frame: ElementFrame,
        path: [Int]
    ) {
        self.role = role
        self.subrole = subrole
        self.actions = actions
        self.frame = frame
        self.path = path
    }
}

public struct ClickableSnapshot: Equatable, Sendable {
    public var elements: [ClickableElement]
    public var truncated: Bool

    public init(elements: [ClickableElement], truncated: Bool) {
        self.elements = elements
        self.truncated = truncated
    }
}

public enum ClickableQuery: Equatable, Sendable {
    case elements(ClickableSnapshot)
    case unavailable
}

public struct EditableInputTarget: Equatable, Sendable {
    public var role: String?
    public var subrole: String?
    public var frame: ElementFrame
    /// Child indices from the window root.
    public var path: [Int]

    public init(role: String? = nil, subrole: String? = nil, frame: ElementFrame, path: [Int]) {
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.path = path
    }
}

/// Lookup only. This does not focus the element and does not enter Insert.
/// A later focus report does that after something else moves the focus.
public enum EditableInputQuery: Equatable, Sendable {
    case found(EditableInputTarget)
    case none
    case unavailable
}

/// Reads already-copied accessibility values. Tests supply a fake.
/// `readFocusedElement` must not walk children. The window read is off the key hook.
/// What a one-time accessibility-tree request did for one process.
public enum AccessibilityTreeExpansion: Equatable, Sendable {
    case unchanged
    case manual
    case enhanced
}

/// One window the frontmost app exposed, already copied.
/// `source` is `focused`, `main`, or `windows`. `found` is false when that
/// attribute was missing. `element` is nil in that case.
public struct AccessibilityWindowChoice: Equatable, Sendable {
    public var source: String
    public var found: Bool
    public var element: AccessibilityElement?

    public init(source: String, found: Bool, element: AccessibilityElement?) {
        self.source = source
        self.found = found
        self.element = element
    }
}

/// How long a scan waits after it turns an accessibility attribute on.
/// Qt and WeChat often populate the tree on a later turn of the run loop.
public enum HintScanTiming {
    public static let populationDelayMilliseconds = 120
}

/// Pauses after `AXManualAccessibility` or `AXEnhancedUserInterface` is set.
/// Tests record the delay and do not sleep. The app uses `AccessibilityTreeSleeper`.
public protocol AccessibilityTreeWaiting: AnyObject, Sendable {
    func waitForAccessibilityTree(milliseconds: Int)
}

public final class AccessibilityTreeSleeper: AccessibilityTreeWaiting, @unchecked Sendable {
    public init() {}

    public func waitForAccessibilityTree(milliseconds: Int) {
        guard milliseconds > 0 else {
            return
        }
        Thread.sleep(forTimeInterval: Double(milliseconds) / 1000)
    }
}

public protocol AccessibilityReading: AnyObject, Sendable {
    func readFocusedElement() -> AccessibilityRead<AccessibilityElement>
    func readFrontmostBundleIdentifier() -> AccessibilityRead<String>
    func readFrontmostWindow(maxNodes: Int, maxDepth: Int) -> AccessibilityRead<AccessibilityElement>
    /// Focused window, then main window, then each window in `AXWindows`.
    /// A missing attribute is a choice with `found == false`, not a skipped slot.
    func readWindowChoices(maxNodes: Int, maxDepth: Int) -> [AccessibilityWindowChoice]
    /// The application element, used when every window attribute is empty.
    func readApplicationElement(maxNodes: Int, maxDepth: Int) -> AccessibilityElement?
    /// Ask the frontmost app to expose its tree.
    /// `allowEnhanced == false` tries `AXManualAccessibility` only.
    /// `allowEnhanced == true` also tries `AXEnhancedUserInterface` when the
    /// tree is still empty. A successful manual write does not skip enhanced.
    func expandAccessibilityTree(allowEnhanced: Bool) -> AccessibilityTreeExpansion
}

extension AccessibilityReading {
    public func expandAccessibilityTree(allowEnhanced: Bool) -> AccessibilityTreeExpansion {
        _ = allowEnhanced
        return .unchanged
    }

    public func readWindowChoices(maxNodes: Int, maxDepth: Int) -> [AccessibilityWindowChoice] {
        switch readFrontmostWindow(maxNodes: maxNodes, maxDepth: maxDepth) {
        case .unavailable:
            return [AccessibilityWindowChoice(source: "focused", found: false, element: nil)]
        case .value(let element):
            return [AccessibilityWindowChoice(source: "focused", found: true, element: element)]
        }
    }

    public func readApplicationElement(maxNodes: Int, maxDepth: Int) -> AccessibilityElement? {
        _ = maxNodes
        _ = maxDepth
        return nil
    }
}

/// Fires when focus or the frontmost app may have changed.
/// The macOS adapter uses an accessibility observer and an activation observer.
/// The key hook does not call this.
public protocol FocusChangeSignaling: AnyObject, Sendable {
    func start(_ handler: @escaping @Sendable () -> Void)
    func stop()
}

public protocol FocusCacheReplacing: FocusCacheReading {
    func replace(_ focus: CachedFocus)
}

public final class LockedFocusCache: FocusCacheReplacing, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: CachedFocus

    public init(snapshot: CachedFocus = .unknown) {
        self.snapshot = snapshot
    }

    public func currentFocus() -> CachedFocus {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    public func replace(_ focus: CachedFocus) {
        lock.lock()
        defer { lock.unlock() }
        snapshot = focus
    }
}

/// Classifies focus and lists elements from a reader.
///
/// Focus updates read one element and the bundle identifier, store them in the
/// cache EventTap already consults, then publish that cache into ModeMachine.
/// Clickable elements and the first editable input walk the frontmost window
/// and do not change the cache or the mode.
public final class AXScanner: AccessibilityScanning, @unchecked Sendable {
    private let reader: any AccessibilityReading
    private let signals: any FocusChangeSignaling
    private let cache: any FocusCacheReplacing
    private let limits: TreeWalkLimits
    private let waiter: (any AccessibilityTreeWaiting)?
    private let populationDelayMilliseconds: Int
    private weak var wiring: EventTapWiring?
    private let lock = NSLock()
    private var started = false

    public init(
        reader: any AccessibilityReading,
        signals: any FocusChangeSignaling,
        cache: any FocusCacheReplacing,
        limits: TreeWalkLimits = .standard,
        waiter: (any AccessibilityTreeWaiting)? = nil,
        populationDelayMilliseconds: Int = HintScanTiming.populationDelayMilliseconds
    ) {
        self.reader = reader
        self.signals = signals
        self.cache = cache
        self.limits = limits
        self.waiter = waiter
        self.populationDelayMilliseconds = populationDelayMilliseconds
    }

    public func connect(_ wiring: EventTapWiring) {
        self.wiring = wiring
    }

    public func start() {
        lock.lock()
        let already = started
        started = true
        lock.unlock()
        signals.start { [weak self] in
            _ = self?.noteFocusChanged()
        }
        if !already {
            _ = noteFocusChanged()
        }
    }

    public func stop() {
        lock.lock()
        started = false
        lock.unlock()
        signals.stop()
    }

    @discardableResult
    public func noteFocusChanged() -> EventDecision {
        let focus = classifiedFocus()
        cache.replace(focus)
        if let wiring {
            return wiring.publishCachedFocus()
        }
        return EventDecision(delivery: .passThrough, mode: .normal)
    }

    public func scanFocus() -> CachedFocus {
        _ = noteFocusChanged()
        return cache.currentFocus()
    }

    public func clickableElements() -> ClickableQuery {
        let started = Date()
        let bundle = frontmostBundle()
        var expansion = "none"
        var retry = "none"
        var picked = readChoices()
        if picked.hits == 0 {
            let manual = reader.expandAccessibilityTree(allowEnhanced: false)
            if manual == .manual {
                expansion = "manual"
                pauseForTree()
                picked = readChoices()
                retry = picked.hits > 0 ? "hits" : "empty"
            }
        }
        if picked.hits == 0 {
            let enhanced = reader.expandAccessibilityTree(allowEnhanced: true)
            if enhanced == .enhanced {
                expansion = expansion == "manual" ? "manual+enhanced" : "enhanced"
                pauseForTree()
                picked = readChoices()
                retry = picked.hits > 0 ? "hits" : "empty"
            } else if enhanced == .manual && expansion == "none" {
                expansion = "manual"
                pauseForTree()
                picked = readChoices()
                retry = picked.hits > 0 ? "hits" : "empty"
            }
        }
        let milliseconds = Int((Date().timeIntervalSince(started) * 1000).rounded())
        if let root = picked.root {
            let summary = AccessibilityTreeSummary.counts(in: root, limits: limits)
            ModeTrace.noteLine(AccessibilityTreeSummary.line(
                bundle: bundle,
                nodes: summary.nodes,
                roles: summary.roles
            ))
        } else {
            ModeTrace.noteLine(AccessibilityTreeSummary.line(bundle: bundle, nodes: 0, roles: [:]))
        }
        ModeTrace.noteHintScan(
            bundleIdentifier: bundle,
            window: picked.window,
            found: picked.found,
            visited: picked.visited,
            hits: picked.hits,
            milliseconds: milliseconds,
            expansion: expansion,
            retry: retry
        )
        return picked.query
    }

    private func pauseForTree() {
        waiter?.waitForAccessibilityTree(milliseconds: populationDelayMilliseconds)
    }

    private func readChoices() -> ScanPick {
        let choices = reader.readWindowChoices(maxNodes: limits.maxNodes, maxDepth: limits.maxDepth)
        if choices.isEmpty {
            ModeTrace.noteLine(ModeTrace.formatHintWindow(source: "none", found: 0, children: 0))
        }
        for choice in choices {
            let children = choice.element?.children.count ?? 0
            ModeTrace.noteLine(ModeTrace.formatHintWindow(
                source: choice.source,
                found: choice.found ? 1 : 0,
                children: children
            ))
        }
        var picked = pick(choices)
        if picked.hits == 0, let application = reader.readApplicationElement(
            maxNodes: limits.maxNodes,
            maxDepth: limits.maxDepth
        ) {
            ModeTrace.noteLine(ModeTrace.formatHintWindow(
                source: "application",
                found: 1,
                children: application.children.count
            ))
            let counted = FocusClassification.countedClickables(in: application, limits: limits)
            if counted.snapshot.elements.count > 0 || picked.found == 0 {
                picked = ScanPick(
                    query: .elements(counted.snapshot),
                    visited: counted.visited,
                    hits: counted.snapshot.elements.count,
                    window: "application",
                    found: 1,
                    root: application
                )
            }
        }
        return picked
    }

    private func pick(_ choices: [AccessibilityWindowChoice]) -> ScanPick {
        var fallback: ScanPick?
        for choice in choices {
            guard choice.found, let element = choice.element else {
                continue
            }
            let counted = FocusClassification.countedClickables(in: element, limits: limits)
            let candidate = ScanPick(
                query: .elements(counted.snapshot),
                visited: counted.visited,
                hits: counted.snapshot.elements.count,
                window: choice.source,
                found: 1,
                root: element
            )
            if candidate.hits > 0 {
                return candidate
            }
            if fallback == nil {
                fallback = candidate
            }
        }
        if let fallback {
            return fallback
        }
        return ScanPick(query: .unavailable, visited: 0, hits: 0, window: "missing", found: 0, root: nil)
    }

    private func frontmostBundle() -> String {
        switch reader.readFrontmostBundleIdentifier() {
        case .value(let identifier):
            return identifier
        case .unavailable:
            return ""
        }
    }

    public func firstEditableInput() -> EditableInputQuery {
        let choices = reader.readWindowChoices(maxNodes: limits.maxNodes, maxDepth: limits.maxDepth)
        let lastFocused = cache.currentFocus().elementIdentity
        var candidates: [InputCandidate] = []
        var sawWindow = false
        var truncated = false
        for choice in choices {
            guard choice.found, let element = choice.element else {
                continue
            }
            sawWindow = true
            let found = FocusClassification.editableCandidates(
                in: element,
                limits: limits,
                inFocusedWindow: choice.source == "focused" || choice.source == "application"
            )
            candidates.append(contentsOf: found.candidates)
            if found.truncated {
                truncated = true
            }
        }
        if candidates.isEmpty,
           let application = reader.readApplicationElement(maxNodes: limits.maxNodes, maxDepth: limits.maxDepth) {
            sawWindow = true
            let found = FocusClassification.editableCandidates(
                in: application,
                limits: limits,
                inFocusedWindow: true
            )
            candidates.append(contentsOf: found.candidates)
            if found.truncated {
                truncated = true
            }
        }
        if let best = InputChoice.best(candidates, lastFocusedIdentity: lastFocused, window: nil) {
            return .found(
                EditableInputTarget(
                    role: best.role,
                    subrole: best.subrole,
                    frame: ElementFrame(
                        x: best.frame.x,
                        y: best.frame.y,
                        width: best.frame.width,
                        height: best.frame.height
                    ),
                    path: best.path
                )
            )
        }
        if !sawWindow || truncated {
            return .unavailable
        }
        return .none
    }

    private func classifiedFocus() -> CachedFocus {
        let editability: FocusEditability
        var identity: String?
        var frame: FocusFrame?
        var role: String?
        var subrole: String?
        switch reader.readFocusedElement() {
        case .unavailable:
            editability = .unknown
        case .value(let element):
            editability = FocusClassification.editability(of: element)
            identity = element.identity
            role = element.role
            subrole = element.subrole
            if let elementFrame = element.frame {
                frame = FocusFrame(
                    x: elementFrame.x,
                    y: elementFrame.y,
                    width: elementFrame.width,
                    height: elementFrame.height
                )
            }
        }
        switch reader.readFrontmostBundleIdentifier() {
        case .unavailable:
            return CachedFocus(
                editability: editability,
                bundleIdentifier: "",
                elementIdentity: identity,
                frame: frame,
                role: role,
                subrole: subrole
            )
        case .value(let identifier):
            return CachedFocus(
                editability: editability,
                bundleIdentifier: identifier,
                elementIdentity: identity,
                frame: frame,
                role: role,
                subrole: subrole
            )
        }
    }
}

/// Wires one reader and one signal source to the cache the event hook already reads.
public final class FocusPipeline: @unchecked Sendable {
    public let cache: LockedFocusCache
    public let scanner: AXScanner
    public let wiring: EventTapWiring

    public init(
        decider: any KeyDeciding,
        reader: any AccessibilityReading,
        signals: any FocusChangeSignaling,
        limits: TreeWalkLimits = .standard,
        waiter: (any AccessibilityTreeWaiting)? = nil,
        populationDelayMilliseconds: Int = HintScanTiming.populationDelayMilliseconds
    ) {
        let cache = LockedFocusCache()
        let scanner = AXScanner(
            reader: reader,
            signals: signals,
            cache: cache,
            limits: limits,
            waiter: waiter,
            populationDelayMilliseconds: populationDelayMilliseconds
        )
        let wiring = EventTapWiring(decider: decider, cache: cache, scanner: scanner)
        scanner.connect(wiring)
        self.cache = cache
        self.scanner = scanner
        self.wiring = wiring
    }
}

private struct ScanPick {
    var query: ClickableQuery
    var visited: Int
    var hits: Int
    var window: String
    var found: Int
    var root: AccessibilityElement?
}

private struct WalkVisit {
    var node: AccessibilityElement
    var path: [Int]
    var isRoot: Bool
    /// True when an earlier node omitted children that tree order would have visited first.
    var holeBefore: Bool
}

private final class WalkCursor {
    var visited = 0
    var truncated = false
    var stopped = false
    let limits: TreeWalkLimits

    init(limits: TreeWalkLimits) {
        self.limits = limits
    }
}

/// Returns whether the walk omitted part of the tree.
private func walk(
    _ root: AccessibilityElement,
    limits: TreeWalkLimits,
    _ body: (WalkVisit) -> Bool
) -> Bool {
    let cursor = WalkCursor(limits: limits)
    visit(root, path: [], depth: 0, isRoot: true, cursor: cursor, body: body)
    return cursor.truncated
}

private func visit(
    _ node: AccessibilityElement,
    path: [Int],
    depth: Int,
    isRoot: Bool,
    cursor: WalkCursor,
    body: (WalkVisit) -> Bool
) {
    if cursor.stopped {
        return
    }
    cursor.visited += 1
    let stop = body(
        WalkVisit(node: node, path: path, isRoot: isRoot, holeBefore: cursor.truncated)
    )
    if stop {
        cursor.stopped = true
        return
    }
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
        visit(
            child,
            path: path + [index],
            depth: depth + 1,
            isRoot: false,
            cursor: cursor,
            body: body
        )
        if cursor.stopped {
            return
        }
        if cursor.visited >= cursor.limits.maxNodes && index + 1 < node.children.count {
            cursor.truncated = true
            return
        }
    }
    if node.childrenTruncated {
        cursor.truncated = true
    }
}

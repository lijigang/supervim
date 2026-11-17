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
        var elements: [ClickableElement] = []
        let truncated = walk(window, limits: limits) { visit in
            if !visit.isRoot, isClickable(visit.node), isOnScreen(visit.node, windowFrame: window.frame) {
                elements.append(
                    ClickableElement(
                        role: visit.node.role,
                        subrole: visit.node.subrole,
                        actions: visit.node.actions,
                        frame: visit.node.frame ?? ElementFrame(x: 0, y: 0, width: 0, height: 0),
                        path: visit.path
                    )
                )
            }
            return false
        }
        return ClickableSnapshot(elements: elements, truncated: truncated)
    }

    public static func firstEditableInput(
        in window: AccessibilityElement,
        limits: TreeWalkLimits
    ) -> EditableInputQuery {
        var found: EditableInputTarget?
        let truncated = walk(window, limits: limits) { visit in
            if found != nil || visit.holeBefore {
                return found != nil
            }
            guard !visit.isRoot,
                  editability(of: visit.node) == .editable,
                  isOnScreen(visit.node, windowFrame: window.frame),
                  let frame = visit.node.frame
            else {
                return false
            }
            found = EditableInputTarget(
                role: visit.node.role,
                subrole: visit.node.subrole,
                frame: frame,
                path: visit.path
            )
            return true
        }
        if let found {
            return .found(found)
        }
        return truncated ? .unavailable : .none
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
        if let subrole = element.subrole, clickableSubroles.contains(subrole) {
            return true
        }
        if let role = element.role, containerRoles.contains(role) {
            return false
        }
        if let role = element.role, clickableRoles.contains(role) {
            return true
        }
        return element.actions.contains { pressActions.contains($0) }
    }

    private static func isOnScreen(_ element: AccessibilityElement, windowFrame: ElementFrame?) -> Bool {
        guard let frame = element.frame, frame.width > 0, frame.height > 0 else {
            return false
        }
        guard let windowFrame else {
            return true
        }
        guard windowFrame.width > 0, windowFrame.height > 0 else {
            return false
        }
        let left = max(frame.x, windowFrame.x)
        let right = min(frame.x + frame.width, windowFrame.x + windowFrame.width)
        let top = max(frame.y, windowFrame.y)
        let bottom = min(frame.y + frame.height, windowFrame.y + windowFrame.height)
        return right - left > 0 && bottom - top > 0
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
public protocol AccessibilityReading: AnyObject, Sendable {
    func readFocusedElement() -> AccessibilityRead<AccessibilityElement>
    func readFrontmostBundleIdentifier() -> AccessibilityRead<String>
    func readFrontmostWindow(maxNodes: Int, maxDepth: Int) -> AccessibilityRead<AccessibilityElement>
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
    private weak var wiring: EventTapWiring?
    private let lock = NSLock()
    private var started = false

    public init(
        reader: any AccessibilityReading,
        signals: any FocusChangeSignaling,
        cache: any FocusCacheReplacing,
        limits: TreeWalkLimits = .standard
    ) {
        self.reader = reader
        self.signals = signals
        self.cache = cache
        self.limits = limits
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
        switch reader.readFrontmostWindow(maxNodes: limits.maxNodes, maxDepth: limits.maxDepth) {
        case .unavailable:
            return .unavailable
        case .value(let window):
            return .elements(FocusClassification.clickableElements(in: window, limits: limits))
        }
    }

    public func firstEditableInput() -> EditableInputQuery {
        switch reader.readFrontmostWindow(maxNodes: limits.maxNodes, maxDepth: limits.maxDepth) {
        case .unavailable:
            return .unavailable
        case .value(let window):
            return FocusClassification.firstEditableInput(in: window, limits: limits)
        }
    }

    private func classifiedFocus() -> CachedFocus {
        let editability: FocusEditability
        switch reader.readFocusedElement() {
        case .unavailable:
            editability = .unknown
        case .value(let element):
            editability = FocusClassification.editability(of: element)
        }
        switch reader.readFrontmostBundleIdentifier() {
        case .unavailable:
            return CachedFocus(editability: editability, bundleIdentifier: "")
        case .value(let identifier):
            return CachedFocus(editability: editability, bundleIdentifier: identifier)
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
        limits: TreeWalkLimits = .standard
    ) {
        let cache = LockedFocusCache()
        let scanner = AXScanner(reader: reader, signals: signals, cache: cache, limits: limits)
        let wiring = EventTapWiring(decider: decider, cache: cache, scanner: scanner)
        scanner.connect(wiring)
        self.cache = cache
        self.scanner = scanner
        self.wiring = wiring
    }
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

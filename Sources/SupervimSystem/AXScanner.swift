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
    /// `AXEnabled`. Nil when the element does not say.
    public var isEnabled: Bool?

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
        horizontalScroll: ScrollBarReading? = nil,
        isEnabled: Bool? = nil
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
        self.isEnabled = isEnabled
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

    /// Walks the copied tree once and returns one target per control.
    ///
    /// A frame is clipped by the window and by the scroll and web areas the
    /// element is actually inside. An area elsewhere in the window is not a
    /// clip: a row scrolled out of its list must not get a label where the
    /// toolbar is, and a button beside a list must not be cut by that list.
    ///
    /// After the walk, nested and stacked candidates are collapsed. See
    /// `ClickableDedupe`.
    static func countedClickables(
        in window: AccessibilityElement,
        limits: TreeWalkLimits
    ) -> (snapshot: ClickableSnapshot, visited: Int) {
        var candidates: [ClickableCandidate] = []
        var visited = 0
        let windowRect = window.frame.map(hintRect)
        let truncated = walk(window, limits: limits, context: ClipContext()) { visit, context in
            visited += 1
            if !visit.isRoot, hidesItsChildren(visit.node.role) {
                noteCandidate(visit, context: context, window: windowRect, into: &candidates)
                return .skipChildren
            }
            var next = context
            if !visit.isRoot,
               let index = noteCandidate(visit, context: context, window: windowRect, into: &candidates) {
                next.nearest = index
            }
            next.enter(visit.node)
            return .descend(next)
        }
        let kept = ClickableDedupe.resolve(candidates, window: windowRect)
        return (ClickableSnapshot(elements: kept, truncated: truncated), visited)
    }

    @discardableResult
    private static func noteCandidate(
        _ visit: WalkVisit,
        context: ClipContext,
        window: HintRect?,
        into candidates: inout [ClickableCandidate]
    ) -> Int? {
        guard let kind = clickableKind(visit.node, context: context),
              let raw = visit.node.frame.map(hintRect),
              let visible = HintGeometry.visibleElement(raw, window: window, ancestors: context.ancestors)
        else {
            return nil
        }
        candidates.append(ClickableCandidate(
            element: ClickableElement(
                role: visit.node.role,
                subrole: visit.node.subrole,
                actions: visit.node.actions,
                frame: elementFrame(visible),
                path: visit.path
            ),
            visible: visible,
            kind: kind,
            parent: context.nearest,
            isTextField: InputChoice.isTextInput(role: visit.node.role, subrole: visit.node.subrole)
        ))
        return candidates.count - 1
    }

    static func editableCandidates(
        in window: AccessibilityElement,
        limits: TreeWalkLimits,
        inFocusedWindow: Bool
    ) -> (candidates: [InputCandidate], truncated: Bool) {
        var candidates: [InputCandidate] = []
        let windowRect = window.frame.map(hintRect)
        let truncated = walk(window, limits: limits, context: ClipContext()) { visit, context in
            var next = context
            next.enter(visit.node)
            guard !visit.isRoot,
                  editability(of: visit.node) == .editable,
                  InputChoice.isTextInput(role: visit.node.role, subrole: visit.node.subrole),
                  let raw = visit.node.frame.map(hintRect),
                  let visible = HintGeometry.visibleElement(raw, window: windowRect, ancestors: context.ancestors)
            else {
                return .descend(next)
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
            return .descend(next)
        }
        return (candidates, truncated)
    }

    /// Roles whose children are parts of the control, or a second way to
    /// reach nodes the walk already visits. A scroll bar's arrows are not
    /// targets. A table column lists the same cells as its rows.
    static func hidesItsChildren(_ role: String?) -> Bool {
        role == "AXScrollBar" || role == "AXColumn"
    }

    /// Whether the reader has to ask for the action names of this role.
    /// Layout containers do not get a label from an action, so the extra
    /// round trip is skipped for them.
    public static func wantsActionNames(role: String?) -> Bool {
        guard let role else {
            return true
        }
        return !structuralRoles.contains(role)
    }

    static func isViewport(_ element: AccessibilityElement) -> Bool {
        element.role == "AXScrollArea" || element.role == "AXWebArea"
    }

    static func hintRect(_ frame: ElementFrame) -> HintRect {
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

    /// Roles that never take typed text. A role that is not listed here and
    /// has no `AXEditable` answer stays unknown, and unknown passes keys
    /// through. `AXEditable == true` is checked before this list, so an
    /// editable cell is still editable.
    private static let knownNonEditableRoles: Set<String> = [
        "AXApplication",
        "AXBrowser",
        "AXBusyIndicator",
        "AXButton",
        "AXCell",
        "AXCheckBox",
        "AXColorWell",
        "AXColumn",
        "AXDisclosureTriangle",
        "AXDockItem",
        "AXDrawer",
        "AXGrid",
        "AXGroup",
        "AXGrowArea",
        "AXHandle",
        "AXHeading",
        "AXHelpTag",
        "AXImage",
        "AXIncrementor",
        "AXLayoutArea",
        "AXLayoutItem",
        "AXLevelIndicator",
        "AXLink",
        "AXList",
        "AXMatte",
        "AXMenuButton",
        "AXOutline",
        "AXPage",
        "AXPopover",
        "AXProgressIndicator",
        "AXRadioButton",
        "AXRadioGroup",
        "AXRelevanceIndicator",
        "AXRow",
        "AXRuler",
        "AXRulerMarker",
        "AXScrollArea",
        "AXScrollBar",
        "AXSlider",
        "AXSplitGroup",
        "AXSplitter",
        "AXStaticText",
        "AXSwitch",
        "AXTab",
        "AXTabGroup",
        "AXTable",
        "AXToggle",
        "AXToolbar",
        "AXValueIndicator",
        "AXWebArea",
        "AXWindow",
    ]

    private static let clickableRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXColorWell",
        "AXComboBox",
        "AXDateField",
        "AXDisclosureTriangle",
        "AXDockItem",
        "AXIncrementor",
        "AXLevelIndicator",
        "AXLink",
        "AXMenuBarItem",
        "AXMenuButton",
        "AXMenuItem",
        "AXPopUpButton",
        "AXRadioButton",
        "AXSlider",
        "AXSwitch",
        "AXTab",
        "AXTextArea",
        "AXTextField",
        "AXTimeField",
        "AXToggle",
    ]

    private static let clickableSubroles: Set<String> = [
        "AXCloseButton",
        "AXFullScreenButton",
        "AXMenuExtra",
        "AXMinimizeButton",
        "AXSearchField",
        "AXSecureTextField",
        "AXSortButton",
        "AXSwitch",
        "AXTabButton",
        "AXToggle",
        "AXToolbarButton",
        "AXZoomButton",
    ]

    /// Containers that only lay out other elements. No label comes from an
    /// action on one of these, so the reader does not ask for their actions.
    private static let structuralRoles: Set<String> = [
        "AXApplication",
        "AXBrowser",
        "AXColumn",
        "AXLayoutArea",
        "AXList",
        "AXMenuBar",
        "AXOutline",
        "AXScrollArea",
        "AXScrollBar",
        "AXSplitGroup",
        "AXSplitter",
        "AXTabGroup",
        "AXTable",
        "AXToolbar",
        "AXValueIndicator",
        "AXWebArea",
        "AXWindow",
    ]

    /// Roles that hold text or an image. `AXShowMenu` on one of these is the
    /// context menu every web node has, not a button.
    private static let passiveRoles: Set<String> = [
        "AXCell",
        "AXHeading",
        "AXImage",
        "AXStaticText",
        "AXUnknown",
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

    private static let pressActions: Set<String> = ["AXPress", "AXConfirm", "AXPick", "AXOpen"]

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

    /// How a node became a target. Nil when it is not one.
    ///
    /// `control`: the role or subrole is a control.
    /// `passive`: only an action says so, as on a group with a click handler.
    /// `weak`: a table or outline row, or a cell with no row above it. These
    /// select on click. Web tables are left out: every `<tr>` and `<td>`
    /// has those roles.
    private static func clickableKind(
        _ element: AccessibilityElement,
        context: ClipContext
    ) -> ClickableKind? {
        if element.isEnabled == false {
            return nil
        }
        let byRole = isControl(element)
        if element.actions.contains(where: { pressActions.contains($0) }) {
            return byRole ? .control : .passive
        }
        if byRole {
            return .control
        }
        if element.actions.contains("AXShowMenu"), let role = element.role,
           !containerRoles.contains(role), !passiveRoles.contains(role) {
            return .passive
        }
        if !context.insideWeb {
            if element.role == "AXRow" {
                return .weak
            }
            if element.role == "AXCell", !context.insideRow {
                return .weak
            }
        }
        return nil
    }

    private static func isControl(_ element: AccessibilityElement) -> Bool {
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

enum ClickableKind: Equatable, Sendable {
    case control
    case passive
    case weak
}

/// What a node inherits from the nodes above it.
struct ClipContext {
    /// Frames of the scroll and web areas above the node, outermost first.
    var ancestors: [HintRect] = []
    var insideWeb = false
    var insideRow = false
    /// Index of the closest candidate above the node.
    var nearest: Int?

    mutating func enter(_ node: AccessibilityElement) {
        if FocusClassification.isViewport(node), let frame = node.frame {
            let rect = FocusClassification.hintRect(frame)
            if rect.isUsable {
                ancestors.append(rect)
            }
        }
        if node.role == "AXWebArea" {
            insideWeb = true
        }
        if node.role == "AXRow" {
            insideRow = true
        }
    }
}

struct ClickableCandidate {
    var element: ClickableElement
    var visible: HintRect
    var kind: ClickableKind
    /// Closest candidate above this one, kept or not.
    var parent: Int?
    var isTextField: Bool
}

/// Collapses candidates that are one control.
///
/// Candidates arrive in tree order, so a parent comes before its children.
///
/// 1. A row with a text field inside is dropped. The field stands for the
///    row, as it does in a Finder list.
/// 2. A node that is a target only because of an action is dropped when a
///    kept control, or a kept action-only node, is above it. That is the
///    text and the icon of a link, which Chromium also marks pressable.
/// 3. An action-only node with nothing kept above it is dropped when it is a
///    wrapper: it holds three or more controls, or it holds two or more
///    targets and covers a large part of the window. A page whose root has
///    the click handler is the usual case.
/// 4. A target whose kept children cover it is dropped. A stepper is its
///    two arrows.
/// 5. Targets whose visible frames are nearly the same rectangle are one
///    click point. A control wins over an action-only node, which wins over
///    a row. Then one with `AXPress` wins. Then the earlier one.
enum ClickableDedupe {
    static let sameFrameOverlap = 0.8
    static let coveredShare = 0.85
    static let wrapperWindowShare = 0.25
    static let wrapperMinimumArea = 90_000.0
    static let wrapperAreaWithoutWindow = 150_000.0

    static func resolve(_ candidates: [ClickableCandidate], window: HintRect?) -> [ClickableElement] {
        let count = candidates.count
        guard count > 1 else {
            return candidates.map(\.element)
        }
        var descendants = [Int](repeating: 0, count: count)
        var controls = [Int](repeating: 0, count: count)
        var holdsTextField = [Bool](repeating: false, count: count)
        for index in stride(from: count - 1, through: 0, by: -1) {
            guard let parent = candidates[index].parent else {
                continue
            }
            descendants[parent] += 1 + descendants[index]
            controls[parent] += controls[index] + (candidates[index].kind == .control ? 1 : 0)
            if candidates[index].isTextField || holdsTextField[index] {
                holdsTextField[parent] = true
            }
        }

        var alive = [Bool](repeating: true, count: count)
        var keptAbove = [Int?](repeating: nil, count: count)
        let wrapperArea = wrapperThreshold(window)
        for index in 0..<count {
            let candidate = candidates[index]
            var above = candidate.parent
            while let current = above, !alive[current] {
                above = candidates[current].parent
            }
            keptAbove[index] = above
            switch candidate.kind {
            case .control:
                break
            case .weak:
                if holdsTextField[index] {
                    alive[index] = false
                } else if let above, candidates[above].kind == .weak {
                    alive[index] = false
                }
            case .passive:
                if let above, candidates[above].kind != .weak {
                    alive[index] = false
                } else if controls[index] >= 3
                    || (descendants[index] >= 2 && area(candidate.visible) >= wrapperArea) {
                    alive[index] = false
                }
            }
        }

        var covered = [Double](repeating: 0, count: count)
        var children = [Int](repeating: 0, count: count)
        for index in 0..<count where alive[index] {
            var above = candidates[index].parent
            while let current = above, !alive[current] {
                above = candidates[current].parent
            }
            guard let above else {
                continue
            }
            covered[above] += overlap(candidates[index].visible, candidates[above].visible)
            children[above] += 1
        }
        for index in 0..<count where alive[index] && children[index] >= 2 {
            let whole = area(candidates[index].visible)
            if whole > 0, covered[index] >= whole * coveredShare {
                alive[index] = false
            }
        }

        let order = (0..<count).filter { alive[$0] }.sorted {
            candidates[$0].visible.x < candidates[$1].visible.x
        }
        for (position, first) in order.enumerated() where alive[first] {
            let frame = candidates[first].visible
            let reach = max(4, frame.width * 0.25)
            var next = position + 1
            while next < order.count {
                let second = order[next]
                next += 1
                let other = candidates[second].visible
                if other.x - frame.x > reach {
                    break
                }
                guard alive[second], sameTarget(frame, other) else {
                    continue
                }
                if outranks(candidates[second], second, candidates[first], first) {
                    alive[first] = false
                    break
                }
                alive[second] = false
            }
        }
        return (0..<count).filter { alive[$0] }.map { candidates[$0].element }
    }

    private static func wrapperThreshold(_ window: HintRect?) -> Double {
        guard let window, window.isUsable else {
            return wrapperAreaWithoutWindow
        }
        return max(area(window) * wrapperWindowShare, wrapperMinimumArea)
    }

    private static func outranks(
        _ lhs: ClickableCandidate,
        _ lhsIndex: Int,
        _ rhs: ClickableCandidate,
        _ rhsIndex: Int
    ) -> Bool {
        let left = rank(lhs.kind)
        let right = rank(rhs.kind)
        if left != right {
            return left > right
        }
        let leftPress = lhs.element.actions.contains("AXPress")
        let rightPress = rhs.element.actions.contains("AXPress")
        if leftPress != rightPress {
            return leftPress
        }
        return lhsIndex < rhsIndex
    }

    private static func rank(_ kind: ClickableKind) -> Int {
        switch kind {
        case .control:
            return 3
        case .passive:
            return 2
        case .weak:
            return 1
        }
    }

    private static func sameTarget(_ lhs: HintRect, _ rhs: HintRect) -> Bool {
        let shared = overlap(lhs, rhs)
        guard shared > 0 else {
            return false
        }
        let union = area(lhs) + area(rhs) - shared
        return union > 0 && shared / union >= sameFrameOverlap
    }

    private static func overlap(_ lhs: HintRect, _ rhs: HintRect) -> Double {
        let width = min(lhs.x + lhs.width, rhs.x + rhs.width) - max(lhs.x, rhs.x)
        let height = min(lhs.y + lhs.height, rhs.y + rhs.height) - max(lhs.y, rhs.y)
        guard width > 0, height > 0 else {
            return 0
        }
        return width * height
    }

    private static func area(_ rect: HintRect) -> Double {
        let value = rect.width * rect.height
        return value.isFinite && value > 0 ? value : 0
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
    /// Names the live walk this copy came from. The scanner hands it back
    /// through `adoptWalk` so presses, scroll bars and `gi` act on the
    /// elements of the tree that was actually used.
    public var walk: Int?

    public init(source: String, found: Bool, element: AccessibilityElement?, walk: Int? = nil) {
        self.source = source
        self.found = found
        self.element = element
        self.walk = walk
    }
}

/// One pass over the front window: what can be clicked, the first text
/// input, and the tree itself for the scroll catalog. One walk feeds all
/// three, so they agree with each other.
public struct WindowScan: Equatable, Sendable {
    public var clickables: ClickableQuery
    public var firstInput: EditableInputQuery
    public var window: AccessibilityRead<AccessibilityElement>
    public var source: String
    public var visited: Int
    public var hits: Int

    public init(
        clickables: ClickableQuery,
        firstInput: EditableInputQuery,
        window: AccessibilityRead<AccessibilityElement>,
        source: String,
        visited: Int,
        hits: Int
    ) {
        self.clickables = clickables
        self.firstInput = firstInput
        self.window = window
        self.source = source
        self.visited = visited
        self.hits = hits
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
    /// The same order, one window at a time. Each choice is offered to
    /// `accept` as soon as it is copied, and no further window is read once
    /// `accept` returns true. A window nobody will use is not walked.
    /// `budgetMilliseconds` bounds each walk. Nil means no deadline.
    func readWindowChoices(
        limits: TreeWalkLimits,
        budgetMilliseconds: Double?,
        accept: (AccessibilityWindowChoice) -> Bool
    ) -> [AccessibilityWindowChoice]
    /// The application element, used when every window attribute is empty.
    func readApplicationElement(maxNodes: Int, maxDepth: Int) -> AccessibilityElement?
    func readApplicationChoice(limits: TreeWalkLimits, budgetMilliseconds: Double?) -> AccessibilityWindowChoice?
    /// Keeps the live elements of this walk for later presses, scroll-bar
    /// writes and input focus, and forgets the other walks. Nil forgets all.
    func adoptWalk(_ walk: Int?)
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

    public func readWindowChoices(
        limits: TreeWalkLimits,
        budgetMilliseconds: Double?,
        accept: (AccessibilityWindowChoice) -> Bool
    ) -> [AccessibilityWindowChoice] {
        _ = budgetMilliseconds
        let choices = readWindowChoices(maxNodes: limits.maxNodes, maxDepth: limits.maxDepth)
        for choice in choices where accept(choice) {
            break
        }
        return choices
    }

    public func readApplicationChoice(
        limits: TreeWalkLimits,
        budgetMilliseconds: Double?
    ) -> AccessibilityWindowChoice? {
        _ = budgetMilliseconds
        guard let element = readApplicationElement(maxNodes: limits.maxNodes, maxDepth: limits.maxDepth) else {
            return nil
        }
        return AccessibilityWindowChoice(source: "application", found: true, element: element)
    }

    public func adoptWalk(_ walk: Int?) {
        _ = walk
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
    private var scanHandler: (@Sendable (WindowScan) -> Void)?

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

    /// The longest one walk for `f` may take. It is a ceiling for a tree
    /// that never ends, not a target: a cut walk loses the deepest nodes
    /// first, and in a browser those are the page.
    public static let hintScanBudgetMilliseconds = 1_000.0

    public func clickableElements() -> ClickableQuery {
        scanWindow(budgetMilliseconds: Self.hintScanBudgetMilliseconds).clickables
    }

    /// Called with every finished scan, on the thread that scanned.
    public func onWindowScan(_ handler: @escaping @Sendable (WindowScan) -> Void) {
        lock.lock()
        scanHandler = handler
        lock.unlock()
    }

    /// Reads the front window once and derives the hint targets, the first
    /// text input and the tree for the scroll catalog from that one copy.
    ///
    /// Windows are tried in the order focused, main, `AXWindows`, and the
    /// first one with a clickable element ends the search. When none has
    /// one, the app is asked to expose its tree and the read is repeated.
    @discardableResult
    public func scanWindow(budgetMilliseconds: Double? = nil) -> WindowScan {
        let watch = TraceStopwatch()
        let bundle = frontmostBundle()
        var expansion = "none"
        var retry = "none"
        var picked = readChoices(budgetMilliseconds)
        if picked.hits == 0 {
            let manual = reader.expandAccessibilityTree(allowEnhanced: false)
            if manual == .manual {
                expansion = "manual"
                pauseForTree()
                picked = readChoices(budgetMilliseconds)
                retry = picked.hits > 0 ? "hits" : "empty"
            }
        }
        if picked.hits == 0 {
            let enhanced = reader.expandAccessibilityTree(allowEnhanced: true)
            if enhanced == .enhanced {
                expansion = expansion == "manual" ? "manual+enhanced" : "enhanced"
                pauseForTree()
                picked = readChoices(budgetMilliseconds)
                retry = picked.hits > 0 ? "hits" : "empty"
            } else if enhanced == .manual && expansion == "none" {
                expansion = "manual"
                pauseForTree()
                picked = readChoices(budgetMilliseconds)
                retry = picked.hits > 0 ? "hits" : "empty"
            }
        }
        reader.adoptWalk(picked.walk)
        let milliseconds = watch.milliseconds
        if ModeTrace.isEnabled {
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
                milliseconds: Int(milliseconds.rounded()),
                expansion: expansion,
                retry: retry
            )
            ModeTrace.noteTiming(
                stage: "ax-scan",
                milliseconds: milliseconds,
                fields: [("nodes", "\(picked.visited)"), ("hits", "\(picked.hits)"), ("window", picked.window)]
            )
        }
        let scan = WindowScan(
            clickables: picked.query,
            firstInput: firstInput(in: picked),
            window: picked.root.map { .value($0) } ?? .unavailable,
            source: picked.window,
            visited: picked.visited,
            hits: picked.hits
        )
        lock.lock()
        let handler = scanHandler
        lock.unlock()
        handler?(scan)
        return scan
    }

    private func pauseForTree() {
        waiter?.waitForAccessibilityTree(milliseconds: populationDelayMilliseconds)
    }

    private func readChoices(_ budgetMilliseconds: Double?) -> ScanPick {
        var picks: [ScanPick] = []
        let choices = reader.readWindowChoices(limits: limits, budgetMilliseconds: budgetMilliseconds) { choice in
            guard choice.found, let element = choice.element else {
                return false
            }
            let counted = FocusClassification.countedClickables(in: element, limits: limits)
            picks.append(ScanPick(
                query: .elements(counted.snapshot),
                visited: counted.visited,
                hits: counted.snapshot.elements.count,
                window: choice.source,
                found: 1,
                root: element,
                walk: choice.walk
            ))
            return counted.snapshot.elements.count > 0
        }
        if ModeTrace.isEnabled {
            if choices.isEmpty {
                ModeTrace.noteLine(ModeTrace.formatHintWindow(source: "none", found: 0, children: 0))
            }
            for choice in choices {
                ModeTrace.noteLine(ModeTrace.formatHintWindow(
                    source: choice.source,
                    found: choice.found ? 1 : 0,
                    children: choice.element?.children.count ?? 0
                ))
            }
        }
        var picked = picks.first(where: { $0.hits > 0 }) ?? picks.first
            ?? ScanPick(query: .unavailable, visited: 0, hits: 0, window: "missing", found: 0, root: nil, walk: nil)
        if picked.hits == 0,
           let application = reader.readApplicationChoice(limits: limits, budgetMilliseconds: budgetMilliseconds),
           let root = application.element {
            ModeTrace.noteLine(ModeTrace.formatHintWindow(
                source: "application",
                found: 1,
                children: root.children.count
            ))
            let counted = FocusClassification.countedClickables(in: root, limits: limits)
            if counted.snapshot.elements.count > 0 || picked.found == 0 {
                picked = ScanPick(
                    query: .elements(counted.snapshot),
                    visited: counted.visited,
                    hits: counted.snapshot.elements.count,
                    window: "application",
                    found: 1,
                    root: root,
                    walk: application.walk
                )
            }
        }
        return picked
    }

    /// The first input of the window that was picked. Its path is a path in
    /// that window's walk, which is the walk `adoptWalk` kept.
    private func firstInput(in picked: ScanPick) -> EditableInputQuery {
        guard let root = picked.root else {
            return .unavailable
        }
        let found = FocusClassification.editableCandidates(
            in: root,
            limits: limits,
            inFocusedWindow: picked.window == "focused" || picked.window == "application"
        )
        let lastFocused = cache.currentFocus().elementIdentity
        if let best = InputChoice.best(found.candidates, lastFocusedIdentity: lastFocused, window: nil) {
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
        return found.truncated ? .unavailable : .none
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
    var walk: Int?
}

private struct WalkVisit {
    var node: AccessibilityElement
    var path: [Int]
    var isRoot: Bool
    /// True when an earlier node omitted children that tree order would have visited first.
    var holeBefore: Bool
}

/// What the walk does after one node.
/// `descend` hands the context to that node's children. `skipChildren`
/// leaves them out on purpose, which is not a truncation.
private enum WalkStep<Context> {
    case descend(Context)
    case skipChildren
    case stop
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
private func walk<Context>(
    _ root: AccessibilityElement,
    limits: TreeWalkLimits,
    context: Context,
    _ body: (WalkVisit, Context) -> WalkStep<Context>
) -> Bool {
    let cursor = WalkCursor(limits: limits)
    visit(root, path: [], depth: 0, isRoot: true, context: context, cursor: cursor, body: body)
    return cursor.truncated
}

private func visit<Context>(
    _ node: AccessibilityElement,
    path: [Int],
    depth: Int,
    isRoot: Bool,
    context: Context,
    cursor: WalkCursor,
    body: (WalkVisit, Context) -> WalkStep<Context>
) {
    if cursor.stopped {
        return
    }
    cursor.visited += 1
    let step = body(
        WalkVisit(node: node, path: path, isRoot: isRoot, holeBefore: cursor.truncated),
        context
    )
    let inherited: Context
    switch step {
    case .stop:
        cursor.stopped = true
        return
    case .skipChildren:
        return
    case .descend(let next):
        inherited = next
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
            context: inherited,
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

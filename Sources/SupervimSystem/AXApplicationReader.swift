#if canImport(ApplicationServices)
import ApplicationServices
import CoreFoundation
import Foundation
import SupervimCore

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(AppKit)
import AppKit
#endif

/// Live Accessibility reader for the frontmost app.
///
/// `AXIsProcessTrusted() == false` is reported as unavailable. The scanner turns
/// that into unknown focus, and ModeMachine passes keys through. Whether trust
/// becomes true without restarting after the user grants Accessibility is not a
/// platform guarantee and is unverified. This type does not prompt.
///
/// Every call here waits for another process. None of it runs on the key
/// hook. Three things keep the wait short.
///
/// One round trip per node. A node's role, subrole, position, size,
/// children, editable flag, enabled flag and scroll bars come back from one
/// `AXUIElementCopyMultipleAttributeValues`. Action names are a second
/// call, and only for roles that can be clicked.
///
/// A bounded wait. `AXUIElementSetMessagingTimeout` replaces the default of
/// about six seconds per call. An app that does not answer ends the walk.
///
/// Less to read. `AccessibilityTreeWalker` reads a level of the tree on
/// several threads, skips what the window and its scroll areas hide, and
/// stops at a deadline. Windows are walked one at a time, and the rest are
/// not walked once one has been accepted.
public final class AXSystemReader: AccessibilityReading, @unchecked Sendable {
    /// How long one accessibility call may wait for the app.
    public static let messagingTimeoutSeconds: Float = 0.75
    /// Threads that read one level of the tree.
    public static let walkWorkers = 4

    private let identities = FocusIdentityVault()
    private let expansions = AccessibilityExpander()
    private let scrollElements: AXElementStore?
    private let inputs: AXInputFocuser?
    private let ledger = WalkLedger()
    private let messaging = MessagingTimeout()

    public init(scrollElements: AXElementStore? = nil, inputs: AXInputFocuser? = nil) {
        self.scrollElements = scrollElements
        self.inputs = inputs
    }

    public func expandAccessibilityTree(allowEnhanced: Bool) -> AccessibilityTreeExpansion {
        guard AXIsProcessTrusted() else {
            return .unchanged
        }
        let system = AXUIElementCreateSystemWide()
        guard let application = copyElement(system, kAXFocusedApplicationAttribute) else {
            return .unchanged
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(application, &pid) == .success, pid != 0 else {
            return .unchanged
        }
        return expansions.expand(application, pid: pid, allowEnhanced: allowEnhanced)
    }

    public func readFocusedElement() -> AccessibilityRead<AccessibilityElement> {
        guard AXIsProcessTrusted() else {
            return .unavailable
        }
        messaging.applyOnce(seconds: Self.messagingTimeoutSeconds)
        let system = AXUIElementCreateSystemWide()
        guard let element = copyElement(system, kAXFocusedUIElementAttribute) else {
            return .unavailable
        }
        var copied: AccessibilityElement
        switch readLiveNode(element, attributes: LiveAttributes.focus, slowMilliseconds: slowMilliseconds) {
        case .node(let reading):
            copied = reading.element
        case .gone, .unresponsive:
            return .unavailable
        }
        copied.identity = focusIdentity(element)
        return .value(copied)
    }

    public func readFrontmostBundleIdentifier() -> AccessibilityRead<String> {
        guard AXIsProcessTrusted() else {
            return .unavailable
        }
        let system = AXUIElementCreateSystemWide()
        if let application = copyElement(system, kAXFocusedApplicationAttribute) {
            var pid: pid_t = 0
            if AXUIElementGetPid(application, &pid) == .success, let identifier = bundleIdentifier(pid: pid) {
                return .value(identifier)
            }
        }
        if let identifier = frontmostBundleIdentifier() {
            return .value(identifier)
        }
        return .unavailable
    }

    public func readFrontmostWindow(maxNodes: Int, maxDepth: Int) -> AccessibilityRead<AccessibilityElement> {
        let limits = TreeWalkLimits(maxNodes: maxNodes, maxDepth: maxDepth)
        var kept: AccessibilityWindowChoice?
        let choices = readWindowChoices(limits: limits, budgetMilliseconds: nil) { choice in
            guard choice.found, choice.element?.children.isEmpty == false else {
                return false
            }
            kept = choice
            return true
        }
        if let kept, let element = kept.element {
            adoptWalk(kept.walk)
            return .value(element)
        }
        if let application = readApplicationChoice(limits: limits, budgetMilliseconds: nil),
           let element = application.element,
           !element.children.isEmpty {
            adoptWalk(application.walk)
            return .value(element)
        }
        if let choice = choices.first(where: \.found), let element = choice.element {
            adoptWalk(choice.walk)
            return .value(element)
        }
        adoptWalk(nil)
        return .unavailable
    }

    public func readWindowChoices(maxNodes: Int, maxDepth: Int) -> [AccessibilityWindowChoice] {
        readWindowChoices(
            limits: TreeWalkLimits(maxNodes: maxNodes, maxDepth: maxDepth),
            budgetMilliseconds: nil
        ) { _ in
            false
        }
    }

    /// Focused window, then main window, then `AXWindows`. A window is
    /// walked when its turn comes and offered to `accept` at once. After
    /// `accept` says yes, or after the app stopped answering, no other
    /// window is read.
    public func readWindowChoices(
        limits: TreeWalkLimits,
        budgetMilliseconds: Double?,
        accept: (AccessibilityWindowChoice) -> Bool
    ) -> [AccessibilityWindowChoice] {
        let missing = [AccessibilityWindowChoice(source: "focused", found: false, element: nil)]
        guard AXIsProcessTrusted() else {
            return missing
        }
        messaging.applyOnce(seconds: Self.messagingTimeoutSeconds)
        let system = AXUIElementCreateSystemWide()
        guard let application = copyElement(system, kAXFocusedApplicationAttribute) else {
            return missing
        }
        var choices: [AccessibilityWindowChoice] = []
        var seen: [AXUIElement] = []
        var finished = false
        func offer(_ element: AXUIElement?, source: String, recordMiss: Bool) {
            guard !finished else {
                return
            }
            guard let element else {
                if recordMiss {
                    choices.append(AccessibilityWindowChoice(source: source, found: false, element: nil))
                }
                return
            }
            if seen.contains(where: { sameAXElement($0, element) }) {
                return
            }
            seen.append(element)
            let walked = walkTree(element, limits: limits, budgetMilliseconds: budgetMilliseconds, source: source)
            let choice = AccessibilityWindowChoice(
                source: source,
                found: walked.root != nil,
                element: walked.root,
                walk: walked.walk
            )
            choices.append(choice)
            if walked.unresponsive || accept(choice) {
                finished = true
            }
        }
        offer(copyElement(application, kAXFocusedWindowAttribute), source: "focused", recordMiss: true)
        if !finished {
            offer(copyElement(application, kAXMainWindowAttribute), source: "main", recordMiss: true)
        }
        if !finished {
            let windows = copyElements(application, kAXWindowsAttribute)
            if windows.isEmpty {
                choices.append(AccessibilityWindowChoice(source: "windows", found: false, element: nil))
            } else {
                for window in windows.prefix(8) {
                    offer(window, source: "windows", recordMiss: false)
                }
            }
        }
        return choices
    }

    public func readApplicationElement(maxNodes: Int, maxDepth: Int) -> AccessibilityElement? {
        readApplicationChoice(
            limits: TreeWalkLimits(maxNodes: maxNodes, maxDepth: maxDepth),
            budgetMilliseconds: nil
        )?.element
    }

    public func readApplicationChoice(
        limits: TreeWalkLimits,
        budgetMilliseconds: Double?
    ) -> AccessibilityWindowChoice? {
        guard AXIsProcessTrusted() else {
            return nil
        }
        messaging.applyOnce(seconds: Self.messagingTimeoutSeconds)
        let system = AXUIElementCreateSystemWide()
        guard let application = copyElement(system, kAXFocusedApplicationAttribute) else {
            return nil
        }
        let walked = walkTree(
            application,
            limits: limits,
            budgetMilliseconds: budgetMilliseconds,
            source: "application"
        )
        guard let root = walked.root else {
            return nil
        }
        return AccessibilityWindowChoice(source: "application", found: true, element: root, walk: walked.walk)
    }

    /// Binds the elements of one walk under the path keys the catalog and
    /// the hint labels use: every node for presses and scroll bars, text
    /// inputs for `gi`. The other walks are forgotten, so a path can only
    /// mean an element of the window that was chosen.
    public func adoptWalk(_ walk: Int?) {
        let stored = ledger.take(walk)
        inputs?.resetInputs()
        guard let stored else {
            scrollElements?.reset()
            return
        }
        var elements: [String: AXUIElement] = [:]
        elements.reserveCapacity(stored.bound.count)
        for bound in stored.bound {
            elements[ScrollTargetIdentity.identifier(path: bound.path)] = bound.node.element
            if let node = copiedNode(at: bound.path, in: stored.root),
               InputChoice.isTextInput(role: node.role, subrole: node.subrole) {
                inputs?.bindInput(bound.node.element, path: bound.path)
            }
        }
        scrollElements?.replace(with: elements)
    }

    private var slowMilliseconds: Double {
        Double(Self.messagingTimeoutSeconds) * 1_000 * 0.8
    }

    private struct Walked {
        var root: AccessibilityElement?
        var walk: Int?
        var unresponsive: Bool
    }

    private func walkTree(
        _ element: AXUIElement,
        limits: TreeWalkLimits,
        budgetMilliseconds: Double?,
        source: String
    ) -> Walked {
        let walked = AccessibilityTreeWalker.walk(
            root: LiveNode(element: element),
            source: LiveNodeSource(slowMilliseconds: slowMilliseconds),
            options: TreeWalkOptions(
                limits: limits,
                budgetMilliseconds: budgetMilliseconds,
                workers: Self.walkWorkers
            )
        )
        ModeTrace.noteTiming(
            stage: "ax-walk",
            milliseconds: walked.milliseconds,
            fields: [
                ("window", source),
                ("nodes", "\(walked.read)"),
                ("pruned", "\(walked.pruned)"),
                ("levels", "\(walked.levels)"),
                ("truncated", walked.truncated ? "1" : "0"),
                ("deadline", walked.timedOut ? "1" : "0"),
                ("unresponsive", walked.unresponsive ? "1" : "0"),
            ]
        )
        guard let root = walked.root else {
            return Walked(root: nil, walk: nil, unresponsive: walked.unresponsive)
        }
        let token = ledger.store(StoredWalk(root: root, bound: walked.bound))
        return Walked(root: root, walk: token, unresponsive: walked.unresponsive)
    }

    private func copiedNode(at path: [Int], in root: AccessibilityElement) -> AccessibilityElement? {
        var node = root
        for index in path {
            guard node.children.indices.contains(index) else {
                return nil
            }
            node = node.children[index]
        }
        return node
    }

    /// The same accessibility element keeps one token across reads.
    /// `CFEqual` is the identity. A new wrapper for that control does not count
    /// as entering a different field.
    private func focusIdentity(_ element: AXUIElement) -> String {
        identities.token(for: element)
    }
}

extension AXSystemReader {
    /// Copies the tree under one element with the given options. The
    /// benchmark uses it to time one window with different settings.
    static func copyTree(_ element: AXUIElement, options: TreeWalkOptions) -> WalkedTree<LiveNode> {
        AccessibilityTreeWalker.walk(
            root: LiveNode(element: element),
            source: LiveNodeSource(slowMilliseconds: Double(messagingTimeoutSeconds) * 1_000 * 0.8),
            options: options
        )
    }
}

/// A live element handed between the threads of one walk. The element is
/// only ever passed to accessibility calls, which may be made from any thread.
struct LiveNode: @unchecked Sendable {
    let element: AXUIElement
}

private struct StoredWalk {
    var root: AccessibilityElement
    var bound: [BoundNode<LiveNode>]
}

/// Walks that have been copied and not yet adopted. A scan makes at most a
/// few before it adopts one, so the oldest are dropped past a small count.
private final class WalkLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var next = 0
    private var walks: [(token: Int, walk: StoredWalk)] = []

    func store(_ walk: StoredWalk) -> Int {
        lock.lock()
        defer { lock.unlock() }
        next += 1
        walks.append((next, walk))
        if walks.count > 12 {
            walks.removeFirst(walks.count - 12)
        }
        return next
    }

    func take(_ token: Int?) -> StoredWalk? {
        lock.lock()
        defer { lock.unlock() }
        let found = walks.first(where: { $0.token == token })?.walk
        walks.removeAll()
        return found
    }
}

private final class MessagingTimeout: @unchecked Sendable {
    private let lock = NSLock()
    private var applied = false

    /// Set on the system-wide element, the timeout applies to every
    /// accessibility call this process makes.
    func applyOnce(seconds: Float) {
        lock.lock()
        let needed = !applied
        applied = true
        lock.unlock()
        guard needed else {
            return
        }
        let error = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), seconds)
        ModeTrace.noteLine("ax-timeout seconds=\(seconds) set=\(error == .success ? 1 : 0)")
    }
}

/// Attribute lists for the one round trip a node costs. The order is the
/// order of the values that come back.
private enum LiveAttributes {
    static let walk: [String] = [
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXPositionAttribute,
        kAXSizeAttribute,
        "AXEditable",
        kAXEnabledAttribute,
        kAXVerticalScrollBarAttribute,
        kAXHorizontalScrollBarAttribute,
        kAXChildrenAttribute,
    ]
    /// The focused element is classified, not walked. Its children are not
    /// asked for: a focused web area would send thousands.
    static let focus: [String] = Array(walk.dropLast())
    static let scrollBar: [String] = [kAXValueAttribute, kAXMinValueAttribute, kAXMaxValueAttribute]

    static let role = 0
    static let subrole = 1
    static let position = 2
    static let size = 3
    static let editable = 4
    static let enabled = 5
    static let verticalBar = 6
    static let horizontalBar = 7
    static let children = 8
}

private struct LiveNodeSource: AccessibilityNodeSource {
    let slowMilliseconds: Double

    func read(_ node: LiveNode) -> NodeReadResult<LiveNode> {
        readLiveNode(node.element, attributes: LiveAttributes.walk, slowMilliseconds: slowMilliseconds)
    }
}

/// One node in one round trip, plus one for its action names when the role
/// can be clicked, plus one per scroll bar it has.
///
/// `cannotComplete` after a wait close to the messaging timeout means the
/// app is not answering. The same error straight away means this one
/// element could not be reached, and only it is left out. Any other
/// failure of the batched call falls back to asking attribute by attribute.
private func readLiveNode(
    _ element: AXUIElement,
    attributes: [String],
    slowMilliseconds: Double
) -> NodeReadResult<LiveNode> {
    let watch = TraceStopwatch()
    var copied: CFArray?
    let error = AXUIElementCopyMultipleAttributeValues(
        element,
        attributes as CFArray,
        AXCopyMultipleAttributeOptions(rawValue: 0),
        &copied
    )
    switch error {
    case .success:
        break
    case .invalidUIElement:
        return .gone
    case .cannotComplete:
        return watch.milliseconds >= slowMilliseconds ? .unresponsive : .gone
    default:
        return .node(NodeReading(
            element: attributeByAttribute(element),
            children: attributes.count > LiveAttributes.children
                ? copyChildren(element).map { LiveNode(element: $0) }
                : []
        ))
    }
    let values = (copied as? [AnyObject]) ?? []
    func value(_ index: Int) -> AnyObject? {
        guard values.indices.contains(index) else {
            return nil
        }
        let raw = values[index]
        if CFGetTypeID(raw) == AXValueGetTypeID(),
           AXValueGetType(unsafeDowncast(raw, to: AXValue.self)) == .axError {
            return nil
        }
        return raw
    }
    let role = value(LiveAttributes.role) as? String
    var frame: ElementFrame?
    if let position = value(LiveAttributes.position).flatMap({ copyPoint($0) }),
       let size = value(LiveAttributes.size).flatMap({ copySize($0) }) {
        frame = ElementFrame(
            x: Double(position.x),
            y: Double(position.y),
            width: Double(size.width),
            height: Double(size.height)
        )
    }
    let copiedElement = AccessibilityElement(
        role: role,
        subrole: value(LiveAttributes.subrole) as? String,
        actions: FocusClassification.wantsActionNames(role: role) ? copyActions(element) : [],
        editableAttribute: value(LiveAttributes.editable).flatMap { booleanValue($0) },
        frame: frame,
        verticalScroll: value(LiveAttributes.verticalBar).flatMap { readScrollBar($0) },
        horizontalScroll: value(LiveAttributes.horizontalBar).flatMap { readScrollBar($0) },
        isEnabled: value(LiveAttributes.enabled).flatMap { booleanValue($0) }
    )
    let children = (value(LiveAttributes.children) as? [AXUIElement]) ?? []
    return .node(NodeReading(element: copiedElement, children: children.map { LiveNode(element: $0) }))
}

private func booleanValue(_ value: AnyObject) -> Bool? {
    guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
        return nil
    }
    return (value as? NSNumber)?.boolValue
}

/// Value, minimum and maximum of one scroll bar in one round trip.
private func readScrollBar(_ value: AnyObject) -> ScrollBarReading? {
    guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    let bar = unsafeBitCast(value, to: AXUIElement.self)
    var copied: CFArray?
    let error = AXUIElementCopyMultipleAttributeValues(
        bar,
        LiveAttributes.scrollBar as CFArray,
        AXCopyMultipleAttributeOptions(rawValue: 0),
        &copied
    )
    guard error == .success, let numbers = copied as? [AnyObject], numbers.count == 3 else {
        return nil
    }
    guard let current = (numbers[0] as? NSNumber)?.doubleValue,
          let minimum = (numbers[1] as? NSNumber)?.doubleValue,
          let maximum = (numbers[2] as? NSNumber)?.doubleValue
    else {
        return nil
    }
    return ScrollBarReading(value: current, minimum: minimum, maximum: maximum, contentLength: nil)
}

/// The reading used before the batched call, kept for an element that
/// refuses the batched call.
private func attributeByAttribute(_ element: AXUIElement) -> AccessibilityElement {
    let role = copyString(element, kAXRoleAttribute)
    return AccessibilityElement(
        role: role,
        subrole: copyString(element, kAXSubroleAttribute),
        actions: copyActions(element),
        editableAttribute: copyBool(element, "AXEditable" as CFString),
        frame: copyFrame(element),
        verticalScroll: copyScrollBar(element, kAXVerticalScrollBarAttribute),
        horizontalScroll: copyScrollBar(element, kAXHorizontalScrollBarAttribute),
        isEnabled: copyBool(element, kAXEnabledAttribute as CFString)
    )
}

/// Observes focused-element changes and application activation.
/// The callback only invokes the handler. It does not walk the window.
public final class AXFocusSignal: FocusChangeSignaling, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private let box = AXSignalBox()
    #if canImport(AppKit)
    private var activationToken: NSObjectProtocol?
    #endif

    public init() {}

    public func start(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
        box.handler = { [weak self] in
            self?.emit()
        }
        bindFrontmost()
        observeActivation()
    }

    public func stop() {
        lock.lock()
        handler = nil
        lock.unlock()
        box.handler = nil
        removeObserver()
        #if canImport(AppKit)
        if let activationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(activationToken)
            self.activationToken = nil
        }
        #endif
    }

    deinit {
        stop()
    }

    private func emit() {
        lock.lock()
        let current = handler
        lock.unlock()
        current?()
    }

    private func bindFrontmost() {
        guard AXIsProcessTrusted() else {
            return
        }
        var pid = frontmostPID()
        if pid == 0 {
            let system = AXUIElementCreateSystemWide()
            if let application = copyElement(system, kAXFocusedApplicationAttribute) {
                var focusedPID: pid_t = 0
                if AXUIElementGetPid(application, &focusedPID) == .success {
                    pid = focusedPID
                }
            }
        }
        bind(pid: pid)
    }

    private func bind(pid: pid_t) {
        if pid == 0 {
            return
        }
        lock.lock()
        let same = pid == observedPID && observer != nil
        lock.unlock()
        if same {
            return
        }
        removeObserver()
        var created: AXObserver?
        guard AXObserverCreate(pid, axFocusNotification, &created) == .success, let created else {
            return
        }
        let application = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(box).toOpaque()
        let names = [
            kAXFocusedUIElementChangedNotification,
            kAXFocusedWindowChangedNotification,
            kAXApplicationActivatedNotification,
        ]
        for name in names {
            _ = AXObserverAddNotification(created, application, name as CFString, refcon)
        }
        let loopSource = AXObserverGetRunLoopSource(created)
        let loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, loopSource, .commonModes)
        lock.lock()
        observer = created
        observedPID = pid
        source = loopSource
        runLoop = loop
        lock.unlock()
    }

    private func removeObserver() {
        lock.lock()
        let currentSource = source
        let currentLoop = runLoop
        observer = nil
        observedPID = 0
        source = nil
        runLoop = nil
        lock.unlock()
        if let currentSource, let currentLoop {
            CFRunLoopRemoveSource(currentLoop, currentSource, .commonModes)
        }
    }

    private func observeActivation() {
        #if canImport(AppKit)
        if activationToken != nil {
            return
        }
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.bindFrontmost()
            self?.emit()
        }
        #endif
    }

    private func frontmostPID() -> pid_t {
        #if canImport(AppKit)
        return NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        #else
        return 0
        #endif
    }
}

/// Turns on the accessibility tree for one process.
/// Each attribute is written at most once. Manual accessibility is the first
/// request. Enhanced mode is written later when the caller still has an empty
/// tree: a successful manual write does not fill Qt's tree by itself.
/// Enhanced mode can slow window animation, so it is not set on the first try.
private final class AccessibilityExpander: @unchecked Sendable {
    private let lock = NSLock()
    private var manual = Set<pid_t>()
    private var enhanced = Set<pid_t>()

    /// Manual accessibility is tried on the first request. Enhanced mode is
    /// separate: a successful manual write does not mean Qt filled the tree,
    /// so a later request with `allowEnhanced` still sets
    /// `AXEnhancedUserInterface` once. Each attribute is written at most once
    /// per process.
    func expand(_ application: AXUIElement, pid: pid_t, allowEnhanced: Bool) -> AccessibilityTreeExpansion {
        lock.lock()
        let needsManual = manual.insert(pid).inserted
        lock.unlock()
        var wroteManual = false
        if needsManual, setBool(application, "AXManualAccessibility", true) {
            wroteManual = true
        }
        guard allowEnhanced else {
            return wroteManual ? .manual : .unchanged
        }
        lock.lock()
        let needsEnhanced = enhanced.insert(pid).inserted
        lock.unlock()
        guard needsEnhanced else {
            return wroteManual ? .manual : .unchanged
        }
        if setBool(application, "AXEnhancedUserInterface", true) {
            return .enhanced
        }
        return wroteManual ? .manual : .unchanged
    }

    private func setBool(_ element: AXUIElement, _ name: String, _ value: Bool) -> Bool {
        let error = AXUIElementSetAttributeValue(element, name as CFString, NSNumber(value: value))
        return error == .success
    }
}

/// Remembers accessibility elements this process has already named.
/// `CFEqual` is the identity. A new wrapper for the same control keeps the token.
private final class FocusIdentityVault: @unchecked Sendable {
    private let lock = NSLock()
    private var known: [(element: AXUIElement, token: String)] = []
    private var next = 0

    func token(for element: AXUIElement) -> String {
        lock.lock()
        defer { lock.unlock() }
        for entry in known where sameElement(entry.element, element) {
            return entry.token
        }
        next += 1
        let token = "ax-\(next)"
        known.append((element, token))
        if known.count > 32 {
            known.removeFirst(known.count - 32)
        }
        return token
    }

    private func sameElement(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        CFEqual(unsafeBitCast(lhs, to: CFTypeRef.self), unsafeBitCast(rhs, to: CFTypeRef.self))
    }
}

private final class AXSignalBox {
    var handler: (@Sendable () -> Void)?
}

private func axFocusNotification(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    _ = observer
    _ = element
    _ = notification
    guard let refcon else {
        return
    }
    let box = Unmanaged<AXSignalBox>.fromOpaque(refcon).takeUnretainedValue()
    box.handler?()
}

private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let value = copyAttribute(element, attribute as CFString) else {
        return nil
    }
    guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return unsafeBitCast(value, to: AXUIElement.self)
}

private func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard error == .success else {
        return nil
    }
    return value
}

private func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
    guard let value = copyAttribute(element, attribute as CFString) else {
        return nil
    }
    return value as? String
}

private func copyScrollBar(_ element: AXUIElement, _ attribute: String) -> ScrollBarReading? {
    guard let bar = copyElement(element, attribute) else {
        return nil
    }
    guard let value = copyDouble(bar, kAXValueAttribute as CFString),
          let minimum = copyDouble(bar, kAXMinValueAttribute as CFString),
          let maximum = copyDouble(bar, kAXMaxValueAttribute as CFString)
    else {
        return nil
    }
    return ScrollBarReading(value: value, minimum: minimum, maximum: maximum, contentLength: nil)
}

private func copyDouble(_ element: AXUIElement, _ attribute: CFString) -> Double? {
    guard let value = copyAttribute(element, attribute) else {
        return nil
    }
    guard let number = value as? NSNumber else {
        return nil
    }
    return number.doubleValue
}

private func copyBool(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
    guard let value = copyAttribute(element, attribute) else {
        return nil
    }
    return value as? Bool
}

private func copyActions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success, let names else {
        return []
    }
    return names as? [String] ?? []
}

private func sameAXElement(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
    CFEqual(unsafeBitCast(lhs, to: CFTypeRef.self), unsafeBitCast(rhs, to: CFTypeRef.self))
}

private func copyElements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
    guard let value = copyAttribute(element, attribute as CFString) else {
        return []
    }
    return value as? [AXUIElement] ?? []
}

private func copyChildren(_ element: AXUIElement) -> [AXUIElement] {
    guard let value = copyAttribute(element, kAXChildrenAttribute as CFString) else {
        return []
    }
    return value as? [AXUIElement] ?? []
}

private func copyFrame(_ element: AXUIElement) -> ElementFrame? {
    guard let position = copyAttribute(element, kAXPositionAttribute as CFString),
          let size = copyAttribute(element, kAXSizeAttribute as CFString),
          let point = copyPoint(position),
          let cgSize = copySize(size)
    else {
        return nil
    }
    return ElementFrame(
        x: Double(point.x),
        y: Double(point.y),
        width: Double(cgSize.width),
        height: Double(cgSize.height)
    )
}

private func copyPoint(_ value: CFTypeRef) -> CGPoint? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgPoint else {
        return nil
    }
    var point = CGPoint.zero
    let copied = withUnsafeMutablePointer(to: &point) { pointer in
        AXValueGetValue(axValue, .cgPoint, UnsafeMutableRawPointer(pointer))
    }
    return copied ? point : nil
}

private func copySize(_ value: CFTypeRef) -> CGSize? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgSize else {
        return nil
    }
    var size = CGSize.zero
    let copied = withUnsafeMutablePointer(to: &size) { pointer in
        AXValueGetValue(axValue, .cgSize, UnsafeMutableRawPointer(pointer))
    }
    return copied ? size : nil
}

private func bundleIdentifier(pid: pid_t) -> String? {
    #if canImport(AppKit)
    guard let identifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
        return nil
    }
    return identifier.isEmpty ? nil : identifier
    #else
    _ = pid
    return nil
    #endif
}

private func frontmostBundleIdentifier() -> String? {
    #if canImport(AppKit)
    guard let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
        return nil
    }
    return identifier.isEmpty ? nil : identifier
    #else
    return nil
    #endif
}
#endif

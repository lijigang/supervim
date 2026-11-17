#if canImport(ApplicationServices)
import ApplicationServices
import CoreFoundation
import Foundation

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
/// The focused-element read copies one element. Child walks happen only in the
/// window read, which callers use off the key hook.
public final class AXSystemReader: AccessibilityReading, @unchecked Sendable {
    private let identities = FocusIdentityVault()
    private let expansions = AccessibilityExpander()
    private let scrollElements: AXElementStore?

    public init(scrollElements: AXElementStore? = nil) {
        self.scrollElements = scrollElements
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
        let system = AXUIElementCreateSystemWide()
        guard let element = copyElement(system, kAXFocusedUIElementAttribute) else {
            return .unavailable
        }
        return .value(snapshot(of: element, identify: true))
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
        let choices = liveChoices(maxNodes: maxNodes, maxDepth: maxDepth)
        let limits = TreeWalkLimits(maxNodes: maxNodes, maxDepth: maxDepth)
        if let choice = choices.first(where: { $0.found && ($0.element?.children.isEmpty == false) }),
           let element = choice.element {
            rememberScrollElements(choice.live, limits: limits)
            return .value(element)
        }
        if let application = liveApplication(maxNodes: maxNodes, maxDepth: maxDepth),
           let element = application.element,
           !element.children.isEmpty {
            rememberScrollElements(application.live, limits: limits)
            return .value(element)
        }
        if let choice = choices.first(where: \.found), let element = choice.element {
            rememberScrollElements(choice.live, limits: limits)
            return .value(element)
        }
        scrollElements?.reset()
        return .unavailable
    }

    public func readWindowChoices(maxNodes: Int, maxDepth: Int) -> [AccessibilityWindowChoice] {
        liveChoices(maxNodes: maxNodes, maxDepth: maxDepth).map { choice in
            AccessibilityWindowChoice(source: choice.source, found: choice.found, element: choice.element)
        }
    }

    public func readApplicationElement(maxNodes: Int, maxDepth: Int) -> AccessibilityElement? {
        liveApplication(maxNodes: maxNodes, maxDepth: maxDepth)?.element
    }

    private struct LiveChoice {
        var source: String
        var found: Bool
        var element: AccessibilityElement?
        var live: AXUIElement?
    }

    private func liveChoices(maxNodes: Int, maxDepth: Int) -> [LiveChoice] {
        guard AXIsProcessTrusted() else {
            return [LiveChoice(source: "focused", found: false, element: nil, live: nil)]
        }
        let system = AXUIElementCreateSystemWide()
        guard let application = copyElement(system, kAXFocusedApplicationAttribute) else {
            return [LiveChoice(source: "focused", found: false, element: nil, live: nil)]
        }
        let limits = TreeWalkLimits(maxNodes: maxNodes, maxDepth: maxDepth)
        var choices: [LiveChoice] = []
        var seen: [AXUIElement] = []
        func append(_ element: AXUIElement?, source: String, recordMiss: Bool) {
            guard let element else {
                if recordMiss {
                    choices.append(LiveChoice(source: source, found: false, element: nil, live: nil))
                }
                return
            }
            if seen.contains(where: { sameAXElement($0, element) }) {
                return
            }
            seen.append(element)
            choices.append(LiveChoice(
                source: source,
                found: true,
                element: copiedTree(element, limits: limits),
                live: element
            ))
        }
        append(copyElement(application, kAXFocusedWindowAttribute), source: "focused", recordMiss: true)
        append(copyElement(application, kAXMainWindowAttribute), source: "main", recordMiss: true)
        let windows = copyElements(application, kAXWindowsAttribute)
        if windows.isEmpty {
            choices.append(LiveChoice(source: "windows", found: false, element: nil, live: nil))
        } else {
            for window in windows.prefix(8) {
                append(window, source: "windows", recordMiss: false)
            }
        }
        return choices
    }

    private func liveApplication(maxNodes: Int, maxDepth: Int) -> LiveChoice? {
        guard AXIsProcessTrusted() else {
            return nil
        }
        let system = AXUIElementCreateSystemWide()
        guard let application = copyElement(system, kAXFocusedApplicationAttribute) else {
            return nil
        }
        return LiveChoice(
            source: "application",
            found: true,
            element: copiedTree(application, limits: TreeWalkLimits(maxNodes: maxNodes, maxDepth: maxDepth)),
            live: application
        )
    }

    /// Binds the chosen window under the same path keys the catalog will use.
    /// The copy used for the catalog is separate; this walk only keeps elements.
    private func rememberScrollElements(_ element: AXUIElement?, limits: TreeWalkLimits) {
        guard let scrollElements else {
            return
        }
        scrollElements.reset()
        guard let element else {
            return
        }
        var remaining = limits.maxNodes
        _ = snapshotTree(element, path: [], depth: 0, limits: limits, remaining: &remaining, bind: true)
    }

    private func copiedTree(_ element: AXUIElement, limits: TreeWalkLimits) -> AccessibilityElement {
        var remaining = limits.maxNodes
        return snapshotTree(element, path: [], depth: 0, limits: limits, remaining: &remaining, bind: false)
    }

    private func snapshot(of element: AXUIElement, identify: Bool = false) -> AccessibilityElement {
        let role = copyString(element, kAXRoleAttribute)
        let subrole = copyString(element, kAXSubroleAttribute)
        return AccessibilityElement(
            role: role,
            subrole: subrole,
            actions: copyActions(element),
            editableAttribute: copyBool(element, "AXEditable" as CFString),
            identity: identify ? focusIdentity(element) : nil,
            frame: copyFrame(element),
            verticalScroll: copyScrollBar(element, kAXVerticalScrollBarAttribute),
            horizontalScroll: copyScrollBar(element, kAXHorizontalScrollBarAttribute)
        )
    }

    /// The same accessibility element keeps one token across reads.
    /// `CFEqual` is the identity. A new wrapper for that control does not count
    /// as entering a different field.
    private func focusIdentity(_ element: AXUIElement) -> String {
        identities.token(for: element)
    }

    private func snapshotTree(
        _ element: AXUIElement,
        path: [Int],
        depth: Int,
        limits: TreeWalkLimits,
        remaining: inout Int,
        bind: Bool
    ) -> AccessibilityElement {
        remaining -= 1
        if bind {
            scrollElements?.bind(element, identifier: ScrollTargetIdentity.identifier(path: path))
        }
        var node = snapshot(of: element)
        let children = copyChildren(element)
        if children.isEmpty {
            return node
        }
        if remaining <= 0 || depth >= limits.maxDepth {
            node.childrenTruncated = true
            return node
        }
        var copied: [AccessibilityElement] = []
        for (index, child) in children.enumerated() {
            if remaining <= 0 {
                node.childrenTruncated = true
                break
            }
            copied.append(snapshotTree(
                child,
                path: path + [index],
                depth: depth + 1,
                limits: limits,
                remaining: &remaining,
                bind: bind
            ))
        }
        if copied.count < children.count {
            node.childrenTruncated = true
        }
        node.children = copied
        return node
    }
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

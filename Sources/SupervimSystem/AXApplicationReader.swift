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

    public init() {}

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
        guard AXIsProcessTrusted() else {
            return .unavailable
        }
        let system = AXUIElementCreateSystemWide()
        guard let application = copyElement(system, kAXFocusedApplicationAttribute) else {
            return .unavailable
        }
        let window = copyElement(application, kAXFocusedWindowAttribute)
            ?? copyElement(application, kAXMainWindowAttribute)
        guard let window else {
            return .unavailable
        }
        let limits = TreeWalkLimits(maxNodes: maxNodes, maxDepth: maxDepth)
        var remaining = limits.maxNodes
        return .value(snapshotTree(window, depth: 0, limits: limits, remaining: &remaining))
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
        depth: Int,
        limits: TreeWalkLimits,
        remaining: inout Int
    ) -> AccessibilityElement {
        remaining -= 1
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
        for child in children {
            if remaining <= 0 {
                node.childrenTruncated = true
                break
            }
            copied.append(snapshotTree(child, depth: depth + 1, limits: limits, remaining: &remaining))
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

/// Turns on the accessibility tree for one process, at most once.
/// Manual accessibility is tried first. Enhanced mode is the fallback, and
/// only when the caller says the scan was empty. Enhanced mode can slow
/// window animation, so a process whose manual request succeeded is left alone.
private final class AccessibilityExpander: @unchecked Sendable {
    private let lock = NSLock()
    private var manual = Set<pid_t>()
    private var enhanced = Set<pid_t>()
    private var manualSucceeded = Set<pid_t>()

    func expand(_ application: AXUIElement, pid: pid_t, allowEnhanced: Bool) -> AccessibilityTreeExpansion {
        lock.lock()
        let needsManual = manual.insert(pid).inserted
        let manualAlreadyWorked = manualSucceeded.contains(pid)
        lock.unlock()
        if needsManual {
            if setBool(application, "AXManualAccessibility", true) {
                lock.lock()
                manualSucceeded.insert(pid)
                lock.unlock()
                return .manual
            }
        } else if manualAlreadyWorked {
            return .unchanged
        }
        guard allowEnhanced else {
            return .unchanged
        }
        lock.lock()
        let needsEnhanced = enhanced.insert(pid).inserted
        lock.unlock()
        guard needsEnhanced else {
            return .unchanged
        }
        if setBool(application, "AXEnhancedUserInterface", true) {
            return .enhanced
        }
        return .unchanged
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

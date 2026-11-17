#if canImport(ApplicationServices)
import ApplicationServices
import Foundation

/// Focuses an accessibility element that was bound off the key hook.
///
/// The element is stored by the child-index path from the window root.
/// A missing path returns false. This does not search the tree and does not
/// focus a different control. Whether `AXFocusedUIElement` on the system-wide
/// element moves a real Safari or Notes field is unverified.
public final class AXInputFocuser: InputFocusing, @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [FocusPath: AXUIElement] = [:]

    public init() {}

    public func bind(_ element: AXUIElement, path: [Int]) {
        lock.lock()
        elements[FocusPath(path)] = element
        lock.unlock()
    }

    public func focusInput(path: [Int]) -> Bool {
        lock.lock()
        let element = elements[FocusPath(path)]
        lock.unlock()
        guard let element else {
            return false
        }
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return false
        }
        let system = AXUIElementCreateSystemWide()
        let error = AXUIElementSetAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            element
        )
        return error == .success
    }
}

private struct FocusPath: Hashable {
    var path: [Int]

    init(_ path: [Int]) {
        self.path = path
    }
}
#endif

#if canImport(ApplicationServices)
import ApplicationServices
import Foundation

/// Focuses an accessibility element that was bound off the key hook.
///
/// The element is stored by the child-index path from the window root.
/// A missing path returns false. This does not search the tree and does not
/// focus a different control. Focus is `AXFocused = true` on the element.
/// Whether that moves a real Safari or Notes field is unverified. The session
/// clicks the field when this returns false.
public final class AXInputFocuser: InputFocusing, @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [FocusPath: AXUIElement] = [:]

    public init() {}

    public func resetInputs() {
        lock.lock()
        elements.removeAll()
        lock.unlock()
    }

    /// Keeps the first element for a path. The focused window is copied first.
    public func bindInput(_ element: AXUIElement, path: [Int]) {
        let key = FocusPath(path)
        lock.lock()
        if elements[key] == nil {
            elements[key] = element
        }
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
        let error = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
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

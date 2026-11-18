import Foundation

/// One app the system reported as activated.
public struct ActivatedApp: Equatable, Sendable {
    public var processIdentifier: Int32
    public var bundleIdentifier: String
    public var name: String

    public init(processIdentifier: Int32, bundleIdentifier: String, name: String) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// The last app that came to the front and was not Supervim.
///
/// Opening the settings window makes Supervim the frontmost app, so the app
/// in front at the time of a click is always Supervim. The settings window
/// asks this instead.
///
/// Supervim is recognised by process identifier and by bundle identifier.
/// The first covers a build run without a bundle, the second covers another
/// running copy. An app without a bundle identifier cannot be excluded and
/// does not replace the remembered app.
public final class LastExternalApp: FrontmostBundleProviding, @unchecked Sendable {
    private let ownProcessIdentifier: Int32
    private let ownBundleIdentifier: String
    private let lock = NSLock()
    private var remembered: ActivatedApp?

    public init(ownProcessIdentifier: Int32, ownBundleIdentifier: String) {
        self.ownProcessIdentifier = ownProcessIdentifier
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    public func noteActivated(_ app: ActivatedApp) {
        let bundle = app.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if app.processIdentifier == ownProcessIdentifier
            || bundle.isEmpty
            || BundleIdentity.matches(bundle, ownBundleIdentifier) {
            return
        }
        let kept = ActivatedApp(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: bundle,
            name: app.name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        lock.lock()
        remembered = kept
        lock.unlock()
    }

    /// Empty until another app has been in front.
    public func frontmostBundleIdentifier() -> String {
        current()?.bundleIdentifier ?? ""
    }

    public func frontmostApplicationName() -> String {
        current()?.name ?? ""
    }

    private func current() -> ActivatedApp? {
        lock.lock()
        defer { lock.unlock() }
        return remembered
    }
}

enum BundleIdentity {
    /// Case is ignored, so Supervim's identifier in another case is still
    /// Supervim. An empty identifier matches nothing.
    static func matches(_ left: String, _ right: String) -> Bool {
        let first = left.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let second = right.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !first.isEmpty && first == second
    }
}

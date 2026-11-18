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

public final class LastExternalApp: FrontmostBundleProviding, @unchecked Sendable {
    private var remembered: ActivatedApp?

    public init(ownProcessIdentifier: Int32, ownBundleIdentifier: String) {
        _ = ownProcessIdentifier
        _ = ownBundleIdentifier
    }

    public func noteActivated(_ app: ActivatedApp) {
        remembered = app
    }

    public func frontmostBundleIdentifier() -> String {
        remembered?.bundleIdentifier ?? ""
    }

    public func frontmostApplicationName() -> String {
        remembered?.name ?? ""
    }
}

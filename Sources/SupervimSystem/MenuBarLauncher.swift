import SupervimCore

public enum HostPlatform: Equatable, Sendable {
    case macOS
    case other
}

public enum MenuBarPreflight: Equatable, Sendable {
    case readyForMenuBarLaunch
    case unsupportedPlatform
}

public enum MenuBarPreflightError: Error, Equatable, Sendable {
    case invalidManifest(ManifestValidationError)
}

public enum MenuBarLauncher {
    public static func currentHost() -> HostPlatform {
        #if os(macOS)
        return .macOS
        #else
        return .other
        #endif
    }

    /// Validates the menu-bar manifest before considering the host.
    /// An invalid manifest is rejected on every host, including non-macOS.
    public static func preflight(
        _ manifest: MenuBarManifest,
        host: HostPlatform = currentHost()
    ) throws -> MenuBarPreflight {
        do {
            try MenuBarManifestValidator.validate(manifest)
        } catch let error as ManifestValidationError {
            throw MenuBarPreflightError.invalidManifest(error)
        }
        switch host {
        case .macOS:
            return .readyForMenuBarLaunch
        case .other:
            return .unsupportedPlatform
        }
    }
}

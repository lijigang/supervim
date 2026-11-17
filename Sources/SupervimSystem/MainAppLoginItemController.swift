import Foundation
import SupervimCore

#if canImport(ServiceManagement)
import ServiceManagement

/// Live login item for this app bundle.
///
/// Calls `SMAppService.mainApp`. An ad-hoc or unsigned bundle that is not in
/// Applications often comes back as `notFound`, and `register()` can throw.
/// The caller is expected to be on the main actor. This type does not prompt.
public struct MainAppLoginItemController: LoginItemControlling {
    public init() {}

    public func currentState() -> LoginItemState {
        MainActor.assumeIsolated {
            Self.map(SMAppService.mainApp.status)
        }
    }

    public func register() throws {
        try MainActor.assumeIsolated {
            try SMAppService.mainApp.register()
        }
    }

    public func unregister() throws {
        try MainActor.assumeIsolated {
            try SMAppService.mainApp.unregister()
        }
    }

    private static func map(_ status: SMAppService.Status) -> LoginItemState {
        switch status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }
}
#endif

import Foundation

/// Registration state reported by the injected login-item service.
///
/// `requiresApproval` means the item is already submitted and the user still
/// has to allow it in System Settings. `notFound` means the system cannot see
/// this bundle, which is common before the app is in Applications.
public enum LoginItemState: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

/// Registers or unregisters the main app. Tests supply a stand-in.
public protocol LoginItemControlling: Sendable {
    func currentState() -> LoginItemState
    func register() throws
    func unregister() throws
}

public enum LoginItemApplyResult: Equatable, Sendable {
    case registered
    case unregistered
    case unchanged
    case failed(String)
}

/// Applies the saved launch-at-login preference.
///
/// A true preference registers. A false preference unregisters. A state that
/// already matches the preference does not call the service again. A thrown
/// error becomes `failureNotice` and does not claim the item changed.
/// This value does not read Settings and does not touch the system service.
public struct LoginItemRegistration: Sendable {
    public static let failureNotice = "Could not update the login item. Move Supervim into Applications and open it from there."

    private let controller: any LoginItemControlling

    public init(controller: any LoginItemControlling) {
        self.controller = controller
    }

    public func apply(launchAtLogin: Bool) -> LoginItemApplyResult {
        let state = controller.currentState()
        if launchAtLogin {
            switch state {
            case .enabled, .requiresApproval:
                return .unchanged
            case .notRegistered, .notFound:
                do {
                    try controller.register()
                    return .registered
                } catch {
                    return .failed(Self.failureNotice)
                }
            }
        }
        switch state {
        case .notRegistered, .notFound:
            return .unchanged
        case .enabled, .requiresApproval:
            do {
                try controller.unregister()
                return .unregistered
            } catch {
                return .failed(Self.failureNotice)
            }
        }
    }
}

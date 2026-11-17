import Foundation
import SupervimCore

#if canImport(ApplicationServices) && canImport(CoreGraphics) && canImport(IOKit)
import ApplicationServices
import CoreGraphics
import IOKit.hid

/// Live Accessibility and Input Monitoring probes.
///
/// A grant does not guarantee this process can use it without quitting and
/// reopening. That behavior is not verified. Rebuilding an unsigned binary
/// can also require the user to allow Supervim again. This type does not prompt.
public final class SystemPermissionStatus: PermissionStatusProviding, @unchecked Sendable {
    public init() {}

    public func currentPermissionStatus() -> PermissionStatus {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let listenEvent = ListenEventAccess.resolve(
            hidGranted: access == kIOHIDAccessTypeGranted,
            hidDenied: access == kIOHIDAccessTypeDenied,
            hidUnknown: access == kIOHIDAccessTypeUnknown,
            preflightGranted: CGPreflightListenEventAccess()
        )
        return PermissionStatus(
            accessibilityTrusted: AXIsProcessTrusted(),
            listenEvent: listenEvent,
            screenRecordingGranted: CGPreflightScreenCaptureAccess()
        )
    }
}
#endif

#if canImport(AppKit)
import AppKit

public final class WorkspacePrivacyPaneOpener: PrivacyPaneOpening, @unchecked Sendable {
    public init() {}

    public func openPrivacyPane(destination: String) -> Bool {
        guard let url = URL(string: destination), !destination.isEmpty else {
            return false
        }
        return MainActor.assumeIsolated {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif

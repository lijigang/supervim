#if canImport(AppKit)
import AppKit
import SupervimCore

/// Tells `LastExternalApp` each time an app comes to the front.
///
/// `onChange` runs on the thread that posted the notification, after the
/// tracker has been told. The workspace posts on the main thread.
public final class WorkspaceActivationFeed: NSObject {
    private let tracker: LastExternalApp
    private let onChange: @Sendable () -> Void

    public init(
        tracker: LastExternalApp,
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onChange: @escaping @Sendable () -> Void = {}
    ) {
        self.tracker = tracker
        self.onChange = onChange
        super.init()
        center.addObserver(
            self,
            selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    /// Reads the app in front now. Used at launch, before any notification,
    /// and when the settings window is about to open.
    public func noteFrontmostNow() {
        if let application = NSWorkspace.shared.frontmostApplication {
            note(application)
        }
    }

    private func note(_ application: NSRunningApplication) {
        tracker.noteActivated(
            ActivatedApp(
                processIdentifier: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier ?? "",
                name: application.localizedName ?? ""
            )
        )
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        note(application)
        onChange()
    }
}
#endif

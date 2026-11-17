#if canImport(AppKit)
import AppKit
import SupervimCore
import SupervimSystem

/// AppKit shell for `PermissionGuidance`. Titles and links come from the guide.
@MainActor
final class PermissionGuidancePanel: NSWindowController, NSWindowDelegate {
    var onClose: (@MainActor () -> Void)?

    private let chrome: PermissionGuideChrome

    init(
        onOpen: @escaping @MainActor (PermissionKind) -> Void,
        onCheckAgain: @escaping @MainActor () -> Void
    ) {
        let chrome = PermissionGuideChrome(onOpen: onOpen, onCheckAgain: onCheckAgain)
        self.chrome = chrome
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = chrome.root
        window.contentMinSize = NSSize(width: 460, height: 360)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func render(_ guidance: PermissionGuidance) {
        window?.title = guidance.title
        chrome.render(guidance)
        chrome.primaryButton?.title = guidance.checkAgainTitle
        if let button = chrome.primaryButton {
            window?.defaultButtonCell = button.cell as? NSButtonCell
        }
    }

    func present() {
        showWindow(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        onClose?()
    }

}
#else
import Foundation

enum PermissionGuidancePanelUnavailable {}
#endif

#if canImport(AppKit)
import AppKit
import SupervimCore

/// AppKit shell for `PermissionGuidance`. Titles and links come from the guide.
@MainActor
final class PermissionGuidancePanel: NSWindowController, NSWindowDelegate {
    var onClose: (@MainActor () -> Void)?

    private let onOpen: @MainActor (PermissionKind) -> Void
    private let onCheckAgain: @MainActor () -> Void
    private let bodyField = NSTextField(wrappingLabelWithString: "")
    private let noticeField = NSTextField(wrappingLabelWithString: "")
    private let linkStack = NSStackView()
    private let checkAgainButton = NSButton(title: "", target: nil, action: nil)
    private var linkKinds: [PermissionKind] = []

    init(
        onOpen: @escaping @MainActor (PermissionKind) -> Void,
        onCheckAgain: @escaping @MainActor () -> Void
    ) {
        self.onOpen = onOpen
        self.onCheckAgain = onCheckAgain
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        checkAgainButton.target = self
        checkAgainButton.action = #selector(checkAgainClicked(_:))
        installContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func render(_ guidance: PermissionGuidance) {
        window?.title = guidance.title
        bodyField.stringValue = guidance.body
        noticeField.stringValue = guidance.notice
        checkAgainButton.title = guidance.checkAgainTitle
        rebuildLinks(guidance.links)
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

    private func installContent() {
        guard let content = window?.contentView else {
            return
        }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        bodyField.maximumNumberOfLines = 0
        noticeField.maximumNumberOfLines = 2
        linkStack.orientation = .vertical
        linkStack.alignment = .leading
        linkStack.spacing = 4
        stack.addArrangedSubview(bodyField)
        stack.addArrangedSubview(linkStack)
        stack.addArrangedSubview(checkAgainButton)
        stack.addArrangedSubview(noticeField)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
        ])
    }

    private func rebuildLinks(_ links: [PrivacyPaneLink]) {
        for view in linkStack.arrangedSubviews {
            linkStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        linkKinds = links.map(\.kind)
        for (index, link) in links.enumerated() {
            let button = NSButton(title: link.title, target: self, action: #selector(linkClicked(_:)))
            button.tag = index
            linkStack.addArrangedSubview(button)
        }
    }

    @objc private func linkClicked(_ sender: NSButton) {
        guard linkKinds.indices.contains(sender.tag) else {
            return
        }
        onOpen(linkKinds[sender.tag])
    }

    @objc private func checkAgainClicked(_ sender: NSButton) {
        _ = sender
        onCheckAgain()
    }
}
#else
import Foundation

enum PermissionGuidancePanelUnavailable {}
#endif

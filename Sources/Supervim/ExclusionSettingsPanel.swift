#if canImport(AppKit)
import AppKit
import SupervimCore

@MainActor
protocol ExclusionSettingsPanelDelegate: AnyObject {
    func exclusionPanelDidAddFrontmost()
    func exclusionPanelDidRemove(_ bundleIdentifier: String)
    func exclusionPanelDidSetLaunchAtLogin(_ enabled: Bool)
    func exclusionPanelDidClose()
}

/// AppKit shell for `ExclusionEditor`. Titles and enablement come from the editor.
@MainActor
final class ExclusionSettingsPanel: NSWindowController, NSWindowDelegate {
    private weak var panelDelegate: ExclusionSettingsPanelDelegate?
    private let rows = NSStackView()
    private let noticeField = NSTextField(wrappingLabelWithString: "")
    private let launchButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let addButton = NSButton(title: "", target: nil, action: nil)
    private var displayedBundles: [String] = []

    init(delegate: ExclusionSettingsPanelDelegate) {
        self.panelDelegate = delegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        launchButton.target = self
        launchButton.action = #selector(launchClicked(_:))
        addButton.target = self
        addButton.action = #selector(addClicked(_:))
        installContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func render(_ editor: ExclusionEditor) {
        window?.title = editor.windowTitle
        addButton.title = editor.addButtonTitle
        addButton.isEnabled = editor.canAddFrontmost
        launchButton.title = editor.launchAtLoginTitle
        launchButton.state = editor.launchAtLogin ? .on : .off
        noticeField.stringValue = editor.notice
        displayedBundles = editor.bundleIdentifiers
        rebuildRows(editor)
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

    func windowWillClose(_ notification: Notification) {
        _ = notification
        panelDelegate?.exclusionPanelDidClose()
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
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 4
        noticeField.maximumNumberOfLines = 3
        stack.addArrangedSubview(launchButton)
        stack.addArrangedSubview(rows)
        stack.addArrangedSubview(addButton)
        stack.addArrangedSubview(noticeField)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
        ])
    }

    private func rebuildRows(_ editor: ExclusionEditor) {
        for view in rows.arrangedSubviews {
            rows.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, bundle) in editor.bundleIdentifiers.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            let label = NSTextField(labelWithString: bundle)
            label.lineBreakMode = .byTruncatingTail
            let remove = NSButton(title: editor.removeButtonTitle, target: self, action: #selector(removeClicked(_:)))
            remove.tag = index
            remove.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(label)
            row.addArrangedSubview(remove)
            rows.addArrangedSubview(row)
        }
    }

    @objc private func addClicked(_ sender: NSButton) {
        _ = sender
        panelDelegate?.exclusionPanelDidAddFrontmost()
    }

    @objc private func removeClicked(_ sender: NSButton) {
        guard displayedBundles.indices.contains(sender.tag) else {
            return
        }
        panelDelegate?.exclusionPanelDidRemove(displayedBundles[sender.tag])
    }

    @objc private func launchClicked(_ sender: NSButton) {
        panelDelegate?.exclusionPanelDidSetLaunchAtLogin(sender.state == .on)
    }
}
#else
import Foundation

enum ExclusionSettingsPanelUnavailable {}
#endif

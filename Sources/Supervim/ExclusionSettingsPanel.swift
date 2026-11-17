#if canImport(AppKit)
import AppKit
import SupervimCore
import SupervimSystem

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

/// Menu-bar status, pause, and settings. When both permissions are granted,
/// the shared interpreter starts the scanner and then the event tap.
@MainActor
final class MenuBarApplication: NSObject, NSApplicationDelegate, ExclusionSettingsPanelDelegate {
    private var statusItem: NSStatusItem?
    private var settingsPanel: ExclusionSettingsPanel?
    private let session: MenuBarController<SystemKeyClock>
    private let hookObserver: HookMenuObserver
    private let runtime: SupervimRuntime

    override init() {
        let session = MenuBarApplication.makeSession(frontmost: WorkspaceFrontmost())
        let observer = HookMenuObserver()
        self.session = session
        self.hookObserver = observer
        self.runtime = MenuHookAssembly.make(decider: session.keyDecider, observer: observer)
        super.init()
        observer.onEvent = { [weak self] in
            Task { @MainActor in
                self?.refreshAfterHook()
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        _ = runtime.start()
        installMenu()
    }

    private func refreshAfterHook() {
        try? session.noteExternalDecision()
        installMenu()
        settingsPanel?.render(session.editor())
    }

    func exclusionPanelDidAddFrontmost() {
        _ = try? session.addFrontmost()
        refreshSettings()
    }

    func exclusionPanelDidRemove(_ bundleIdentifier: String) {
        _ = try? session.removeExcluded(bundleIdentifier: bundleIdentifier)
        refreshSettings()
    }

    func exclusionPanelDidSetLaunchAtLogin(_ enabled: Bool) {
        _ = try? session.setLaunchAtLogin(enabled)
        refreshSettings()
    }

    func exclusionPanelDidClose() {
        _ = session.closeSettings()
    }

    private func installMenu() {
        let menu = NSMenu()
        let snapshot = session.snapshot()
        statusItem?.button?.title = snapshot.statusTitle
        for command in snapshot.commands {
            if command.kind == .separator {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(
                title: command.title,
                action: #selector(menuClicked(_:)),
                keyEquivalent: command.kind == .quit ? "q" : ""
            )
            item.target = self
            item.isEnabled = command.enabled
            item.tag = tag(for: command.kind)
            menu.addItem(item)
        }
        statusItem?.menu = menu
    }

    @objc private func menuClicked(_ sender: NSMenuItem) {
        guard let kind = kind(for: sender.tag) else {
            return
        }
        switch try? session.perform(kind) {
        case .terminate:
            NSApplication.shared.terminate(sender)
        case .show, nil:
            installMenu()
            if kind == .settings {
                showSettings()
            }
        }
    }

    private func showSettings() {
        let panel = settingsPanel ?? ExclusionSettingsPanel(delegate: self)
        settingsPanel = panel
        panel.render(session.editor())
        panel.present()
    }

    private func refreshSettings() {
        installMenu()
        settingsPanel?.render(session.editor())
    }

    private func tag(for kind: MenuCommandKind) -> Int {
        switch kind {
        case .pause:
            return 1
        case .resume:
            return 2
        case .settings:
            return 3
        case .quit:
            return 4
        case .separator:
            return 0
        }
    }

    private func kind(for tag: Int) -> MenuCommandKind? {
        switch tag {
        case 1:
            return .pause
        case 2:
            return .resume
        case 3:
            return .settings
        case 4:
            return .quit
        default:
            return nil
        }
    }

    private static func makeSession(frontmost: WorkspaceFrontmost) -> MenuBarController<SystemKeyClock> {
        let clock = SystemKeyClock()
        if let defaults = UserDefaults(suiteName: UserDefaultsSettingsStore.applicationSuiteName) {
            let repository = SettingsRepository(store: UserDefaultsSettingsStore(defaults: defaults))
            if let session = try? MenuBarController(
                repository: repository,
                clock: clock,
                frontmost: frontmost
            ) {
                return session
            }
        }
        let repository = SettingsRepository(store: InMemorySettingsStore())
        do {
            return try MenuBarController(repository: repository, clock: clock, frontmost: frontmost)
        } catch {
            preconditionFailure("in-memory settings must load")
        }
    }
}

final class HookMenuObserver: RuntimeObserving, @unchecked Sendable {
    var onEvent: (@Sendable () -> Void)?

    func runtimeDidHandle(_ decision: EventDecision?) {
        _ = decision
        onEvent?()
    }
}

struct WorkspaceFrontmost: FrontmostBundleProviding {
    func frontmostBundleIdentifier() -> String {
        MainActor.assumeIsolated {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        }
    }
}
#else
import Foundation

enum ExclusionSettingsPanelUnavailable {}
#endif

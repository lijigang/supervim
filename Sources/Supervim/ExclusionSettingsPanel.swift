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
    private let chrome: SettingsChrome

    init(delegate: ExclusionSettingsPanelDelegate) {
        self.panelDelegate = delegate
        let chrome = SettingsChrome(
            onAdd: { [weak delegate] in
                delegate?.exclusionPanelDidAddFrontmost()
            },
            onRemove: { [weak delegate] bundle in
                delegate?.exclusionPanelDidRemove(bundle)
            },
            onLaunchAtLogin: { [weak delegate] enabled in
                delegate?.exclusionPanelDidSetLaunchAtLogin(enabled)
            }
        )
        self.chrome = chrome
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = chrome.root
        window.contentMinSize = NSSize(width: 420, height: 280)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func render(_ editor: ExclusionEditor) {
        window?.title = editor.windowTitle
        chrome.render(presentedCopy(editor))
    }

    /// Threads the editor's button titles through this target. `SettingsChrome` draws them.
    private func presentedCopy(_ editor: ExclusionEditor) -> ExclusionEditor {
        ExclusionEditor(
            bundleIdentifiers: editor.bundleIdentifiers,
            launchAtLogin: editor.launchAtLogin,
            frontmostBundleIdentifier: editor.frontmostBundleIdentifier,
            canAddFrontmost: editor.canAddFrontmost,
            notice: editor.notice,
            isVisible: editor.isVisible,
            windowTitle: editor.windowTitle,
            addButtonTitle: editor.addButtonTitle,
            removeButtonTitle: editor.removeButtonTitle,
            launchAtLoginTitle: editor.launchAtLoginTitle
        )
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
}

/// Menu-bar status, pause, settings, and the permission guide.
/// When both permissions are granted, the shared interpreter starts the scanner and then the event tap.
@MainActor
final class MenuBarApplication: NSObject, NSApplicationDelegate, ExclusionSettingsPanelDelegate {
    private var statusItem: NSStatusItem?
    private var settingsPanel: ExclusionSettingsPanel?
    private var permissionPanel: PermissionGuidancePanel?
    private var permissionWindowOpen = false
    private var latestGuidance: PermissionGuidance?
    private let session: MenuBarController<SystemKeyClock>
    private let misses: HintMissBanner
    private let hookObserver: HookMenuObserver
    private let runtime: SupervimRuntime
    private let launchGate: PermissionLaunchGate
    private let loginItems: LoginItemRegistration
    private var activations: WorkspaceActivationFeed?
    private var lastDrawnMenu: DrawnMenu?

    override init() {
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        let externalApp = LastExternalApp(
            ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            ownBundleIdentifier: ownBundle
        )
        let session = MenuBarApplication.makeSession(frontmost: externalApp, ownBundleIdentifier: ownBundle)
        let observer = HookMenuObserver()
        let misses = HintMissBanner()
        self.session = session
        self.misses = misses
        self.hookObserver = observer
        self.runtime = MenuHookAssembly.make(decider: session.keyDecider, observer: observer, misses: misses)
        self.launchGate = PermissionLaunchGate(
            guide: PermissionGuide(
                status: SystemPermissionStatus(),
                opener: WorkspacePrivacyPaneOpener()
            )
        )
        self.loginItems = LoginItemRegistration(controller: MainAppLoginItemController())
        super.init()
        observer.onEvent = { [weak self] in
            Task { @MainActor in
                observer.delivered()
                self?.refreshAfterHook()
            }
        }
        let feed = WorkspaceActivationFeed(tracker: externalApp, onChange: { [weak self] in
            Task { @MainActor in
                self?.externalAppChanged()
            }
        })
        feed.noteFrontmostNow()
        activations = feed
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        synchronizeLoginItem()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        syncPermissions(showWhenNeeded: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        _ = notification
        syncPermissions(showWhenNeeded: false)
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
        synchronizeLoginItem()
        refreshSettings()
    }

    private func synchronizeLoginItem() {
        let enabled = session.editor().launchAtLogin
        if case .failed(let message) = loginItems.apply(launchAtLogin: enabled) {
            _ = session.reportNotice(message)
        }
    }

    func exclusionPanelDidClose() {
        _ = session.closeSettings()
    }

    private func installMenu() {
        if let latestGuidance {
            installMenu(guidance: latestGuidance)
        } else {
            apply(launchGate.refresh(), showWhenNeeded: false)
        }
    }

    private func installMenu(guidance: PermissionGuidance) {
        let snapshot = session.snapshot()
        let title = misses.title(fallback: snapshot.statusTitle)
        let permissionsTitle = guidance.isVisible ? guidance.menuTitle : nil
        let drawn = DrawnMenu(snapshot: snapshot, title: title, permissionsTitle: permissionsTitle)
        if drawn == lastDrawnMenu, statusItem?.menu != nil {
            return
        }
        lastDrawnMenu = drawn
        let menu = NSMenu()
        let button = statusItem?.button
        let glyph = MenuBarGlyphImage.image(for: MenuBarGlyphKind(statusTitle: snapshot.statusTitle))
        button?.image = glyph
        button?.imagePosition = title == snapshot.statusTitle ? .imageOnly : .imageLeading
        button?.title = title == snapshot.statusTitle ? "" : title
        button?.toolTip = snapshot.statusTitle
        button?.setAccessibilityLabel(title == snapshot.statusTitle ? snapshot.statusTitle : "\(snapshot.statusTitle), \(title)")
        statusItem?.length = title == snapshot.statusTitle ? NSStatusItem.squareLength : NSStatusItem.variableLength
        if title != snapshot.statusTitle {
            TransientNoticePanel.shared.show(title)
            DispatchQueue.main.asyncAfter(deadline: .now() + misses.duration + 0.05) { [weak self] in
                self?.installMenu()
            }
        } else {
            TransientNoticePanel.shared.hide()
        }
        for item in MenuChrome.items(snapshot: snapshot, permissionsTitle: permissionsTitle) {
            if item.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let menuItem = NSMenuItem(
                title: item.title,
                action: item.isPermissions ? #selector(permissionsClicked(_:)) : #selector(menuClicked(_:)),
                keyEquivalent: item.keyEquivalent
            )
            menuItem.target = self
            menuItem.isEnabled = item.enabled
            if let kind = item.kind {
                menuItem.tag = tag(for: kind)
            }
            if let symbol = item.symbolName,
               let image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.title) {
                menuItem.image = image
            }
            menu.addItem(menuItem)
        }
        statusItem?.menu = menu
    }

    private func syncPermissions(showWhenNeeded: Bool) {
        apply(launchGate.refresh(), showWhenNeeded: showWhenNeeded)
    }

    private func showPermissions(_ guidance: PermissionGuidance) {
        let panel = permissionPanel ?? makePermissionPanel()
        permissionPanel = panel
        panel.render(guidance)
        panel.present()
        permissionWindowOpen = true
    }

    private func makePermissionPanel() -> PermissionGuidancePanel {
        let panel = PermissionGuidancePanel(
            onOpen: { [weak self] kind in
                self?.openedPermission(kind)
            },
            onCheckAgain: { [weak self] in
                self?.syncPermissions(showWhenNeeded: true)
            }
        )
        panel.onClose = { [weak self] in
            self?.permissionWindowOpen = false
        }
        return panel
    }

    private func openedPermission(_ kind: PermissionKind) {
        apply(launchGate.openLink(kind), showWhenNeeded: true)
    }

    private func apply(_ step: PermissionLaunchStep, showWhenNeeded: Bool) {
        let guidance = step.guidance
        latestGuidance = guidance
        installMenu(guidance: guidance)
        if guidance.isVisible {
            if showWhenNeeded || permissionWindowOpen {
                showPermissions(guidance)
            }
            return
        }
        if permissionWindowOpen {
            permissionPanel?.dismiss()
            permissionWindowOpen = false
        }
        guard step.shouldStartRuntime else {
            return
        }
        let started = runtime.start()
        if started.monitoredFocus || started.installedHook {
            launchGate.noteRuntimeStarted()
        }
    }

    @objc private func permissionsClicked(_ sender: NSMenuItem) {
        _ = sender
        syncPermissions(showWhenNeeded: true)
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
        // Presenting the window makes Supervim the frontmost app. The app to
        // add is the one in front until then.
        activations?.noteFrontmostNow()
        let panel = settingsPanel ?? ExclusionSettingsPanel(delegate: self)
        settingsPanel = panel
        panel.render(session.editor())
        panel.present()
    }

    private func refreshSettings() {
        installMenu()
        settingsPanel?.render(session.editor())
    }

    /// The add button names the app it would add, so it is redrawn when
    /// another app comes to the front.
    private func externalAppChanged() {
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

    private static func makeSession(
        frontmost: LastExternalApp,
        ownBundleIdentifier: String
    ) -> MenuBarController<SystemKeyClock> {
        let clock = SystemKeyClock()
        if let defaults = UserDefaults(suiteName: UserDefaultsSettingsStore.applicationSuiteName) {
            let repository = SettingsRepository(store: UserDefaultsSettingsStore(defaults: defaults))
            if let session = try? MenuBarController(
                repository: repository,
                clock: clock,
                frontmost: frontmost,
                ownBundleIdentifier: ownBundleIdentifier
            ) {
                return session
            }
        }
        let repository = SettingsRepository(store: InMemorySettingsStore())
        do {
            return try MenuBarController(
                repository: repository,
                clock: clock,
                frontmost: frontmost,
                ownBundleIdentifier: ownBundleIdentifier
            )
        } catch {
            preconditionFailure("in-memory settings must load")
        }
    }
}

/// What the status item and its menu were last built from. The menu is
/// rebuilt only when one of these changes.
private struct DrawnMenu: Equatable {
    var snapshot: MenuBarSnapshot
    var title: String
    var permissionsTitle: String?
}

/// Passes hook events to the main thread. Events that arrive while one is
/// already waiting there are folded into it: the menu shows the current
/// state, not a history.
final class HookMenuObserver: RuntimeObserving, @unchecked Sendable {
    var onEvent: (@Sendable () -> Void)?
    private let lock = NSLock()
    private var waiting = false

    func runtimeDidHandle(_ decision: EventDecision?) {
        _ = decision
        lock.lock()
        let already = waiting
        waiting = true
        lock.unlock()
        if !already {
            onEvent?()
        }
    }

    /// The main thread has picked the event up. The next one is queued again.
    func delivered() {
        lock.lock()
        waiting = false
        lock.unlock()
    }
}
#else
import Foundation

enum ExclusionSettingsPanelUnavailable {}
#endif

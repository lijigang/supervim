#if canImport(AppKit)
import AppKit
import SupervimCore
import SupervimSystem

/// Menu-bar status, pause, and settings. The event tap stays uninstalled:
/// the focus scanner is not wired, and swallowing commands here would drop keys.
@MainActor
final class MenuBarApplication: NSObject, NSApplicationDelegate, ExclusionSettingsPanelDelegate {
    private var statusItem: NSStatusItem?
    private var settingsPanel: ExclusionSettingsPanel?
    private let session: MenuBarController<SystemKeyClock>

    override init() {
        session = MenuBarApplication.makeSession(frontmost: WorkspaceFrontmost())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        installMenu()
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

struct WorkspaceFrontmost: FrontmostBundleProviding {
    func frontmostBundleIdentifier() -> String {
        MainActor.assumeIsolated {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        }
    }
}

@main
enum SupervimMain {
    static func main() {
        MainActor.assumeIsolated {
            let application = NSApplication.shared
            let delegate = MenuBarApplication()
            application.delegate = delegate
            _ = application.setActivationPolicy(.accessory)
            application.run()
        }
    }
}
#else
import Foundation

@main
enum SupervimMain {
    static func main() {
        let message = "Supervim is a macOS 13+ menu-bar app and cannot run on this platform.\n"
        FileHandle.standardError.write(Data(message.utf8))
        exit(1)
    }
}
#endif

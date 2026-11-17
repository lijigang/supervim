#if os(macOS)
import AppKit

/// Menu-bar placeholder for Task 1. No mode display, pause, or settings — those are later tasks.
@MainActor
final class MenuBarPlaceholder: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Supervim"
        let menu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit Supervim",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(sender)
    }
}

@main
enum SupervimMain {
    static func main() {
        MainActor.assumeIsolated {
            let application = NSApplication.shared
            let delegate = MenuBarPlaceholder()
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

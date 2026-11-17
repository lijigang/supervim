#if os(macOS)
import AppKit
import SupervimCore
import SupervimSystem

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

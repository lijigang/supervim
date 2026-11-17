import Foundation

#if canImport(AppKit)
import AppKit
import SupervimSystem

@main
enum UISnapshotsMain {
    static func main() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let path = CommandLine.arguments.dropFirst().first ?? "build/ui-snapshots"
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            do {
                let written = try ChromeSnapshot.writeAll(to: directory)
                for url in written {
                    FileHandle.standardOutput.write(Data("\(url.path)\n".utf8))
                }
            } catch {
                let message = "UI snapshots failed: \(error)\n"
                FileHandle.standardError.write(Data(message.utf8))
                exit(1)
            }
        }
    }
}
#else
@main
enum UISnapshotsMain {
    static func main() {
        FileHandle.standardError.write(Data("UI snapshots require macOS.\n".utf8))
        exit(1)
    }
}
#endif

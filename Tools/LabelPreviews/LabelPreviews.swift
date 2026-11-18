import Foundation

#if canImport(AppKit)
import AppKit

@main
enum LabelPreviewsMain {
    static func main() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let path = CommandLine.arguments.dropFirst().first ?? "build/label-previews"
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            do {
                let written = try LabelPreviewRunner.writeAll(to: directory)
                for url in written {
                    FileHandle.standardOutput.write(Data("\(url.path)\n".utf8))
                }
            } catch {
                let message = "Label previews failed: \(error)\n"
                FileHandle.standardError.write(Data(message.utf8))
                exit(1)
            }
        }
    }
}
#else
@main
enum LabelPreviewsMain {
    static func main() {
        FileHandle.standardError.write(Data("Label previews require macOS.\n".utf8))
        exit(1)
    }
}
#endif

import Foundation

func repoRoot(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

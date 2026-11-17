import Foundation

/// Optional trace of mode changes for a device that is stuck in Insert.
///
/// Off unless one of these is set:
/// `SUPERVIM_LOG=1`, or `defaults write com.lijigang.supervim SupervimDebugLog -bool true`.
/// Lines go to `~/Library/Logs/Supervim.log`.
public enum ModeTrace {
    public static let defaultsKey = "SupervimDebugLog"
    public static let environmentKey = "SUPERVIM_LOG"

    public static func note(
        from: SupervimMode,
        to: SupervimMode,
        role: String?,
        subrole: String?,
        trigger: String,
        identity: String?
    ) {
        guard from != to, enabled() else {
            return
        }
        let line = formatLine(
            timestamp: timestamp(),
            from: from,
            to: to,
            role: role,
            subrole: subrole,
            trigger: trigger,
            identity: identity
        )
        append(line)
    }

    public static func formatLine(
        timestamp: String,
        from: SupervimMode,
        to: SupervimMode,
        role: String?,
        subrole: String?,
        trigger: String,
        identity: String?
    ) -> String {
        let roleText = shown(role)
        let subroleText = shown(subrole)
        let identityText = shown(identity)
        return "\(timestamp) \(modeName(from)) -> \(modeName(to)) trigger=\(trigger) role=\(roleText) subrole=\(subroleText) identity=\(identityText)"
    }

    private static func shown(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "-"
        }
        return value
    }

    public static func noteHintScan(
        bundleIdentifier: String,
        visited: Int,
        hits: Int,
        milliseconds: Int,
        expansion: String
    ) {
        guard enabled() else {
            return
        }
        append(formatHintScan(
            bundleIdentifier: bundleIdentifier,
            visited: visited,
            hits: hits,
            milliseconds: milliseconds,
            expansion: expansion
        ))
    }

    public static func formatHintScan(
        bundleIdentifier: String,
        visited: Int,
        hits: Int,
        milliseconds: Int,
        expansion: String
    ) -> String {
        let bundle = bundleIdentifier.isEmpty ? "-" : bundleIdentifier
        return "hint-scan bundle=\(bundle) visited=\(visited) hits=\(hits) ms=\(milliseconds) expansion=\(expansion)"
    }

    public static func formatHintPlace(screen: DisplayFrame, index: Int) -> String {
        "hint-screen index=\(index) x=\(screen.x) y=\(screen.y) w=\(screen.width) h=\(screen.height) scale=\(screen.backingScale)"
    }

    public static func formatHintLabel(
        index: Int,
        ax: HintRect,
        ns: HintRect
    ) -> String {
        "hint-label index=\(index) ax=\(ax.x),\(ax.y),\(ax.width),\(ax.height) ns=\(ns.x),\(ns.y),\(ns.width),\(ns.height)"
    }

    public static func formatHintClick(index: Int, method: String, x: Double, y: Double) -> String {
        "hint-click index=\(index) method=\(method) ax=\(x),\(y)"
    }

    public static func noteLine(_ line: String) {
        guard enabled() else {
            return
        }
        append(line)
    }

    public static func logFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Supervim.log", isDirectory: false)
    }

    private static func enabled() -> Bool {
        let value = ProcessInfo.processInfo.environment[environmentKey]?.lowercased()
        if value == "1" || value == "true" || value == "yes" {
            return true
        }
        if UserDefaults.standard.bool(forKey: defaultsKey) {
            return true
        }
        return UserDefaults(suiteName: "com.lijigang.supervim")?.bool(forKey: defaultsKey) ?? false
    }

    private static func modeName(_ mode: SupervimMode) -> String {
        switch mode {
        case .normal:
            return "normal"
        case .insert:
            return "insert"
        case .hint:
            return "hint"
        case .paused:
            return "paused"
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static let writeLock = NSLock()

    private static func append(_ line: String) {
        let url = logFileURL()
        let directory = url.deletingLastPathComponent()
        writeLock.lock()
        defer { writeLock.unlock() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = Data((line + "\n").utf8)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            return
        }
    }
}

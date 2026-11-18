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
        window: String,
        found: Int,
        visited: Int,
        hits: Int,
        milliseconds: Int,
        expansion: String,
        retry: String
    ) {
        guard enabled() else {
            return
        }
        append(formatHintScan(
            bundleIdentifier: bundleIdentifier,
            window: window,
            found: found,
            visited: visited,
            hits: hits,
            milliseconds: milliseconds,
            expansion: expansion,
            retry: retry
        ))
    }

    public static func formatHintScan(
        bundleIdentifier: String,
        window: String,
        found: Int,
        visited: Int,
        hits: Int,
        milliseconds: Int,
        expansion: String,
        retry: String
    ) -> String {
        let bundle = bundleIdentifier.isEmpty ? "-" : bundleIdentifier
        let windowName = window.isEmpty ? "missing" : window
        return "hint-scan bundle=\(bundle) window=\(windowName) found=\(found) visited=\(visited) hits=\(hits) ms=\(milliseconds) expansion=\(expansion) retry=\(retry)"
    }

    public static func formatHintWindow(source: String, found: Int, children: Int) -> String {
        "hint-window source=\(source) found=\(found) children=\(children)"
    }

    public static func formatHintKey(
        key: String,
        mode: String,
        why: String,
        delivery: String,
        bundle: String,
        role: String?,
        subrole: String?,
        identity: String?,
        held: String
    ) -> String {
        let bundleText = bundle.isEmpty ? "-" : bundle
        return "hint-key key=\(key) mode=\(mode) why=\(why) delivery=\(delivery) bundle=\(bundleText) role=\(shown(role)) subrole=\(shown(subrole)) identity=\(shown(identity)) held=\(held)"
    }

    public static func formatTapDisabled(reason: String, reenabled: Bool) -> String {
        "tap-disabled reason=\(reason) reenabled=\(reenabled ? 1 : 0)"
    }

    public static func formatHintBanner(reason: String) -> String {
        "hint-banner reason=\(reason)"
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

    public static func formatHintPanel(screen: Int, scale: Double, frame: HintRect) -> String {
        "hint-panel screen=\(screen) scale=\(scale) x=\(frame.x) y=\(frame.y) w=\(frame.width) h=\(frame.height)"
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

    /// A line with how long one stage took. `fields` keep the order given.
    public static func formatTiming(
        stage: String,
        milliseconds: Double,
        fields: [(String, String)]
    ) -> String {
        let shownMilliseconds = milliseconds.isFinite ? String(format: "%.1f", milliseconds) : "-"
        var line = "timing stage=\(stage) ms=\(shownMilliseconds)"
        for (name, value) in fields {
            line += " \(name)=\(value)"
        }
        return line
    }

    public static func noteTiming(stage: String, milliseconds: Double, fields: [(String, String)] = []) {
        guard enabled() else {
            return
        }
        append(formatTiming(stage: stage, milliseconds: milliseconds, fields: fields))
    }

    /// True when a line would be kept. Callers use it to skip building a
    /// line that costs something to format.
    public static var isEnabled: Bool {
        enabled()
    }

    /// Runs `body` with every line collected in memory instead of the file.
    /// Tests use it. The previous destination is restored afterwards.
    public static func capture(_ body: () -> Void) -> [String] {
        let collector = TraceCollector()
        let previous = state.swapCollector(collector)
        body()
        _ = state.swapCollector(previous)
        return collector.lines
    }

    /// Waits for queued lines to reach the file.
    public static func flush() {
        state.writer.flush()
    }

    private static let state = TraceState()

    private static func enabled() -> Bool {
        if state.collector() != nil {
            return true
        }
        return state.toggle.isOn()
    }

    fileprivate static func probe() -> Bool {
        let value = ProcessInfo.processInfo.environment[environmentKey]?.lowercased()
        if value == "1" || value == "true" || value == "yes" {
            return true
        }
        if UserDefaults.standard.bool(forKey: defaultsKey) {
            return true
        }
        return state.suite?.bool(forKey: defaultsKey) ?? false
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

    private static func append(_ line: String) {
        if let collector = state.collector() {
            collector.add(line)
            return
        }
        state.writer.write(stamped(line))
    }

    /// Mode lines already start with a date. Every other line gets the
    /// wall-clock time to the millisecond, so stages can be lined up.
    private static func stamped(_ line: String) -> String {
        if let first = line.unicodeScalars.first, first.value >= 0x30, first.value <= 0x39 {
            return line
        }
        return "\(clockText()) \(line)"
    }

    private static func clockText() -> String {
        let now = Date().timeIntervalSince1970
        let whole = Int(now)
        let milliseconds = Int((now - Double(whole)) * 1000)
        let seconds = whole % 60
        let minutes = (whole / 60) % 60
        let hours = (whole / 3600) % 24
        return String(format: "%02d:%02d:%02d.%03dZ", hours, minutes, seconds, milliseconds)
    }
}

/// Monotonic stopwatch for the debug log. Not a wall clock.
public struct TraceStopwatch: Sendable {
    private let started: UInt64

    public init() {
        started = DispatchTime.now().uptimeNanoseconds
    }

    public var milliseconds: Double {
        Double(DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000
    }
}

/// Remembers whether the log is on, and asks again only after the interval.
/// The probe reads the environment and two defaults domains; the event hook
/// calls `isOn` for every key and must not pay for that each time.
public final class TraceSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private let interval: Int64
    private let now: @Sendable () -> Int64
    private let probe: @Sendable () -> Bool
    private var checkedAt: Int64?
    private var value = false

    public init(
        intervalMilliseconds: Int64,
        now: @escaping @Sendable () -> Int64,
        probe: @escaping @Sendable () -> Bool
    ) {
        interval = intervalMilliseconds
        self.now = now
        self.probe = probe
    }

    public func isOn() -> Bool {
        let current = now()
        lock.lock()
        if let checkedAt, current - checkedAt < interval, current >= checkedAt {
            let known = value
            lock.unlock()
            return known
        }
        checkedAt = current
        lock.unlock()
        let fresh = probe()
        lock.lock()
        value = fresh
        lock.unlock()
        return fresh
    }
}

/// Appends lines on its own queue through one open handle.
/// `write` returns as soon as the line is queued.
public final class TraceFileWriter: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "com.lijigang.supervim.trace", qos: .utility)
    private var handle: FileHandle?
    private var failed = false
    private var openCount = 0

    public init(url: URL) {
        self.url = url
    }

    /// How many times the file was opened. Read after `flush`.
    public var opens: Int {
        queue.sync { openCount }
    }

    public func write(_ line: String) {
        queue.async { [self] in
            guard let handle = opened() else {
                return
            }
            do {
                try handle.write(contentsOf: Data((line + "\n").utf8))
            } catch {
                self.handle = nil
            }
        }
    }

    public func flush() {
        queue.sync {}
    }

    /// Parks the queue until `gate` is signalled. Tests use it to show that
    /// `write` does not wait for the disk.
    func hold(_ gate: DispatchSemaphore) {
        queue.async {
            gate.wait()
        }
    }

    private func opened() -> FileHandle? {
        if let handle {
            return handle
        }
        if failed {
            return nil
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url)
            }
            let made = try FileHandle(forWritingTo: url)
            try made.seekToEnd()
            handle = made
            openCount += 1
            return made
        } catch {
            failed = true
            return nil
        }
    }
}

private final class TraceCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [String] = []

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return kept
    }

    func add(_ line: String) {
        lock.lock()
        kept.append(line)
        lock.unlock()
    }
}

private final class TraceState: @unchecked Sendable {
    let suite = UserDefaults(suiteName: "com.lijigang.supervim")
    let writer = TraceFileWriter(url: ModeTrace.logFileURL())
    let toggle = TraceSwitch(
        intervalMilliseconds: 2_000,
        now: { Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) },
        probe: { ModeTrace.probe() }
    )
    private let lock = NSLock()
    private var active: TraceCollector?

    func collector() -> TraceCollector? {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func swapCollector(_ next: TraceCollector?) -> TraceCollector? {
        lock.lock()
        defer { lock.unlock() }
        let previous = active
        active = next
        return previous
    }
}

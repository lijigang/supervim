import Foundation

/// Frontmost bundle id supplied by the app. An empty string means it could not be named.
public protocol FrontmostBundleProviding: Sendable {
    func frontmostBundleIdentifier() -> String
}

public enum MenuCommandKind: Equatable, Sendable {
    case pause
    case resume
    case settings
    case quit
    case separator
}

public struct MenuCommand: Equatable, Sendable {
    public var kind: MenuCommandKind
    public var title: String
    public var enabled: Bool

    public init(kind: MenuCommandKind, title: String, enabled: Bool) {
        self.kind = kind
        self.title = title
        self.enabled = enabled
    }
}

public struct MenuBarSnapshot: Equatable, Sendable {
    public var statusTitle: String
    public var commands: [MenuCommand]

    public init(statusTitle: String, commands: [MenuCommand]) {
        self.statusTitle = statusTitle
        self.commands = commands
    }
}

/// Exclusion list and the launch-at-login preference. The key timeout stays in Settings.
public struct ExclusionEditor: Equatable, Sendable {
    public var bundleIdentifiers: [String]
    public var launchAtLogin: Bool
    public var frontmostBundleIdentifier: String
    public var canAddFrontmost: Bool
    public var notice: String
    public var isVisible: Bool
    public var windowTitle: String
    public var addButtonTitle: String
    public var removeButtonTitle: String
    public var launchAtLoginTitle: String

    public init(
        bundleIdentifiers: [String],
        launchAtLogin: Bool,
        frontmostBundleIdentifier: String,
        canAddFrontmost: Bool,
        notice: String,
        isVisible: Bool,
        windowTitle: String,
        addButtonTitle: String,
        removeButtonTitle: String,
        launchAtLoginTitle: String
    ) {
        self.bundleIdentifiers = bundleIdentifiers
        self.launchAtLogin = launchAtLogin
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.canAddFrontmost = canAddFrontmost
        self.notice = notice
        self.isVisible = isVisible
        self.windowTitle = windowTitle
        self.addButtonTitle = addButtonTitle
        self.removeButtonTitle = removeButtonTitle
        self.launchAtLoginTitle = launchAtLoginTitle
    }
}

public enum MenuBarEffect: Equatable, Sendable {
    case show(MenuBarSnapshot)
    case terminate
}

/// Status title, menu enablement, pause persistence, and the exclusion editor.
///
/// Hint is shown as Normal. The spec names only Normal, Insert, and Paused.
/// Launch-at-login is stored and not registered. This type does not install an event tap.
public final class MenuBarController<Clock: KeyTimeSource>: @unchecked Sendable {
    private let repository: SettingsRepository
    private let interpreter: EventInterpreter<Clock>
    private let frontmost: any FrontmostBundleProviding
    private var lastSaved: Settings
    private var settingsVisible = false
    private var notice = ""

    public init(
        repository: SettingsRepository,
        clock: Clock,
        frontmost: any FrontmostBundleProviding
    ) throws {
        let loaded = try repository.load()
        self.repository = repository
        self.frontmost = frontmost
        self.interpreter = EventInterpreter(settings: loaded, clock: clock, cache: .unknown)
        self.lastSaved = loaded
    }

    /// The hook and the menu use this same interpreter.
    public var keyDecider: EventInterpreter<Clock> {
        interpreter
    }

    /// Saves a pause or resume that the hook applied to `keyDecider`.
    public func noteExternalDecision() throws {
        try persistIfChanged()
    }

    public func snapshot() -> MenuBarSnapshot {
        let title = Self.statusTitle(for: interpreter.mode)
        let paused = interpreter.mode == .paused
        return MenuBarSnapshot(
            statusTitle: title,
            commands: [
                MenuCommand(kind: .pause, title: "Pause", enabled: !paused),
                MenuCommand(kind: .resume, title: "Resume", enabled: paused),
                MenuCommand(kind: .settings, title: "Settings", enabled: true),
                MenuCommand(kind: .separator, title: "", enabled: false),
                MenuCommand(kind: .quit, title: "Quit Supervim", enabled: true),
            ]
        )
    }

    public func editor() -> ExclusionEditor {
        let settings = interpreter.settingsSnapshot()
        let raw = frontmost.frontmostBundleIdentifier()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let canAdd = !trimmed.isEmpty && !settings.isExcluded(bundleIdentifier: trimmed)
        return ExclusionEditor(
            bundleIdentifiers: settings.excludedBundleIdentifiers,
            launchAtLogin: settings.launchAtLogin,
            frontmostBundleIdentifier: raw,
            canAddFrontmost: canAdd,
            notice: notice,
            isVisible: settingsVisible,
            windowTitle: "Settings",
            addButtonTitle: "Add Frontmost App",
            removeButtonTitle: "Remove",
            launchAtLoginTitle: "Launch at Login"
        )
    }

    public func perform(_ kind: MenuCommandKind) throws -> MenuBarEffect {
        switch kind {
        case .pause:
            _ = interpreter.pause()
            try persistIfChanged()
            return .show(snapshot())
        case .resume:
            _ = interpreter.resume()
            try persistIfChanged()
            return .show(snapshot())
        case .settings:
            settingsVisible = true
            notice = ""
            return .show(snapshot())
        case .quit:
            return .terminate
        case .separator:
            return .show(snapshot())
        }
    }

    public func handleKeyDown(_ event: KeyEvent, cache: CachedFocus) throws -> EventDecision {
        let decision = interpreter.handleKeyDown(event, cache: cache)
        try persistIfChanged()
        return decision
    }

    public func addFrontmost() throws -> ExclusionEditor {
        let trimmed = frontmost.frontmostBundleIdentifier()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            notice = "Frontmost app has no bundle identifier."
            return editor()
        }
        let current = interpreter.settingsSnapshot()
        if current.isExcluded(bundleIdentifier: trimmed) {
            notice = "That app is already excluded."
            return editor()
        }
        var next = current
        next.excludedBundleIdentifiers.append(trimmed)
        try commit(next)
        return editor()
    }

    public func removeExcluded(bundleIdentifier: String) throws -> ExclusionEditor {
        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = interpreter.settingsSnapshot()
        let remaining = next.excludedBundleIdentifiers.filter { $0 != trimmed }
        guard remaining.count != next.excludedBundleIdentifiers.count else {
            notice = ""
            return editor()
        }
        next.excludedBundleIdentifiers = remaining
        try commit(next)
        return editor()
    }

    public func setLaunchAtLogin(_ enabled: Bool) throws -> ExclusionEditor {
        var next = interpreter.settingsSnapshot()
        guard next.launchAtLogin != enabled else {
            notice = ""
            return editor()
        }
        next.launchAtLogin = enabled
        try commit(next)
        return editor()
    }

    public func closeSettings() -> ExclusionEditor {
        settingsVisible = false
        return editor()
    }

    private func commit(_ settings: Settings) throws {
        do {
            try repository.save(settings)
        } catch let error as SettingsError {
            notice = noticeText(error)
            return
        }
        let stored = try repository.load()
        interpreter.replaceSettings(stored)
        lastSaved = stored
        notice = ""
    }

    private func persistIfChanged() throws {
        let current = interpreter.settingsSnapshot()
        guard current != lastSaved else {
            return
        }
        try repository.save(current)
        lastSaved = current
    }

    private func noticeText(_ error: SettingsError) -> String {
        switch error {
        case .invalidBundleIdentifier, .unrecognizedExcludedApplication:
            return "That bundle identifier cannot be saved."
        default:
            return "Could not save settings."
        }
    }

    /// Hint stays on the Normal label. It is a transient command, not a fourth status.
    private static func statusTitle(for mode: SupervimMode) -> String {
        switch mode {
        case .normal, .hint:
            return "Normal"
        case .insert:
            return "Insert"
        case .paused:
            return "Paused"
        }
    }
}

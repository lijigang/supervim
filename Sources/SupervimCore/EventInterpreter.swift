import Foundation

/// Where a key goes after the event tap has decided.
/// `passThrough` gives it back to the focused app. `swallow` keeps it.
public enum KeyDelivery: Equatable, Sendable {
    case passThrough
    case swallow
}

public enum HintEnd: Equatable, Sendable {
    case completed
    case cancelled
}

public protocol HintModeEnding: AnyObject, Sendable {
    func endHint(_ reason: HintEnd) -> EventDecision
}

/// An overlay change for a later drawing task.
/// Nothing in this module creates a window.
public enum OverlayUpdate: Equatable, Sendable {
    case beginHint(HintClick)
    case hintKey(KeyEvent)
    case endHint
    case showHelp
}

/// Screen rectangle copied with a focus element.
/// The axes stay in the coordinate space the reader used.
public struct FocusFrame: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Inclusive on every edge. A non-positive or non-finite size contains nothing.
    public func contains(x: Double, y: Double) -> Bool {
        guard width > 0, height > 0, x.isFinite, y.isFinite, self.x.isFinite, self.y.isFinite else {
            return false
        }
        return x >= self.x && x <= self.x + width && y >= self.y && y <= self.y + height
    }

    /// True when the overlap covers at least half of the smaller rectangle.
    /// A missing or empty rectangle does not overlap.
    public func overlaps(_ other: FocusFrame, minimumRatio: Double = 0.5) -> Bool {
        guard width > 0, height > 0, other.width > 0, other.height > 0,
              x.isFinite, y.isFinite, other.x.isFinite, other.y.isFinite
        else {
            return false
        }
        let left = max(x, other.x)
        let right = min(x + width, other.x + other.width)
        let top = max(y, other.y)
        let bottom = min(y + height, other.y + other.height)
        let overlapWidth = right - left
        let overlapHeight = bottom - top
        guard overlapWidth > 0, overlapHeight > 0 else {
            return false
        }
        let smaller = min(width * height, other.width * other.height)
        guard smaller > 0 else {
            return false
        }
        return (overlapWidth * overlapHeight) / smaller >= minimumRatio
    }
}

/// Focus and frontmost app, already read by something outside the event hook.
/// An empty bundle identifier is treated as excluded by Settings.
/// `elementIdentity` is the accessibility element's identity. Nil means the reader
/// could not name the element. The same identity after Esc is not a new field.
public struct CachedFocus: Equatable, Sendable {
    public var editability: FocusEditability
    public var bundleIdentifier: String
    public var elementIdentity: String?
    public var frame: FocusFrame?
    public var role: String?
    public var subrole: String?

    public init(
        editability: FocusEditability,
        bundleIdentifier: String,
        elementIdentity: String? = nil,
        frame: FocusFrame? = nil,
        role: String? = nil,
        subrole: String? = nil
    ) {
        self.editability = editability
        self.bundleIdentifier = bundleIdentifier
        self.elementIdentity = elementIdentity
        self.frame = frame
        self.role = role
        self.subrole = subrole
    }

    public static let unknown = CachedFocus(editability: .unknown, bundleIdentifier: "")
}

/// What the event hook should do with one key.
/// `actions` and `overlay` are decisions only. This type does not click, scroll, or draw.
public struct EventDecision: Equatable, Sendable {
    public var delivery: KeyDelivery
    public var mode: SupervimMode
    public var actions: [Action]
    public var overlay: OverlayUpdate?
    public var modeEffects: [ModeEffect]

    public init(
        delivery: KeyDelivery,
        mode: SupervimMode,
        actions: [Action] = [],
        overlay: OverlayUpdate? = nil,
        modeEffects: [ModeEffect] = []
    ) {
        self.delivery = delivery
        self.mode = mode
        self.actions = actions
        self.overlay = overlay
        self.modeEffects = modeEffects
    }
}

/// Wires one key to ModeMachine, KeyParser, and CommandMap.
///
/// The hook passes in a focus snapshot that was cached earlier. This type does not
/// scan the accessibility tree, and it does not perform the action it returns.
/// Ctrl+Option+V (or the shortcut stored in Settings) is `togglePause` and is not
/// fed to the parser. A saved `Settings.isPaused` starts the machine paused.
/// Menu pause and the chord both write that flag back onto the in-memory settings.
///
/// Every entry point takes one lock. The event tap has its own thread, focus
/// reports come from a background queue, hint results from another, and the
/// menu from the main thread.
public final class EventInterpreter<Clock: KeyTimeSource>: @unchecked Sendable {
    public let clock: Clock

    public var mode: SupervimMode {
        gate.lock()
        defer { gate.unlock() }
        return machine.mode
    }

    private let gate = NSRecursiveLock()

    private var settings: Settings
    private var cache: CachedFocus
    private var machine = ModeMachine()
    private var parser: KeyParser<Clock>
    private let commands = CommandMap()
    /// Set when Esc leaves Insert on a named element. The same field does not
    /// auto-enter Insert again until a different field is focused, `i` is
    /// pressed, or the pointer clicks inside that field's frame.
    ///
    /// WeChat replaces the focused accessibility object on every read, so the
    /// token from `CFEqual` changes. The hold also matches bundle, role, and an
    /// overlapping frame, and a read with no frame is not treated as a new field.
    private var heldComposer: HeldComposer?

    public init(settings: Settings = .defaults, clock: Clock, cache: CachedFocus = .unknown) {
        self.clock = clock
        self.settings = settings
        self.cache = cache
        parser = KeyParser(
            clock: clock,
            prefixTimeoutMilliseconds: Int64(settings.keySequenceTimeoutMilliseconds)
        )
        _ = apply(cache)
        if settings.isPaused {
            _ = machine.handle(.pause)
        }
    }

    public func settingsSnapshot() -> Settings {
        gate.lock()
        defer { gate.unlock() }
        return settings
    }

    /// Menu pause. This is not a key, so the decision passes the event through.
    /// A pending prefix is dropped and is not replayed after resume.
    public func pause() -> EventDecision {
        gate.lock()
        defer { gate.unlock() }
        let previous = machine.mode
        _ = parser.suspendParsing()
        let step = machine.handle(.pause)
        settings.isPaused = machine.mode == .paused
        let decision = decided(
            delivery: .passThrough,
            actions: [],
            overlay: overlay(from: step.effects),
            effects: step.effects
        )
        trace("pause", from: previous)
        return decision
    }

    /// Menu resume. A resume while the machine is not paused leaves the mode alone.
    public func resume() -> EventDecision {
        gate.lock()
        defer { gate.unlock() }
        let previous = machine.mode
        let step = machine.handle(.resume)
        settings.isPaused = machine.mode == .paused
        let decision = decided(
            delivery: .passThrough,
            actions: [],
            overlay: overlay(from: step.effects),
            effects: step.effects
        )
        trace("resume", from: previous)
        return decision
    }

    public func handleKeyDown(_ event: KeyEvent, cache: CachedFocus) -> EventDecision {
        gate.lock()
        defer { gate.unlock() }
        let previous = machine.mode
        let holdBefore = heldComposer
        let transition = apply(cache)
        let decision: EventDecision
        if shouldPause(event) {
            _ = parser.suspendParsing()
            let step = machine.handle(.togglePause)
            settings.isPaused = machine.mode == .paused
            decision = decided(
                delivery: .swallow,
                actions: [],
                overlay: overlay(from: step.effects) ?? transition.overlay,
                effects: transition.effects + step.effects
            )
        } else if !interpretsCommands {
            _ = parser.suspendParsing()
            decision = decisionWithoutParser(event, transition: transition)
        } else {
            decision = decisionFromParser(event, transition: transition)
        }
        trace(triggerText(event), from: previous)
        if let line = hintKeyLine(event, decision: decision, hold: holdLabel(before: holdBefore)) {
            ModeTrace.noteLine(line)
        }
        return decision
    }

    /// Applies a snapshot between keys. Does not scan and does not swallow a key.
    @discardableResult
    public func updateCache(_ cache: CachedFocus) -> EventDecision {
        gate.lock()
        defer { gate.unlock() }
        let previous = machine.mode
        let decision = applyCache(cache)
        trace("focus", from: previous)
        return decision
    }

    /// Leaves Hint after a label was clicked or the overlay gave up.
    /// Does nothing to a prefix or to another mode. The key hook does not call this.
    public func endHint(_ reason: HintEnd) -> EventDecision {
        gate.lock()
        defer { gate.unlock() }
        let previous = machine.mode
        let input: ModeInput
        switch reason {
        case .completed:
            input = .hintCompleted
        case .cancelled:
            input = .hintCancelled
        }
        let step = machine.handle(input)
        if step.effects.contains(.endHint) {
            _ = parser.suspendParsing()
        }
        let decision = decided(
            delivery: .passThrough,
            actions: [],
            overlay: overlay(from: step.effects),
            effects: step.effects
        )
        trace("hint-end", from: previous)
        return decision
    }

    /// A click inside the input that Esc is holding re-enters Insert.
    /// A click anywhere else leaves Normal alone and does not swallow the click.
    public func acceptPointerClick(x: Double, y: Double) -> EventDecision {
        gate.lock()
        defer { gate.unlock() }
        let previous = machine.mode
        guard let frame = cache.frame,
              heldComposer != nil,
              cache.editability == .editable,
              frame.contains(x: x, y: y)
        else {
            trace("click", from: previous)
            return EventDecision(delivery: .passThrough, mode: machine.mode)
        }
        heldComposer = nil
        let decision = applyCache(cache)
        trace("click", from: previous)
        return decision
    }

    /// `gi` drops the Esc hold so the following focus read can enter Insert.
    public func releaseHeldInput() {
        gate.lock()
        defer { gate.unlock() }
        heldComposer = nil
    }

    /// Insert after `gi`, including when the focus read is not editable yet.
    /// The cause is manual, so a not-editable notification does not leave Insert.
    @discardableResult
    public func enterInsertAfterFocus() -> SupervimMode {
        gate.lock()
        defer { gate.unlock() }
        let previous = machine.mode
        heldComposer = nil
        _ = machine.holdManualInsert()
        trace("gi", from: previous)
        return machine.mode
    }

    public func replaceSettings(_ settings: Settings) {
        gate.lock()
        defer { gate.unlock() }
        let timeoutChanged = settings.keySequenceTimeoutMilliseconds != self.settings.keySequenceTimeoutMilliseconds
        self.settings = settings
        if timeoutChanged {
            parser = KeyParser(
                clock: clock,
                prefixTimeoutMilliseconds: Int64(settings.keySequenceTimeoutMilliseconds)
            )
        }
        _ = apply(cache)
    }

    private var interpretsCommands: Bool {
        machine.mode == .normal
            && editabilitySeenByMachine(cache) == .notEditable
            && !settings.isExcluded(bundleIdentifier: cache.bundleIdentifier)
    }

    private func shouldPause(_ event: KeyEvent) -> Bool {
        guard cache.editability != .unknown else {
            return false
        }
        guard !settings.isExcluded(bundleIdentifier: cache.bundleIdentifier) else {
            return false
        }
        return settings.pauseShortcut.matches(event)
    }

    private func applyCache(_ next: CachedFocus) -> EventDecision {
        let transition = apply(next)
        if !interpretsCommands {
            _ = parser.suspendParsing()
        }
        return decided(
            delivery: .passThrough,
            actions: [],
            overlay: transition.overlay,
            effects: transition.effects
        )
    }

    private func apply(_ next: CachedFocus) -> Transition {
        noteIdentityChange(next)
        let foreground: ForegroundApp = settings.isExcluded(bundleIdentifier: next.bundleIdentifier)
            ? .excluded
            : .controlled
        let foregroundStep = machine.handle(.foreground(foreground))
        let focusStep = machine.handle(.focus(editabilitySeenByMachine(next)))
        cache = next
        let effects = foregroundStep.effects + focusStep.effects
        return Transition(effects: effects, overlay: overlay(from: effects))
    }

    /// A different field clears the Esc hold. A missing name does not, and neither
    /// does a new token for the same role and an overlapping frame. WeChat issues
    /// a fresh accessibility object for the composer on every query.
    private func noteIdentityChange(_ next: CachedFocus) {
        guard heldComposer != nil else {
            return
        }
        if sameHeldComposer(next) {
            return
        }
        heldComposer = nil
    }

    /// While Esc is holding the composer, that field is shown to the mode machine
    /// as not editable, so Normal commands keep working. A cache with no identity
    /// and no hold keeps the previous rule.
    private func editabilitySeenByMachine(_ next: CachedFocus) -> FocusEditability {
        guard heldComposer != nil else {
            return next.editability
        }
        if sameHeldComposer(next), next.editability != .notEditable {
            return .notEditable
        }
        return next.editability
    }

    private func sameHeldComposer(_ next: CachedFocus) -> Bool {
        guard let held = heldComposer else {
            return false
        }
        if next.elementIdentity == nil || next.elementIdentity == held.identity {
            return true
        }
        guard next.bundleIdentifier == held.bundleIdentifier else {
            return false
        }
        guard rolesMatch(held, next) else {
            return false
        }
        guard framesMatch(held.frame, next.frame) else {
            return false
        }
        return next.editability != .notEditable
    }

    private func rolesMatch(_ held: HeldComposer, _ next: CachedFocus) -> Bool {
        guard let role = next.role else {
            return true
        }
        return role == held.role && next.subrole == held.subrole
    }

    private func framesMatch(_ held: FocusFrame?, _ next: FocusFrame?) -> Bool {
        guard let held, let next else {
            return true
        }
        return held.overlaps(next)
    }

    private func decisionWithoutParser(_ event: KeyEvent, transition: Transition) -> EventDecision {
        let wasHint: Bool
        if case .hint = machine.mode {
            wasHint = true
        } else {
            wasHint = false
        }
        let step = machine.handle(.key(modeKey(for: event)))
        var overlay = transition.overlay
        if step.effects.contains(.endHint) {
            overlay = .endHint
        } else if wasHint && step.effects.contains(.swallowKey) {
            overlay = .hintKey(event)
        }
        return decided(
            delivery: delivery(from: step.effects),
            actions: [],
            overlay: overlay,
            effects: transition.effects + step.effects
        )
    }

    private func decisionFromParser(_ event: KeyEvent, transition: Transition) -> EventDecision {
        let parsed = parser.handle(event)
        var delivery = KeyDelivery.passThrough
        var actions: [Action] = []
        var overlay = transition.overlay
        var effects = transition.effects

        for result in parsed.results {
            switch commands.disposition(for: result) {
            case .passThrough:
                let step = machine.handle(.key(.other))
                delivery = self.delivery(from: step.effects)
                actions = []
                effects.append(contentsOf: step.effects)
            case .swallow:
                delivery = .swallow
            case .perform(let action):
                switch action {
                case .escape:
                    let step = machine.handle(.key(.escape))
                    effects.append(contentsOf: step.effects)
                    if step.effects.contains(.passKeyThrough) {
                        delivery = .passThrough
                        actions = []
                    } else {
                        delivery = .swallow
                        actions = [action]
                    }
                case .enterInsert:
                    let step = machine.handle(.key(.manualInsert))
                    effects.append(contentsOf: step.effects)
                    delivery = .swallow
                    actions = [action]
                case .beginHint(let click):
                    let step = machine.handle(.key(.hint(click)))
                    effects.append(contentsOf: step.effects)
                    delivery = .swallow
                    actions = [action]
                    overlay = .beginHint(click)
                case .showHelp:
                    delivery = .swallow
                    actions = [action]
                    overlay = .showHelp
                case .scroll, .sendShortcut, .sequence, .focusFirstInput, .passNextKey:
                    delivery = .swallow
                    actions = [action]
                }
            }
        }

        return decided(delivery: delivery, actions: actions, overlay: overlay, effects: effects)
    }

    private func decided(
        delivery: KeyDelivery,
        actions: [Action],
        overlay: OverlayUpdate?,
        effects: [ModeEffect]
    ) -> EventDecision {
        if effects.contains(.blurFocus), let identity = cache.elementIdentity {
            heldComposer = HeldComposer(
                identity: identity,
                bundleIdentifier: cache.bundleIdentifier,
                role: cache.role,
                subrole: cache.subrole,
                frame: cache.frame
            )
        }
        return EventDecision(
            delivery: delivery,
            mode: machine.mode,
            actions: actions,
            overlay: overlay,
            modeEffects: effects
        )
    }

    private func holdLabel(before: HeldComposer?) -> String {
        guard before != nil else {
            return "none"
        }
        guard heldComposer != nil else {
            return "cleared"
        }
        if cache.elementIdentity == nil {
            return "unnamed"
        }
        return "kept"
    }

    private func hintKeyLine(_ event: KeyEvent, decision: EventDecision, hold: String) -> String? {
        guard event.modifiers.intersection([.control, .option, .command]).isEmpty,
              case .character(let character) = event.identity,
              character == "f" || character == "F"
        else {
            return nil
        }
        let why: String
        if settings.isExcluded(bundleIdentifier: cache.bundleIdentifier) {
            why = "excluded"
        } else if machine.mode == .paused {
            why = "paused"
        } else if case .beginHint = decision.overlay {
            if cache.editability == .editable && (hold == "kept" || hold == "unnamed") {
                why = "held-normal"
            } else {
                why = "normal"
            }
        } else if case .hint = machine.mode {
            why = "hint"
        } else {
            switch cache.editability {
            case .unknown:
                why = "unknown-focus"
            case .editable:
                why = "editable-focus"
            case .notEditable:
                why = "normal"
            }
        }
        let delivery = decision.delivery == .swallow ? "swallow" : "passThrough"
        return ModeTrace.formatHintKey(
            key: String(character),
            mode: modeName(machine.mode),
            why: why,
            delivery: delivery,
            bundle: cache.bundleIdentifier,
            role: cache.role,
            subrole: cache.subrole,
            identity: cache.elementIdentity,
            held: hold
        )
    }

    private func modeName(_ mode: SupervimMode) -> String {
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

    private func triggerText(_ event: KeyEvent) -> String {
        switch event.identity {
        case .character(let character):
            return String(character)
        case .escape:
            return "escape"
        case .unnamed:
            return "unnamed"
        }
    }

    private func trace(_ trigger: String, from previous: SupervimMode) {
        ModeTrace.note(
            from: previous,
            to: machine.mode,
            role: cache.role,
            subrole: cache.subrole,
            trigger: trigger,
            identity: cache.elementIdentity
        )
    }

    private func modeKey(for event: KeyEvent) -> ModeKey {
        isPlainEscape(event) ? .escape : .other
    }

    private func isPlainEscape(_ event: KeyEvent) -> Bool {
        guard event.modifiers.intersection([.control, .option, .command]).isEmpty else {
            return false
        }
        switch event.identity {
        case .escape:
            return true
        case .character("\u{1B}"):
            return true
        case .character, .unnamed:
            return false
        }
    }

    private func delivery(from effects: [ModeEffect]) -> KeyDelivery {
        if effects.contains(.passKeyThrough) {
            return .passThrough
        }
        if effects.contains(.swallowKey) {
            return .swallow
        }
        return .passThrough
    }

    private func overlay(from effects: [ModeEffect]) -> OverlayUpdate? {
        effects.contains(.endHint) ? .endHint : nil
    }
}

extension EventInterpreter: HintModeEnding {}

extension EventInterpreter {
    private struct Transition {
        var effects: [ModeEffect]
        var overlay: OverlayUpdate?
    }

    private struct HeldComposer: Equatable {
        var identity: String
        var bundleIdentifier: String
        var role: String?
        var subrole: String?
        var frame: FocusFrame?
    }
}

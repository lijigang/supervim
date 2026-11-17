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
public final class EventInterpreter<Clock: KeyTimeSource>: @unchecked Sendable {
    public let clock: Clock

    public var mode: SupervimMode {
        machine.mode
    }

    private var settings: Settings
    private var cache: CachedFocus
    private var machine = ModeMachine()
    private var parser: KeyParser<Clock>
    private let commands = CommandMap()
    /// Set when Esc leaves Insert on a named element. The same element does not
    /// auto-enter Insert again until the identity changes, `i` is pressed, or
    /// the pointer clicks inside that element's frame.
    private var heldNormalIdentity: String?

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
        settings
    }

    /// Menu pause. This is not a key, so the decision passes the event through.
    /// A pending prefix is dropped and is not replayed after resume.
    public func pause() -> EventDecision {
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
        let previous = machine.mode
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
        return decision
    }

    /// Applies a snapshot between keys. Does not scan and does not swallow a key.
    @discardableResult
    public func updateCache(_ cache: CachedFocus) -> EventDecision {
        let previous = machine.mode
        let decision = applyCache(cache)
        trace("focus", from: previous)
        return decision
    }

    /// Leaves Hint after a label was clicked or the overlay gave up.
    /// Does nothing to a prefix or to another mode. The key hook does not call this.
    public func endHint(_ reason: HintEnd) -> EventDecision {
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
        let previous = machine.mode
        guard let frame = cache.frame,
              heldNormalIdentity != nil,
              cache.elementIdentity == heldNormalIdentity,
              cache.editability == .editable,
              frame.contains(x: x, y: y)
        else {
            trace("click", from: previous)
            return EventDecision(delivery: .passThrough, mode: machine.mode)
        }
        heldNormalIdentity = nil
        let decision = applyCache(cache)
        trace("click", from: previous)
        return decision
    }

    /// `gi` drops the Esc hold so the following focus read can enter Insert.
    public func releaseHeldInput() {
        heldNormalIdentity = nil
    }

    public func replaceSettings(_ settings: Settings) {
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

    /// A different named element clears the Esc hold. A missing name does not:
    /// a failed or partial read is not "the caret entered a new field".
    private func noteIdentityChange(_ next: CachedFocus) {
        guard let identity = next.elementIdentity else {
            return
        }
        if heldNormalIdentity != identity {
            heldNormalIdentity = nil
        }
    }

    /// While Esc is holding an element, that same element (or an unnamed read)
    /// is shown to the mode machine as not editable, so Normal commands keep working.
    /// A cache with no identity and no hold keeps the previous rule.
    private func editabilitySeenByMachine(_ next: CachedFocus) -> FocusEditability {
        guard let held = heldNormalIdentity else {
            return next.editability
        }
        let sameOrUnnamed = next.elementIdentity == held || next.elementIdentity == nil
        if sameOrUnnamed, next.editability != .notEditable {
            return .notEditable
        }
        return next.editability
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
            heldNormalIdentity = identity
        }
        return EventDecision(
            delivery: delivery,
            mode: machine.mode,
            actions: actions,
            overlay: overlay,
            modeEffects: effects
        )
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
}

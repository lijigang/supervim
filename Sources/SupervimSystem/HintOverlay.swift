import Foundation
import SupervimCore

public protocol ClickableQuerying: AnyObject, Sendable {
    func clickableElements() -> ClickableQuery
}

extension AXScanner: ClickableQuerying {}

/// How an overlay window is allowed to behave.
/// Hint labels are transparent, ignore the mouse, and must not activate the app.
public struct OverlayWindowPolicy: Equatable, Sendable {
    public var isTransparent: Bool
    public var isNonActivating: Bool
    public var ignoresMouseEvents: Bool

    public init(isTransparent: Bool, isNonActivating: Bool, ignoresMouseEvents: Bool) {
        self.isTransparent = isTransparent
        self.isNonActivating = isNonActivating
        self.ignoresMouseEvents = ignoresMouseEvents
    }

    public static let hintLabels = OverlayWindowPolicy(
        isTransparent: true,
        isNonActivating: true,
        ignoresMouseEvents: true
    )
}

public struct OverlayPresentation: Equatable, Sendable {
    public var markers: [HintMarker]
    public var policy: OverlayWindowPolicy
    /// Lowercase prefix the user has typed. Empty until a hint character arrives.
    /// Labels that still match paint this many characters in the accent color.
    public var typedPrefix: String

    public init(markers: [HintMarker], policy: OverlayWindowPolicy, typedPrefix: String = "") {
        self.markers = markers
        self.policy = policy
        self.typedPrefix = typedPrefix
    }
}

public protocol OverlayPresenting: AnyObject, Sendable {
    func present(_ presentation: OverlayPresentation)
    func hideOverlay()
}

public enum HintCancelReason: Equatable, Sendable {
    case unavailable
    case noTargets
    case invalidInput
    case dismissed
}

public enum VisionHintResult: Equatable, Sendable {
    case skipped
    case targets([HintTarget])
    case needsScreenRecording
    case empty
}

/// Starts a vision pass off the event-tap thread.
/// The completion may run before `prepareHints` returns, or later.
public protocol VisionHintServing: AnyObject, Sendable {
    func prepareHints(
        bundleIdentifier: String,
        axHitCount: Int,
        completion: @escaping @Sendable (VisionHintResult) -> Void
    )
}

/// What the app calls after it has already decided to hint.
/// The caller moves ModeMachine into Hint before `enterHint`, then feeds
/// later keys here. `cancelHint` hides the labels and leaves Hint.
public protocol HintOverlayControlling: AnyObject, Sendable {
    func refreshClickables() -> ClickableQuery
    func enterHint(_ click: HintClick) -> HintOverlayResult
    func receiveHintKey(_ event: KeyEvent, keyCode: UInt16?) -> HintOverlayResult
    func cancelHint() -> HintOverlayResult
}

extension HintOverlayControlling {
    public func receiveHintKey(_ event: KeyEvent) -> HintOverlayResult {
        receiveHintKey(event, keyCode: nil)
    }
}

public enum HintOverlayResult: Equatable, Sendable {
    case unchanged
    case ignored
    case inactive
    case showing(OverlayPresentation)
    case activated(HintActivation, ActuatorOutcome)
    case cancelled(HintCancelReason)
}

public final class LockedClickableCache: @unchecked Sendable {
    private let lock = NSLock()
    private var query: ClickableQuery

    public init(query: ClickableQuery = .unavailable) {
        self.query = query
    }

    public func replace(_ query: ClickableQuery) {
        lock.lock()
        self.query = query
        lock.unlock()
    }

    public func current() -> ClickableQuery {
        lock.lock()
        defer { lock.unlock() }
        return query
    }
}

/// Scans, shows hint labels and clicks when a label is completed.
///
/// `enterHint` starts a new scan of the window every time. Labels from an
/// earlier scan are not reused: the page may have scrolled or loaded since,
/// and a label in the wrong place clicks the wrong thing.
///
/// With a `scanning` scheduler, `enterHint` returns before the scan starts
/// and the labels appear when it ends. Keys typed in between are kept and
/// replayed in order once the labels exist. A cancel, or a second
/// `enterHint`, makes the scan in flight a no-op. Without a scheduler the
/// scan runs inside `enterHint`, which is what the tests of the label logic
/// use.
///
/// The vision pass starts before the accessibility scan for the bundle ids
/// in `visionBundles`, because those always use it. For other apps it starts
/// only after the scan found nothing.
///
/// A plain click is `AXPress` when the element offers it, with the frame
/// center as the fallback. Command click holds Command and is not a context
/// menu.
public final class HintController: HintOverlayControlling, @unchecked Sendable {
    private enum Phase {
        case idle
        case scanning
        case waitingForVision
        case active
    }

    private let querier: any ClickableQuerying
    private let presenter: any OverlayPresenting
    private let actuator: ActionActuator
    private let mode: any HintModeEnding
    private let cache: LockedClickableCache
    private let misses: HintMissBanner?
    private let vision: (any VisionHintServing)?
    private let frontBundle: @Sendable () -> String
    private let scanning: (any WorkScheduling)?
    private let visionBundles: @Sendable () -> [String]
    private let lock = NSLock()
    private var session: HintSession?
    private var phase = Phase.idle
    private var generation = 0
    private var pendingClick: HintClick = .plain
    private var pendingTargets: [HintTarget] = []
    private var bufferedKeys: [(event: KeyEvent, keyCode: UInt16?)] = []
    private var earlyVision: VisionHintResult?
    private var lastResult = HintOverlayResult.unchanged
    private var watch = TraceStopwatch()
    private var activation: (@Sendable () -> Void)?

    public init(
        querier: any ClickableQuerying,
        presenter: any OverlayPresenting,
        actuator: ActionActuator,
        mode: any HintModeEnding,
        cache: LockedClickableCache = LockedClickableCache(),
        misses: HintMissBanner? = nil,
        vision: (any VisionHintServing)? = nil,
        frontBundle: @escaping @Sendable () -> String = { "" },
        scanning: (any WorkScheduling)? = nil,
        visionBundles: @escaping @Sendable () -> [String] = { [] }
    ) {
        self.querier = querier
        self.presenter = presenter
        self.actuator = actuator
        self.mode = mode
        self.cache = cache
        self.misses = misses
        self.vision = vision
        self.frontBundle = frontBundle
        self.scanning = scanning
        self.visionBundles = visionBundles
    }

    /// Called after a label was clicked. The app uses it to read focus
    /// again: an app that sends no focus notification would otherwise keep
    /// the mode the click made stale.
    public func onActivation(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        activation = handler
        lock.unlock()
    }

    @discardableResult
    public func refreshClickables() -> ClickableQuery {
        let query = querier.clickableElements()
        cache.replace(query)
        return query
    }

    /// Maps a decision the event hook already returned.
    /// `beginHint` is `enterHint`, a hint key is `receiveHintKey`, and
    /// `endHint` is `cancelHint`. `showHelp` stays ignored here.
    /// `HelpController` claims that update.
    @discardableResult
    public func consume(_ decision: EventDecision, hintKeyCode: UInt16? = nil) -> HintOverlayResult {
        guard let update = decision.overlay else {
            return .unchanged
        }
        switch update {
        case .beginHint(let click):
            return enterHint(click)
        case .hintKey(let event):
            return receiveHintKey(event, keyCode: hintKeyCode)
        case .endHint:
            return cancelHint()
        case .showHelp:
            return .ignored
        }
    }

    @discardableResult
    public func enterHint(_ click: HintClick) -> HintOverlayResult {
        lock.lock()
        generation += 1
        let ticket = generation
        session = nil
        phase = .scanning
        pendingClick = click
        pendingTargets = []
        bufferedKeys = []
        earlyVision = nil
        watch = TraceStopwatch()
        let waiting = HintOverlayResult.showing(OverlayPresentation(markers: [], policy: .hintLabels))
        lastResult = waiting
        lock.unlock()
        guard let scanning else {
            scan(ticket: ticket, click: click)
            lock.lock()
            defer { lock.unlock() }
            return lastResult
        }
        scanning.run { [self] in
            scan(ticket: ticket, click: click)
        }
        return waiting
    }

    @discardableResult
    public func receiveHintKey(_ event: KeyEvent, keyCode: UInt16? = nil) -> HintOverlayResult {
        lock.lock()
        defer { lock.unlock() }
        return type(event, keyCode: keyCode)
    }

    @discardableResult
    public func cancelHint() -> HintOverlayResult {
        lock.lock()
        defer { lock.unlock() }
        return dismiss()
    }

    /// Off the key hook when a scheduler was given.
    private func scan(ticket: Int, click: HintClick) {
        guard isCurrent(ticket) else {
            return
        }
        let bundle = frontBundle()
        let early = vision != nil && visionBundles().contains(bundle)
        if early {
            requestVision(ticket: ticket, bundle: bundle, axHitCount: 0)
        }
        let scanWatch = TraceStopwatch()
        let query = querier.clickableElements()
        cache.replace(query)
        let targets: [HintTarget]
        switch query {
        case .unavailable:
            targets = []
        case .elements(let snapshot):
            targets = Self.rankedTargets(snapshot.elements)
        }
        ModeTrace.noteTiming(
            stage: "hint-scan",
            milliseconds: scanWatch.milliseconds,
            fields: [("targets", "\(targets.count)"), ("bundle", bundle.isEmpty ? "-" : bundle)]
        )

        lock.lock()
        guard generation == ticket, phase == .scanning else {
            lock.unlock()
            return
        }
        guard vision != nil else {
            finish(show(targets, click: click))
            lock.unlock()
            return
        }
        if early, let result = earlyVision {
            earlyVision = nil
            finish(applyVision(result, axTargets: targets, click: click))
            lock.unlock()
            return
        }
        phase = .waitingForVision
        pendingTargets = targets
        lock.unlock()
        if !early {
            requestVision(ticket: ticket, bundle: bundle, axHitCount: targets.count)
        }
    }

    private func isCurrent(_ ticket: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == ticket && phase != .idle
    }

    /// The completion may run before `prepareHints` returns, on this thread.
    private func requestVision(ticket: Int, bundle: String, axHitCount: Int) {
        let visionWatch = TraceStopwatch()
        vision?.prepareHints(bundleIdentifier: bundle, axHitCount: axHitCount) { [weak self] result in
            if result != .skipped {
                ModeTrace.noteTiming(stage: "hint-vision", milliseconds: visionWatch.milliseconds, fields: [])
            }
            self?.receiveVision(result, ticket: ticket)
        }
    }

    private func receiveVision(_ result: VisionHintResult, ticket: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == ticket else {
            return
        }
        switch phase {
        case .scanning:
            earlyVision = result
        case .waitingForVision:
            let targets = pendingTargets
            pendingTargets = []
            finish(applyVision(result, axTargets: targets, click: pendingClick))
        case .idle, .active:
            return
        }
    }

    /// Records what the scan led to and replays the keys typed meanwhile.
    private func finish(_ shown: HintOverlayResult) {
        lastResult = shown
        let keys = bufferedKeys
        bufferedKeys = []
        guard case .showing = shown else {
            return
        }
        for key in keys {
            let result = type(key.event, keyCode: key.keyCode)
            lastResult = result
            guard case .showing = result else {
                return
            }
        }
    }

    private func applyVision(
        _ result: VisionHintResult,
        axTargets: [HintTarget],
        click: HintClick
    ) -> HintOverlayResult {
        switch result {
        case .skipped:
            return show(axTargets, click: click)
        case .targets(let found):
            if found.isEmpty {
                return axTargets.isEmpty ? stop(.noTargets) : show(axTargets, click: click)
            }
            return show(found, click: click)
        case .needsScreenRecording:
            return stop(.noTargets, banner: HintMissBanner.screenRecordingMessage)
        case .empty:
            if !axTargets.isEmpty {
                return show(axTargets, click: click)
            }
            if case .unavailable = cache.current() {
                return stop(.unavailable)
            }
            return stop(.noTargets)
        }
    }

    private func show(_ targets: [HintTarget], click: HintClick) -> HintOverlayResult {
        if targets.isEmpty, case .unavailable = cache.current() {
            return stop(.unavailable)
        }
        let started = HintSession(targets: targets, click: click)
        guard started.isActive else {
            return stop(.noTargets)
        }
        session = started
        phase = .active
        let shown = show(started.markers, typedPrefix: started.typedText)
        ModeTrace.noteTiming(
            stage: "hint-visible",
            milliseconds: watch.milliseconds,
            fields: [("labels", "\(started.markers.count)")]
        )
        return shown
    }

    private func type(_ event: KeyEvent, keyCode: UInt16?) -> HintOverlayResult {
        if phase == .scanning || phase == .waitingForVision {
            bufferedKeys.append((event, keyCode))
            return .showing(OverlayPresentation(markers: [], policy: .hintLabels))
        }
        guard var current = session, current.isActive else {
            return .inactive
        }
        switch HintTyping.resolve(event, keyCode: keyCode) {
        case .cancel:
            let reason: HintCancelReason = event.identity == .escape ? .dismissed : .invalidInput
            return stop(reason)
        case .input(let input):
            switch current.handle(input) {
            case .showing(let markers):
                session = current
                return show(markers, typedPrefix: current.typedText)
            case .activated(let activation):
                let outcome = actuator.click(Self.request(for: activation))
                session = nil
                phase = .idle
                presenter.hideOverlay()
                _ = mode.endHint(.completed)
                self.activation?()
                return .activated(activation, outcome)
            case .cancelled:
                return stop(.invalidInput)
            case .inactive:
                session = current
                return .inactive
            }
        }
    }

    private func show(_ markers: [HintMarker], typedPrefix: String) -> HintOverlayResult {
        let presentation = OverlayPresentation(
            markers: markers,
            policy: .hintLabels,
            typedPrefix: typedPrefix
        )
        presenter.present(presentation)
        return .showing(presentation)
    }

    private func dismiss() -> HintOverlayResult {
        generation += 1
        phase = .idle
        bufferedKeys = []
        pendingTargets = []
        earlyVision = nil
        session = nil
        presenter.hideOverlay()
        _ = mode.endHint(.cancelled)
        return .cancelled(.dismissed)
    }

    private func stop(_ reason: HintCancelReason, banner: String? = nil) -> HintOverlayResult {
        phase = .idle
        bufferedKeys = []
        pendingTargets = []
        if reason == .noTargets || reason == .unavailable {
            if let banner {
                misses?.report(banner)
            } else {
                misses?.reportMissingClickableElements()
            }
            let name = banner == HintMissBanner.screenRecordingMessage
                ? "screenRecording"
                : (reason == .noTargets ? "noTargets" : "unavailable")
            ModeTrace.noteLine(ModeTrace.formatHintBanner(reason: name))
        }
        session = nil
        presenter.hideOverlay()
        _ = mode.endHint(.cancelled)
        return .cancelled(reason)
    }

    private static func request(for activation: HintActivation) -> ClickRequest {
        let point = ActuatorPoint(x: activation.point.x, y: activation.point.y)
        let press = activation.click == .plain && activation.canAccessibilityPress
        ModeTrace.noteLine(ModeTrace.formatHintClick(
            index: activation.index,
            method: press ? "AXPress" : "coordinate",
            x: point.x,
            y: point.y
        ))
        return ClickRequest(
            point: point,
            kind: activation.click == .command ? .command : .plain,
            elementID: activation.identifier,
            canAccessibilityPress: press
        )
    }

    /// Easiest labels go to the controls `HintRanking` puts first.
    private static func rankedTargets(_ elements: [ClickableElement]) -> [HintTarget] {
        let items = elements.enumerated().map { index, element in
            HintRankItem(
                role: element.role,
                subrole: element.subrole,
                frame: HintRect(
                    x: element.frame.x,
                    y: element.frame.y,
                    width: element.frame.width,
                    height: element.frame.height
                ),
                index: index
            )
        }
        return HintRanking.order(items).compactMap { item in
            guard elements.indices.contains(item.index) else {
                return nil
            }
            return target(from: elements[item.index])
        }
    }

    private static func target(from element: ClickableElement) -> HintTarget? {
        let frame = HintRect(
            x: element.frame.x,
            y: element.frame.y,
            width: element.frame.width,
            height: element.frame.height
        )
        guard frame.isUsable else {
            return nil
        }
        let joined = element.path.map(String.init).joined(separator: "/")
        let identifier = joined.isEmpty ? nil : joined
        let canPress = element.actions.contains("AXPress")
        return HintTarget(frame: frame, identifier: identifier, canAccessibilityPress: canPress)
    }
}

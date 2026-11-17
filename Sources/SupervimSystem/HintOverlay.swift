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

/// What the app calls after it has already decided to hint.
/// Entering hint does not scan and does not install an event tap.
/// The caller moves ModeMachine into Hint before `enterHint`, then feeds
/// later keys here. `cancelHint` hides the labels and leaves Hint.
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

/// Shows cached hint labels and clicks when a label is completed.
///
/// `consume` reads the cache and does not call `clickableElements()`.
/// The caller refreshes that cache off the event hook. A plain click is a
/// left click at the element center. Command click holds Command and is not
/// a context menu. Accessibility Press is not used: the snapshot has no
/// bound element, and a press with a dangling identifier would do nothing.
/// `canAccessibilityPress: false` keeps the actuator on the mouse path.
public final class HintController: HintOverlayControlling, @unchecked Sendable {
    private let querier: any ClickableQuerying
    private let presenter: any OverlayPresenting
    private let actuator: ActionActuator
    private let mode: any HintModeEnding
    private let cache: LockedClickableCache
    private let misses: HintMissBanner?
    private let vision: (any VisionHintServing)?
    private let frontBundle: @Sendable () -> String
    private let lock = NSLock()
    private var session: HintSession?
    private var waitingForVision = false
    private var pendingClick: HintClick = .plain
    private var pendingTargets: [HintTarget] = []
    private var bufferedKeys: [KeyEvent] = []

    public init(
        querier: any ClickableQuerying,
        presenter: any OverlayPresenting,
        actuator: ActionActuator,
        mode: any HintModeEnding,
        cache: LockedClickableCache = LockedClickableCache(),
        misses: HintMissBanner? = nil,
        vision: (any VisionHintServing)? = nil,
        frontBundle: @escaping @Sendable () -> String = { "" }
    ) {
        self.querier = querier
        self.presenter = presenter
        self.actuator = actuator
        self.mode = mode
        self.cache = cache
        self.misses = misses
        self.vision = vision
        self.frontBundle = frontBundle
    }

    @discardableResult
    public func refreshClickables() -> ClickableQuery {
        let query = querier.clickableElements()
        cache.replace(query)
        return query
    }

    /// Maps a decision the event hook already returned. Does not scan.
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
        defer { lock.unlock() }
        return begin(click)
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

    private func begin(_ click: HintClick) -> HintOverlayResult {
        let targets = loadTargets()
        guard let vision else {
            return show(targets, click: click)
        }
        let gate = VisionGate()
        gate.begin()
        let bundle = frontBundle()
        vision.prepareHints(bundleIdentifier: bundle, axHitCount: targets.count) { [weak self] result in
            gate.receive(result) { [weak self] late in
                self?.finishVision(late)
            }
        }
        if let immediate = gate.end() {
            return applyVision(immediate, axTargets: targets, click: click)
        }
        waitingForVision = true
        pendingClick = click
        pendingTargets = targets
        bufferedKeys = []
        return .showing(OverlayPresentation(markers: [], policy: .hintLabels))
    }

    private func loadTargets() -> [HintTarget] {
        var current = cache.current()
        if !Self.hasUsableTarget(current) {
            current = querier.clickableElements()
            cache.replace(current)
        }
        switch current {
        case .unavailable:
            return []
        case .elements(let snapshot):
            return Self.rankedTargets(snapshot.elements)
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

    private func finishVision(_ result: VisionHintResult) {
        lock.lock()
        defer { lock.unlock() }
        guard waitingForVision else {
            return
        }
        waitingForVision = false
        let click = pendingClick
        let axTargets = pendingTargets
        let keys = bufferedKeys
        bufferedKeys = []
        let shown = applyVision(result, axTargets: axTargets, click: click)
        guard case .showing = shown else {
            return
        }
        for key in keys {
            _ = type(key, keyCode: nil)
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
        return show(started.markers, typedPrefix: started.typedText)
    }

    private func type(_ event: KeyEvent, keyCode: UInt16?) -> HintOverlayResult {
        if waitingForVision {
            bufferedKeys.append(event)
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
                presenter.hideOverlay()
                _ = mode.endHint(.completed)
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
        waitingForVision = false
        bufferedKeys = []
        session = nil
        presenter.hideOverlay()
        _ = mode.endHint(.cancelled)
        return .cancelled(.dismissed)
    }

    private func stop(_ reason: HintCancelReason, banner: String? = nil) -> HintOverlayResult {
        waitingForVision = false
        bufferedKeys = []
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

    private static func hasUsableTarget(_ query: ClickableQuery) -> Bool {
        switch query {
        case .unavailable:
            return false
        case .elements(let snapshot):
            return snapshot.elements.contains { element in
                HintRect(
                    x: element.frame.x,
                    y: element.frame.y,
                    width: element.frame.width,
                    height: element.frame.height
                ).isUsable
            }
        }
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

/// Holds a vision result that arrives before `prepareHints` returns.
/// A later result is delivered on the callback instead.
private final class VisionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var holding = false
    private var pending: VisionHintResult?

    func begin() {
        lock.lock()
        holding = true
        pending = nil
        lock.unlock()
    }

    func receive(_ result: VisionHintResult, late: @escaping @Sendable (VisionHintResult) -> Void) {
        lock.lock()
        if holding {
            pending = result
            lock.unlock()
            return
        }
        lock.unlock()
        late(result)
    }

    func end() -> VisionHintResult? {
        lock.lock()
        holding = false
        let value = pending
        pending = nil
        lock.unlock()
        return value
    }
}

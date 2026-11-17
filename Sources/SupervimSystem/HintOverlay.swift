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

    public init(markers: [HintMarker], policy: OverlayWindowPolicy) {
        self.markers = markers
        self.policy = policy
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
public final class HintController: @unchecked Sendable {
    private let querier: any ClickableQuerying
    private let presenter: any OverlayPresenting
    private let actuator: ActionActuator
    private let mode: any HintModeEnding
    private let cache: LockedClickableCache
    private let lock = NSLock()
    private var session: HintSession?

    public init(
        querier: any ClickableQuerying,
        presenter: any OverlayPresenting,
        actuator: ActionActuator,
        mode: any HintModeEnding,
        cache: LockedClickableCache = LockedClickableCache()
    ) {
        self.querier = querier
        self.presenter = presenter
        self.actuator = actuator
        self.mode = mode
        self.cache = cache
    }

    @discardableResult
    public func refreshClickables() -> ClickableQuery {
        let query = querier.clickableElements()
        cache.replace(query)
        return query
    }

    @discardableResult
    public func consume(_ decision: EventDecision, hintKeyCode: UInt16? = nil) -> HintOverlayResult {
        lock.lock()
        defer { lock.unlock() }
        guard let update = decision.overlay else {
            return .unchanged
        }
        switch update {
        case .beginHint(let click):
            return begin(click)
        case .hintKey(let event):
            return type(event, keyCode: hintKeyCode)
        case .endHint:
            return dismiss()
        case .showHelp:
            return .ignored
        }
    }

    private func begin(_ click: HintClick) -> HintOverlayResult {
        let targets: [HintTarget]
        switch cache.current() {
        case .unavailable:
            return stop(.unavailable)
        case .elements(let snapshot):
            targets = snapshot.elements.compactMap(Self.target(from:))
        }
        let started = HintSession(targets: targets, click: click)
        guard started.isActive else {
            return stop(.noTargets)
        }
        session = started
        let presentation = OverlayPresentation(markers: started.markers, policy: .hintLabels)
        presenter.present(presentation)
        return .showing(presentation)
    }

    private func type(_ event: KeyEvent, keyCode: UInt16?) -> HintOverlayResult {
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
                let presentation = OverlayPresentation(markers: markers, policy: .hintLabels)
                presenter.present(presentation)
                return .showing(presentation)
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

    private func dismiss() -> HintOverlayResult {
        session = nil
        presenter.hideOverlay()
        return .cancelled(.dismissed)
    }

    private func stop(_ reason: HintCancelReason) -> HintOverlayResult {
        session = nil
        presenter.hideOverlay()
        _ = mode.endHint(.cancelled)
        return .cancelled(reason)
    }

    private static func request(for activation: HintActivation) -> ClickRequest {
        ClickRequest(
            point: ActuatorPoint(x: activation.point.x, y: activation.point.y),
            kind: activation.click == .command ? .command : .plain,
            elementID: activation.identifier,
            canAccessibilityPress: false
        )
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
        return HintTarget(frame: frame, identifier: identifier)
    }
}

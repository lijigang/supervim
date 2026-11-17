import Foundation
import SupervimCore

public struct HelpPresentation: Equatable, Sendable {
    public var page: HelpPage
    public var policy: OverlayWindowPolicy

    public init(page: HelpPage, policy: OverlayWindowPolicy) {
        self.page = page
        self.policy = policy
    }
}

public enum HelpOverlayResult: Equatable, Sendable {
    case unchanged
    case shown(HelpPresentation)
    case hidden
}

public struct HelpKeyOutcome: Equatable, Sendable {
    public var result: HelpOverlayResult
    public var consumesKey: Bool

    public init(result: HelpOverlayResult, consumesKey: Bool) {
        self.result = result
        self.consumesKey = consumesKey
    }
}

public protocol HelpPresenting: AnyObject, Sendable {
    func presentHelp(_ presentation: HelpPresentation)
    func hideHelp()
}

/// What the app calls to show the shortcut sheet.
/// `HelpCommandHandling` is the protocol task 11 already calls.
/// `claimHelp()` toggles and returns true, so `?` is swallowed.
/// `claimDismissal` closes on Esc only while the sheet is open.
/// `respond` is the direct key entry: a `.showHelp` decision toggles and consumes the key,
/// Esc consumes the key only while help is visible, and a new hint hides the sheet
/// without taking that key away from the hint controller.
public protocol HelpOverlayControlling: HelpCommandHandling {
    var isHelpVisible: Bool { get }
    func showHelp() -> HelpOverlayResult
    func hideHelp() -> HelpOverlayResult
    func toggleHelp() -> HelpOverlayResult
    func claimDismissal(_ event: KeyEvent) -> Bool
    func respond(to event: KeyEvent, decision: EventDecision?) -> HelpKeyOutcome
}

public final class HelpController: HelpOverlayControlling, @unchecked Sendable {
    private let presenter: any HelpPresenting
    private let lock = NSLock()
    private var sheet: HelpSheet

    public init(presenter: any HelpPresenting, bindings: [CommandBinding] = CommandMap().bindings) {
        self.presenter = presenter
        self.sheet = HelpSheet(bindings: bindings)
    }

    public var isHelpVisible: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sheet.isOpen
    }

    @discardableResult
    public func claimHelp() -> Bool {
        _ = toggleHelp()
        return true
    }

    @discardableResult
    public func showHelp() -> HelpOverlayResult {
        lock.lock()
        defer { lock.unlock() }
        return apply(sheet.show())
    }

    @discardableResult
    public func hideHelp() -> HelpOverlayResult {
        lock.lock()
        defer { lock.unlock() }
        return apply(sheet.hide())
    }

    @discardableResult
    public func toggleHelp() -> HelpOverlayResult {
        lock.lock()
        defer { lock.unlock() }
        return apply(sheet.toggle())
    }

    @discardableResult
    public func claimDismissal(_ event: KeyEvent) -> Bool {
        dismissHelp(for: event)
    }

    @discardableResult
    public func dismissHelp(for event: KeyEvent) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard sheet.isOpen, HelpSheet.isDismissKey(event) else {
            return false
        }
        _ = apply(sheet.hide())
        return true
    }

    public func yieldHelp() {
        _ = hideHelp()
    }

    public func respond(to event: KeyEvent, decision: EventDecision?) -> HelpKeyOutcome {
        lock.lock()
        defer { lock.unlock() }
        if decision?.overlay == .showHelp || (decision == nil && HelpSheet.isHelpKey(event)) {
            let result = apply(sheet.toggle())
            return HelpKeyOutcome(result: result, consumesKey: true)
        }
        if case .beginHint = decision?.overlay {
            if sheet.isOpen {
                return HelpKeyOutcome(result: apply(sheet.hide()), consumesKey: false)
            }
            return HelpKeyOutcome(result: .unchanged, consumesKey: false)
        }
        if sheet.isOpen, HelpSheet.isDismissKey(event) {
            return HelpKeyOutcome(result: apply(sheet.hide()), consumesKey: true)
        }
        return HelpKeyOutcome(result: .unchanged, consumesKey: false)
    }

    private func apply(_ change: HelpSheetChange) -> HelpOverlayResult {
        switch change {
        case .shown(let page):
            let presentation = HelpPresentation(page: page, policy: .hintLabels)
            presenter.presentHelp(presentation)
            return .shown(presentation)
        case .hidden:
            presenter.hideHelp()
            return .hidden
        case .unchanged:
            return .unchanged
        }
    }
}

import Foundation
import SupervimCore

/// The switch on an installed event tap.
public protocol TapPortControlling: AnyObject, Sendable {
    func isEnabled() -> Bool
    func enable()
}

public enum TapDisableReason: String, Equatable, Sendable {
    /// The callback took too long and macOS switched the tap off.
    case timeout
    /// macOS switched the tap off after something the user did.
    case userInput
    /// No notice arrived. The watchdog found the tap off.
    case watchdog
}

/// Keeps an event tap on.
///
/// macOS switches a tap off and leaves it off. While it is off every key
/// goes to the app untouched, which looks like Supervim ignoring `f` or `j`
/// until something restarts it. There are two ways to find out. The tap's
/// own callback is told, when its run loop gets to it. And the port can be
/// asked. `disabled` is the first, `check` is the second, for a timer that
/// does not share the tap's run loop.
public final class TapGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var port: (any TapPortControlling)?
    private var revived = 0

    public init(port: any TapPortControlling) {
        self.port = port
    }

    /// How many times the tap was found off and came back on.
    public var revivals: Int {
        lock.lock()
        defer { lock.unlock() }
        return revived
    }

    /// The tap was uninstalled on purpose. Nothing turns it on after this.
    public func release() {
        lock.lock()
        port = nil
        lock.unlock()
    }

    /// The callback received a disabled notice.
    public func disabled(_ reason: TapDisableReason) {
        lock.lock()
        let current = port
        lock.unlock()
        guard let current else {
            return
        }
        revive(current, reason: reason)
    }

    /// True when the tap was off. It has been asked to turn back on.
    @discardableResult
    public func check() -> Bool {
        lock.lock()
        let current = port
        lock.unlock()
        guard let current, !current.isEnabled() else {
            return false
        }
        revive(current, reason: .watchdog)
        return true
    }

    private func revive(_ port: any TapPortControlling, reason: TapDisableReason) {
        port.enable()
        let on = port.isEnabled()
        if on {
            lock.lock()
            revived += 1
            lock.unlock()
        }
        ModeTrace.noteLine(ModeTrace.formatTapDisabled(reason: reason.rawValue, reenabled: on))
    }
}

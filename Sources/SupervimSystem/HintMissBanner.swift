import Foundation

/// Short status-bar text after `f` finds nothing to label.
/// The title falls back once `duration` has elapsed.
public final class HintMissBanner: @unchecked Sendable {
    public static let message = "没找到可点击元素"

    public var duration: TimeInterval
    private let lock = NSLock()
    private var deadline: Date?

    public init(duration: TimeInterval = 2) {
        self.duration = duration
    }

    public func reportMissingClickableElements() {
        lock.lock()
        deadline = Date().addingTimeInterval(duration)
        lock.unlock()
    }

    public func title(fallback: String, now: Date = Date()) -> String {
        lock.lock()
        let until = deadline
        lock.unlock()
        if let until, now < until {
            return Self.message
        }
        return fallback
    }
}

import Foundation

/// Short status-bar text after `f` finds nothing to label.
/// The title falls back once `duration` has elapsed.
public final class HintMissBanner: @unchecked Sendable {
    public static let message = "没找到可点击元素"
    public static let screenRecordingMessage = "需要“屏幕录制”权限才能在此应用显示标签"
    public static let inputMissingMessage = "没找到可输入的文本框"

    public var duration: TimeInterval
    private let lock = NSLock()
    private var deadline: Date?
    private var messageText: String
    private var reported: (@Sendable () -> Void)?

    public init(duration: TimeInterval = 2) {
        self.duration = duration
        self.messageText = Self.message
    }

    /// Runs after each report. The hint scan reports from its own thread,
    /// after the key that asked for it has returned, so the status item
    /// cannot rely on that key to refresh it.
    public func onReport(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        reported = handler
        lock.unlock()
    }

    public func report(_ message: String) {
        lock.lock()
        messageText = message
        deadline = Date().addingTimeInterval(duration)
        let handler = reported
        lock.unlock()
        handler?()
    }

    public func reportMissingClickableElements() {
        report(Self.message)
    }

    public func title(fallback: String, now: Date = Date()) -> String {
        lock.lock()
        let until = deadline
        let message = messageText
        lock.unlock()
        if let until, now < until {
            return message
        }
        return fallback
    }
}

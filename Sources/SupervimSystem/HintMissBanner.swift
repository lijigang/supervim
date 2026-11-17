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

    public init(duration: TimeInterval = 2) {
        self.duration = duration
        self.messageText = Self.message
    }

    public func report(_ message: String) {
        lock.lock()
        messageText = message
        deadline = Date().addingTimeInterval(duration)
        lock.unlock()
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

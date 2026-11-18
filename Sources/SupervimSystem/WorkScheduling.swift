import Foundation

/// Where work that must not run inside the key hook goes.
///
/// The hook decides swallow or pass-through and returns. Accessibility
/// calls, event posting and tree walks are handed to one of these. Work
/// given to the same scheduler runs in the order it was given.
public protocol WorkScheduling: AnyObject, Sendable {
    func run(_ work: @escaping @Sendable () -> Void)
    func run(afterMilliseconds delay: Int, _ work: @escaping @Sendable () -> Void)
}

/// Runs the work before `run` returns. A delay is not waited for.
/// This is the default, so a type built without a scheduler behaves as one
/// synchronous call.
public final class InlineWork: WorkScheduling, @unchecked Sendable {
    public init() {}

    public func run(_ work: @escaping @Sendable () -> Void) {
        work()
    }

    public func run(afterMilliseconds delay: Int, _ work: @escaping @Sendable () -> Void) {
        _ = delay
        work()
    }
}

/// A serial queue with its own thread of execution.
public final class QueueWork: WorkScheduling, @unchecked Sendable {
    private let queue: DispatchQueue

    public init(label: String, qos: DispatchQoS = .userInteractive) {
        queue = DispatchQueue(label: label, qos: qos)
    }

    public func run(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    public func run(afterMilliseconds delay: Int, _ work: @escaping @Sendable () -> Void) {
        queue.asyncAfter(deadline: .now() + .milliseconds(max(delay, 0)), execute: work)
    }

    /// Returns after everything queued before this call has run.
    public func drain() {
        queue.sync {}
    }
}

/// Holds work until a test releases it. Delayed work is kept with its delay
/// and runs only when the test advances that far.
public final class ManualWork: WorkScheduling, @unchecked Sendable {
    private struct Item {
        var due: Int
        var order: Int
        var work: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var items: [Item] = []
    private var now = 0
    private var order = 0

    public init() {}

    public var pending: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    public func run(_ work: @escaping @Sendable () -> Void) {
        add(delay: 0, work)
    }

    public func run(afterMilliseconds delay: Int, _ work: @escaping @Sendable () -> Void) {
        add(delay: max(delay, 0), work)
    }

    /// Runs everything that is due now, including work queued while running.
    public func runPending() {
        advance(milliseconds: 0)
    }

    public func advance(milliseconds: Int) {
        lock.lock()
        now += max(milliseconds, 0)
        lock.unlock()
        while let next = takeDue() {
            next()
        }
    }

    private func add(delay: Int, _ work: @escaping @Sendable () -> Void) {
        lock.lock()
        order += 1
        items.append(Item(due: now + delay, order: order, work: work))
        lock.unlock()
    }

    private func takeDue() -> (@Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        let due = items.enumerated().filter { $0.element.due <= now }
        guard let first = due.min(by: { lhs, rhs in
            if lhs.element.due != rhs.element.due {
                return lhs.element.due < rhs.element.due
            }
            return lhs.element.order < rhs.element.order
        }) else {
            return nil
        }
        items.remove(at: first.offset)
        return first.element.work
    }
}

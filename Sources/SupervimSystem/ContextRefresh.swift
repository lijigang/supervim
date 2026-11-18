import Foundation
import SupervimCore

/// What the refresher needs from the scanner. `AXScanner` is the real one.
public protocol ContextScanning: AnyObject, Sendable {
    func noteFocusChanged() -> EventDecision
    func scanWindow(budgetMilliseconds: Double?) -> WindowScan
    func onWindowScan(_ handler: @escaping @Sendable (WindowScan) -> Void)
}

extension AXScanner: ContextScanning {}

/// Called from the event tap after a record was handled.
public protocol TapFollowUp: AnyObject, Sendable {
    /// A real left-button press went through.
    func pointerClicked()
    /// A key was pressed while the focus was unknown and so passed through.
    func keyWhileFocusUnknown()
}

/// Keeps the focus cache and the command snapshot current without ever
/// running on the key hook or the main thread.
///
/// Focus. A focus notification, a click and a completed hint each cause one
/// read of the focused element on `work`. Reads that are already queued are
/// not queued again. A read that fails leaves the focus unknown, which
/// passes every key through, so it is retried after each of `retryDelays`
/// until it succeeds. Apps that send no focus notification are covered by
/// the click and the key-while-unknown reads.
///
/// Window. The scroll catalog, the first text input and the window frame
/// come from one walk of the front window. The walk waits until focus has
/// been quiet for `settleMilliseconds`, so a burst of notifications costs
/// one walk and not one each. A hint scan is the same walk: its result is
/// adopted and the pending walk is dropped. No walk starts while labels are
/// showing, because the elements behind those labels must stay bound.
public final class ContextRefresher: TapFollowUp, @unchecked Sendable {
    public static let defaultRetryDelays = [80, 250, 700]
    public static let defaultClickDelays = [60, 300]

    private let scanner: any ContextScanning
    private let focus: any FocusCacheReading
    private let mode: @Sendable () -> SupervimMode
    private let publish: @Sendable (CommandSnapshot) -> Void
    private let modeChanged: @Sendable () -> Void
    private let windows: (any FrontWindowReading)?
    private let work: any WorkScheduling
    private let limits: TreeWalkLimits
    private let settleMilliseconds: Int
    private let retryDelays: [Int]
    private let clickDelays: [Int]
    private let unknownKeyIntervalMilliseconds: Int
    private let scanBudgetMilliseconds: Double?
    private let clock: @Sendable () -> Double
    private let lock = NSLock()
    private var readQueued = false
    private var retryEpoch = 0
    private var scanEpoch = 0
    private var lastUnknownKeyRead = -Double.infinity
    private var lastMode: SupervimMode?
    private var lastBundle: String?

    public init(
        scanner: any ContextScanning,
        focus: any FocusCacheReading,
        mode: @escaping @Sendable () -> SupervimMode,
        work: any WorkScheduling,
        publish: @escaping @Sendable (CommandSnapshot) -> Void,
        modeChanged: @escaping @Sendable () -> Void = {},
        windows: (any FrontWindowReading)? = nil,
        limits: TreeWalkLimits = .standard,
        settleMilliseconds: Int = 200,
        retryDelays: [Int] = ContextRefresher.defaultRetryDelays,
        clickDelays: [Int] = ContextRefresher.defaultClickDelays,
        unknownKeyIntervalMilliseconds: Int = 150,
        scanBudgetMilliseconds: Double? = nil,
        clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 * 1_000 }
    ) {
        self.scanner = scanner
        self.focus = focus
        self.mode = mode
        self.work = work
        self.publish = publish
        self.modeChanged = modeChanged
        self.windows = windows
        self.limits = limits
        self.settleMilliseconds = settleMilliseconds
        self.retryDelays = retryDelays
        self.clickDelays = clickDelays
        self.unknownKeyIntervalMilliseconds = unknownKeyIntervalMilliseconds
        self.scanBudgetMilliseconds = scanBudgetMilliseconds
        self.clock = clock
        scanner.onWindowScan { [weak self] scan in
            self?.adopt(scan)
        }
    }

    /// The accessibility observer or the workspace said focus may have moved.
    public func focusMayHaveChanged() {
        readFocus(retry: 0)
        scheduleScan()
    }

    public func pointerClicked() {
        for delay in clickDelays {
            work.run(afterMilliseconds: delay) { [weak self] in
                self?.readFocusNow(retry: 0)
            }
        }
        scheduleScan()
    }

    public func keyWhileFocusUnknown() {
        let now = clock()
        lock.lock()
        let due = now - lastUnknownKeyRead >= Double(unknownKeyIntervalMilliseconds)
        if due {
            lastUnknownKeyRead = now
        }
        lock.unlock()
        if due {
            readFocus(retry: 0)
        }
    }

    /// A hint click or a `gi` just acted on the app.
    public func actuated() {
        pointerClicked()
    }

    private func readFocus(retry: Int) {
        lock.lock()
        let already = readQueued
        readQueued = true
        lock.unlock()
        if already {
            return
        }
        work.run { [weak self] in
            self?.readFocusNow(retry: retry)
        }
    }

    private func readFocusNow(retry: Int) {
        lock.lock()
        readQueued = false
        retryEpoch += 1
        let epoch = retryEpoch
        lock.unlock()
        let watch = TraceStopwatch()
        _ = scanner.noteFocusChanged()
        let current = focus.currentFocus()
        let failed = current.editability == .unknown && current.role == nil
        ModeTrace.noteTiming(
            stage: "focus-read",
            milliseconds: watch.milliseconds,
            fields: [("retry", "\(retry)"), ("failed", failed ? "1" : "0")]
        )
        noteMode()
        guard failed, retry < retryDelays.count else {
            return
        }
        work.run(afterMilliseconds: retryDelays[retry]) { [weak self] in
            guard let self else {
                return
            }
            self.lock.lock()
            let superseded = self.retryEpoch != epoch
            self.lock.unlock()
            if !superseded {
                self.readFocusNow(retry: retry + 1)
            }
        }
    }

    /// The menu shows the mode, and the settings window names the front
    /// app. Either one changing is worth telling the menu about.
    private func noteMode() {
        let now = mode()
        let bundle = focus.currentFocus().bundleIdentifier
        lock.lock()
        let changed = lastMode != now || lastBundle != bundle
        lastMode = now
        lastBundle = bundle
        lock.unlock()
        if changed {
            modeChanged()
        }
    }

    private func scheduleScan() {
        lock.lock()
        scanEpoch += 1
        let epoch = scanEpoch
        lock.unlock()
        work.run(afterMilliseconds: settleMilliseconds) { [weak self] in
            self?.scanIfCurrent(epoch)
        }
    }

    private func scanIfCurrent(_ epoch: Int) {
        lock.lock()
        let current = scanEpoch == epoch
        lock.unlock()
        guard current else {
            return
        }
        if case .hint = mode() {
            return
        }
        _ = scanner.scanWindow(budgetMilliseconds: scanBudgetMilliseconds)
    }

    private func adopt(_ scan: WindowScan) {
        lock.lock()
        scanEpoch += 1
        lock.unlock()
        let frame = focus.currentFocus().frame.map {
            ElementFrame(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
        }
        var snapshot = CommandSnapshotBuilder.make(
            window: scan.window,
            focusedFrame: frame,
            firstInput: scan.firstInput,
            limits: limits
        )
        if snapshot.windowFrame == nil {
            snapshot.windowFrame = windows?.frontWindowFrame()
        }
        publish(snapshot)
    }
}

/// Tells the menu only when the mode it shows has changed.
///
/// The tap reports every key. Rebuilding the status item for each one puts
/// work on the main thread for nothing: the title depends on the mode. A nil
/// decision is a request to refresh regardless, used for banners.
public final class ModeChangeObserver: RuntimeObserving, @unchecked Sendable {
    private let inner: any RuntimeObserving
    private let lock = NSLock()
    private var last: SupervimMode?

    public init(inner: any RuntimeObserving) {
        self.inner = inner
    }

    public func runtimeDidHandle(_ decision: EventDecision?) {
        guard let decision else {
            inner.runtimeDidHandle(nil)
            return
        }
        lock.lock()
        let changed = last != decision.mode
        last = decision.mode
        lock.unlock()
        if changed {
            inner.runtimeDidHandle(decision)
        }
    }
}

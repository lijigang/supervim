#if os(macOS)
import ApplicationServices
import CoreGraphics
import Foundation
import SupervimCore

/// Builds the scanner, actuator, and event tap around the menu's interpreter.
/// Permission checks do not prompt. Task 14 owns the guide.
/// `SupervimRuntime.start` starts the scanner before installing the hook.
///
/// Four places run code, and none waits for another.
///
/// The tap thread decides what a key means from cached state and returns.
/// The scan queue reads the focused element and walks the window: after a
/// focus change, after a click, and for `f`. The actuate queue posts
/// events and makes accessibility writes. The main thread draws the labels
/// and the menu. A slow app can hold up the scan queue or the actuate
/// queue. It cannot hold up a key.
public enum MenuHookAssembly {
    public static func make(
        decider: EventInterpreter<SystemKeyClock>,
        observer: any RuntimeObserving,
        misses: HintMissBanner = HintMissBanner()
    ) -> SupervimRuntime {
        let scrollElements = AXElementStore()
        let focuser = AXInputFocuser()
        let reader = AXSystemReader(scrollElements: scrollElements, inputs: focuser)
        let relay = FocusRelay(inner: AXFocusSignal())
        let pipeline = FocusPipeline(
            decider: decider,
            reader: reader,
            signals: relay,
            waiter: AccessibilityTreeSleeper()
        )
        let scanWork = QueueWork(label: "supervim.scan", qos: .userInteractive)
        let actWork = QueueWork(label: "supervim.actuate", qos: .userInteractive)
        let poster = CGEventActuatorPoster(accessibility: scrollElements)
        let actuator = ActionActuator(poster: poster, edgeBars: scrollElements, deferral: actWork)
        let panel = NonActivatingHintPanel()
        let vision = SystemVisionHints {
            decider.settingsSnapshot().visionBundleIdentifiers
        }
        let hints = HintController(
            querier: pipeline.scanner,
            presenter: panel,
            actuator: actuator,
            mode: decider,
            misses: misses,
            vision: vision,
            frontBundle: { pipeline.cache.currentFocus().bundleIdentifier },
            scanning: scanWork,
            visionBundles: { decider.settingsSnapshot().visionBundleIdentifiers }
        )
        let help = HelpController(presenter: panel)
        let snapshots = LockedCommandSnapshot(snapshot: .unavailable)
        let session = NormalCommandSession(
            pipeline: pipeline,
            decider: decider,
            actuator: actuator,
            snapshots: snapshots,
            pointer: QuartzPointer(),
            focuser: focuser,
            hints: hints,
            help: help,
            banner: misses,
            visionBundles: { decider.settingsSnapshot().visionBundleIdentifiers },
            deferral: actWork
        )
        let menu = ModeChangeObserver(inner: observer)
        let refresher = ContextRefresher(
            scanner: pipeline.scanner,
            focus: pipeline.cache,
            mode: { decider.mode },
            work: scanWork,
            publish: { snapshot in session.replaceSnapshot(snapshot) },
            modeChanged: { menu.runtimeDidHandle(nil) },
            windows: CGFrontWindow()
        )
        relay.attach(refresher)
        misses.onReport {
            menu.runtimeDidHandle(nil)
        }
        hints.onActivation { [weak refresher] in
            refresher?.actuated()
            menu.runtimeDidHandle(nil)
        }
        let adapter = SessionTapAdapter(
            session: session,
            observer: menu,
            followUp: refresher,
            focus: pipeline.cache
        )
        let tap = CGEventTapSession(wiring: adapter)
        let starter = ScannerStarter(scanner: pipeline.scanner, refresher: refresher, panel: panel)
        return SupervimRuntime(
            permissions: SystemHookPermission(),
            focus: starter,
            hook: tap,
            owners: [
                pipeline, session, adapter, tap, poster, focuser, hints, help, panel,
                refresher, starter, relay, vision, menu, scanWork, actWork,
            ]
        )
    }
}

extension CGEventTapSession: HookControlling {}

private struct SystemHookPermission: HookPermissionReading {
    func currentHookPermission() -> HookPermission {
        HookPermission(
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess()
        )
    }
}

private final class QuartzPointer: PointerReading, @unchecked Sendable {
    func currentPointer() -> ActuatorPoint? {
        guard let event = CGEvent(source: nil) else {
            return nil
        }
        return ActuatorPoint(x: event.location.x, y: event.location.y)
    }
}

private final class ScannerStarter: FocusMonitoring, @unchecked Sendable {
    private let scanner: AXScanner
    private let refresher: ContextRefresher
    private let panel: NonActivatingHintPanel

    init(scanner: AXScanner, refresher: ContextRefresher, panel: NonActivatingHintPanel) {
        self.scanner = scanner
        self.refresher = refresher
        self.panel = panel
    }

    func start() {
        scanner.start()
        refresher.focusMayHaveChanged()
        panel.prewarm()
    }
}

/// Sends focus notifications to the refresher.
///
/// The scanner's own handler reads the focused element on the thread the
/// notification arrives on, which is the main run loop. The refresher does
/// that read on the scan queue, so the handler the scanner passes in is
/// not used.
private final class FocusRelay: FocusChangeSignaling, @unchecked Sendable {
    private let inner: AXFocusSignal
    private let lock = NSLock()
    private weak var refresher: ContextRefresher?

    init(inner: AXFocusSignal) {
        self.inner = inner
    }

    func attach(_ refresher: ContextRefresher) {
        lock.lock()
        self.refresher = refresher
        lock.unlock()
    }

    func start(_ handler: @escaping @Sendable () -> Void) {
        _ = handler
        inner.start { [weak self] in
            self?.current()?.focusMayHaveChanged()
        }
    }

    func stop() {
        inner.stop()
    }

    private func current() -> ContextRefresher? {
        lock.lock()
        defer { lock.unlock() }
        return refresher
    }
}
#endif

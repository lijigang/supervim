#if os(macOS)
import ApplicationServices
import CoreGraphics
import Foundation
import SupervimCore

/// Builds the scanner, actuator, and event tap around the menu's interpreter.
/// Permission checks do not prompt. Task 14 owns the guide.
/// `SupervimRuntime.start` starts the scanner before installing the hook.
public enum MenuHookAssembly {
    public static func make(
        decider: EventInterpreter<SystemKeyClock>,
        observer: any RuntimeObserving,
        misses: HintMissBanner = HintMissBanner()
    ) -> SupervimRuntime {
        let scrollElements = AXElementStore()
        let focuser = AXInputFocuser()
        let reader = AXSystemReader(scrollElements: scrollElements, inputs: focuser)
        let signals = AXFocusSignal()
        let fanout = FanoutSignals(inner: signals)
        let pipeline = FocusPipeline(
            decider: decider,
            reader: reader,
            signals: fanout,
            waiter: AccessibilityTreeSleeper()
        )
        let poster = CGEventActuatorPoster(accessibility: scrollElements)
        let actuator = ActionActuator(poster: poster, edgeBars: scrollElements)
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
            frontBundle: { pipeline.cache.currentFocus().bundleIdentifier }
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
            windows: CGFrontWindow(),
            visionBundles: { decider.settingsSnapshot().visionBundleIdentifiers }
        )
        let refresh = SnapshotRefresh(
            reader: reader,
            scanner: pipeline.scanner,
            session: session,
            hints: hints,
            observer: observer
        )
        fanout.extra = refresh
        let adapter = SessionTapAdapter(session: session, observer: refresh)
        let tap = CGEventTapSession(wiring: adapter)
        let starter = ScannerStarter(scanner: pipeline.scanner, after: refresh)
        return SupervimRuntime(
            permissions: SystemHookPermission(),
            focus: starter,
            hook: tap,
            owners: [pipeline, session, adapter, tap, poster, focuser, hints, help, panel, refresh, starter, fanout, vision]
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
    private let after: SnapshotRefresh

    init(scanner: AXScanner, after: SnapshotRefresh) {
        self.scanner = scanner
        self.after = after
    }

    func start() {
        scanner.start()
        after.refresh()
    }
}

private final class SnapshotRefresh: RuntimeObserving, @unchecked Sendable {
    private let reader: AXSystemReader
    private let scanner: AXScanner
    private let session: NormalCommandSession
    private let hints: HintController
    private let observer: any RuntimeObserving

    init(
        reader: AXSystemReader,
        scanner: AXScanner,
        session: NormalCommandSession,
        hints: HintController,
        observer: any RuntimeObserving
    ) {
        self.reader = reader
        self.scanner = scanner
        self.session = session
        self.hints = hints
        self.observer = observer
    }

    func refresh() {
        _ = hints.refreshClickables()
        let limits = TreeWalkLimits.standard
        let window = reader.readFrontmostWindow(maxNodes: limits.maxNodes, maxDepth: limits.maxDepth)
        let frame: ElementFrame?
        switch reader.readFocusedElement() {
        case .value(let element):
            frame = element.frame
        case .unavailable:
            frame = nil
        }
        session.replaceSnapshot(
            CommandSnapshotBuilder.make(
                window: window,
                focusedFrame: frame,
                firstInput: scanner.firstEditableInput(),
                limits: limits
            )
        )
    }

    func runtimeDidHandle(_ decision: EventDecision?) {
        observer.runtimeDidHandle(decision)
    }
}

private final class FanoutSignals: FocusChangeSignaling, @unchecked Sendable {
    private let inner: AXFocusSignal
    var extra: SnapshotRefresh?

    init(inner: AXFocusSignal) {
        self.inner = inner
    }

    func start(_ handler: @escaping @Sendable () -> Void) {
        inner.start { [weak self] in
            handler()
            self?.extra?.refresh()
        }
    }

    func stop() {
        inner.stop()
    }
}
#endif

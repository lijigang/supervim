import Foundation
import SupervimCore

/// Accessibility and Input Monitoring. Both are required before the hook is installed.
/// Neither check prompts. The permission guide is task 14.
public struct HookPermission: Equatable, Sendable {
    public var accessibility: Bool
    public var inputMonitoring: Bool

    public init(accessibility: Bool, inputMonitoring: Bool) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }

    public var canInstallHook: Bool {
        accessibility && inputMonitoring
    }
}

public protocol HookPermissionReading: Sendable {
    func currentHookPermission() -> HookPermission
}

/// Starts the focus scanner. The key hook must not call this.
public protocol FocusMonitoring: AnyObject, Sendable {
    func start()
}

/// Installs the event tap. A failure is reported and does not crash the process.
public protocol HookControlling: AnyObject, Sendable {
    func install() throws
}

public protocol RuntimeObserving: AnyObject, Sendable {
    func runtimeDidHandle(_ decision: EventDecision?)
}

public struct RuntimeStart: Equatable, Sendable {
    public var monitoredFocus: Bool
    public var installedHook: Bool

    public init(monitoredFocus: Bool, installedHook: Bool) {
        self.monitoredFocus = monitoredFocus
        self.installedHook = installedHook
    }
}

/// Starts the scanner, then the event tap, only when both permissions are granted.
/// The scanner and the tap are injected. This type does not touch AppKit.
public final class SupervimRuntime: @unchecked Sendable {
    private let permissions: any HookPermissionReading
    private let focus: any FocusMonitoring
    private let hook: any HookControlling
    /// Keeps the scanner graph alive after `start` returns.
    private let owners: [AnyObject]

    public init(
        permissions: any HookPermissionReading,
        focus: any FocusMonitoring,
        hook: any HookControlling,
        owners: [AnyObject] = []
    ) {
        self.permissions = permissions
        self.focus = focus
        self.hook = hook
        self.owners = owners
    }

    public func start() -> RuntimeStart {
        _ = owners
        guard permissions.currentHookPermission().canInstallHook else {
            return RuntimeStart(monitoredFocus: false, installedHook: false)
        }
        focus.start()
        do {
            try hook.install()
            return RuntimeStart(monitoredFocus: true, installedHook: true)
        } catch {
            return RuntimeStart(monitoredFocus: true, installedHook: false)
        }
    }
}

/// Forwards tap records to the command session, then tells the menu.
///
/// The time from the record arriving to the delivery being known is the time
/// the system waits before it delivers the key. It is logged when it is long
/// enough to notice, and always for a swallowed command.
public final class SessionTapAdapter: SystemKeyHandling, @unchecked Sendable {
    public static let slowCallbackMilliseconds = 8.0

    private let session: NormalCommandSession
    private let observer: any RuntimeObserving
    private let followUp: (any TapFollowUp)?
    private let focus: (any FocusCacheReading)?

    public init(
        session: NormalCommandSession,
        observer: any RuntimeObserving,
        followUp: (any TapFollowUp)? = nil,
        focus: (any FocusCacheReading)? = nil
    ) {
        self.session = session
        self.observer = observer
        self.followUp = followUp
        self.focus = focus
    }

    public func handleSystemRecord(_ record: SystemKeyRecord) -> SystemKeyOutcome {
        let watch = TraceStopwatch()
        let performance = session.handleSystemRecord(record)
        let elapsed = watch.milliseconds
        if record.sourceUserData != SynthesizedEventMark.userData {
            if record.pointerX != nil {
                followUp?.pointerClicked()
            } else if record.kind == .keyDown, focus?.currentFocus().editability == .unknown {
                followUp?.keyWhileFocusUnknown()
            }
        }
        if ModeTrace.isEnabled, record.kind == .keyDown,
           performance.delivery == .swallow || elapsed >= Self.slowCallbackMilliseconds {
            ModeTrace.noteTiming(
                stage: "tap",
                milliseconds: elapsed,
                fields: [("delivery", performance.delivery == .swallow ? "swallow" : "pass")]
            )
        }
        observer.runtimeDidHandle(performance.decision)
        return SystemKeyOutcome(delivery: performance.delivery, decision: performance.decision)
    }
}

extension AXScanner: FocusMonitoring {}

#if os(macOS)
import CoreGraphics
import Foundation
import SupervimCore

public enum EventTapError: Error, Equatable, Sendable {
    case creationFailed
}

/// Installs a session event tap and forwards key records to `EventTapWiring`.
/// The callback decides swallow or pass-through. `NormalCommandSession` performs
/// scrolls and shortcuts. The menu-bar app installs this only after the focus
/// scanner is running and Accessibility plus Input Monitoring are granted.
///
/// The tap has a thread and a run loop of its own. On the main run loop it
/// waited behind menus, drawing and accessibility notifications, and a slow
/// turn there is what makes macOS switch a tap off. A timer on a separate
/// queue asks the port every half second whether it is still on, because the
/// notice that it was switched off arrives through the same run loop that
/// was too slow.
public final class CGEventTapSession: EventTapInstalling, @unchecked Sendable {
    public static let watchdogIntervalMilliseconds = 500

    private let box: EventTapBox
    private let lock = NSLock()
    private var parts: TapParts?
    private var loop: TapLoop?
    private var tapGuard: TapGuard?
    private var watchdog: DispatchSourceTimer?

    public init(wiring: any SystemKeyHandling) {
        box = EventTapBox(wiring: wiring)
    }

    public func install() throws {
        lock.lock()
        defer { lock.unlock() }
        if parts != nil {
            return
        }
        let eventMask = eventBit(.keyDown) | eventBit(.keyUp) | eventBit(.flagsChanged) | eventBit(.leftMouseDown)
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: supervimEventTapCallback,
            userInfo: Unmanaged.passUnretained(box).toOpaque()
        ) else {
            throw EventTapError.creationFailed
        }
        guard let createdSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else {
            CFMachPortInvalidate(created)
            throw EventTapError.creationFailed
        }
        let made = TapParts(port: created, source: createdSource)
        let tapGuard = TapGuard(port: MachTapPort(parts: made))
        box.setGuard(tapGuard)

        let tapLoop = TapLoop()
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            tapLoop.set(CFRunLoopGetCurrent())
            CFRunLoopAddSource(CFRunLoopGetCurrent(), made.source, .commonModes)
            CGEvent.tapEnable(tap: made.port, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "supervim.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()

        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "supervim.event-tap.watchdog", qos: .userInitiated)
        )
        let interval = DispatchTimeInterval.milliseconds(Self.watchdogIntervalMilliseconds)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
        timer.setEventHandler {
            tapGuard.check()
        }
        timer.resume()

        parts = made
        loop = tapLoop
        self.tapGuard = tapGuard
        watchdog = timer
        ModeTrace.noteLine("tap-installed thread=supervim.event-tap watchdog_ms=\(Self.watchdogIntervalMilliseconds)")
    }

    public func uninstall() {
        lock.lock()
        defer { lock.unlock() }
        removeTapLocked()
    }

    deinit {
        lock.lock()
        removeTapLocked()
        lock.unlock()
    }

    private func removeTapLocked() {
        tapGuard?.release()
        box.setGuard(nil)
        watchdog?.cancel()
        watchdog = nil
        tapGuard = nil
        if let parts {
            CGEvent.tapEnable(tap: parts.port, enable: false)
            if let runLoop = loop?.get() {
                CFRunLoopRemoveSource(runLoop, parts.source, .commonModes)
                CFRunLoopStop(runLoop)
            }
            CFMachPortInvalidate(parts.port)
        }
        parts = nil
        loop = nil
    }

    private func eventBit(_ type: CGEventType) -> CGEventMask {
        CGEventMask(1) << CGEventMask(type.rawValue)
    }
}

/// The Mach port and its run loop source. Both are used from the tap thread
/// and from the thread that installs and removes the tap.
private struct TapParts: @unchecked Sendable {
    let port: CFMachPort
    let source: CFRunLoopSource
}

private final class TapLoop: @unchecked Sendable {
    private let lock = NSLock()
    private var runLoop: CFRunLoop?

    func set(_ runLoop: CFRunLoop) {
        lock.lock()
        self.runLoop = runLoop
        lock.unlock()
    }

    func get() -> CFRunLoop? {
        lock.lock()
        defer { lock.unlock() }
        return runLoop
    }
}

private final class MachTapPort: TapPortControlling, @unchecked Sendable {
    private let parts: TapParts

    init(parts: TapParts) {
        self.parts = parts
    }

    func isEnabled() -> Bool {
        CGEvent.tapIsEnabled(tap: parts.port)
    }

    func enable() {
        CGEvent.tapEnable(tap: parts.port, enable: true)
    }
}

private final class EventTapBox: @unchecked Sendable {
    let wiring: any SystemKeyHandling
    private let lock = NSLock()
    private var tapGuard: TapGuard?

    init(wiring: any SystemKeyHandling) {
        self.wiring = wiring
    }

    func setGuard(_ tapGuard: TapGuard?) {
        lock.lock()
        self.tapGuard = tapGuard
        lock.unlock()
    }

    func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tapGuard = self.tapGuard
            lock.unlock()
            if let tapGuard {
                tapGuard.disabled(type == .tapDisabledByUserInput ? .userInput : .timeout)
            } else {
                ModeTrace.noteLine(ModeTrace.formatTapDisabled(
                    reason: type == .tapDisabledByUserInput ? "userInput" : "timeout",
                    reenabled: false
                ))
            }
            return Unmanaged.passUnretained(event)
        }
        let outcome = wiring.handleSystemRecord(SystemKeyRecord(event: event, type: type))
        if outcome.delivery == .swallow {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}

private extension SystemKeyRecord {
    init(event: CGEvent, type: CGEventType) {
        if type == .leftMouseDown {
            let userData = event.getIntegerValueField(.eventSourceUserData)
            self.init(
                kind: .other,
                keyCode: 0,
                modifierFlags: event.flags.rawValue,
                unicode: "",
                sourceUserData: userData,
                pointerX: Double(event.location.x),
                pointerY: Double(event.location.y)
            )
            return
        }
        let kind: SystemEventKind
        switch type {
        case .keyDown:
            kind = .keyDown
        case .keyUp:
            kind = .keyUp
        case .flagsChanged:
            kind = .flagsChanged
        default:
            kind = .other
        }
        var units = [UniChar](repeating: 0, count: 4)
        var length = 0
        event.keyboardGetUnicodeString(
            maxStringLength: units.count,
            actualStringLength: &length,
            unicodeString: &units
        )
        let unicode = length > 0 ? String(utf16CodeUnits: units, count: length) : ""
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let userData = event.getIntegerValueField(.eventSourceUserData)
        self.init(
            kind: kind,
            keyCode: keyCode,
            modifierFlags: event.flags.rawValue,
            unicode: unicode,
            sourceUserData: userData
        )
    }
}

private func supervimEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    _ = proxy
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let box = Unmanaged<EventTapBox>.fromOpaque(userInfo).takeUnretainedValue()
    return box.receive(type: type, event: event)
}
#endif

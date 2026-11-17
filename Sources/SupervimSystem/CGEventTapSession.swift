#if os(macOS)
import CoreGraphics
import Foundation

public enum EventTapError: Error, Equatable, Sendable {
    case creationFailed
}

/// Installs a session event tap and forwards key records to `EventTapWiring`.
/// The menu-bar app does not start this. The focus scanner is not wired yet.
/// A known, non-editable cache would swallow commands before the app performs
/// them, which drops keystrokes. Leave the tap uninstalled until that cache is real.
public final class CGEventTapSession: EventTapInstalling, @unchecked Sendable {
    private let box: EventTapBox
    private let lock = NSLock()
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?

    public init(wiring: EventTapWiring) {
        box = EventTapBox(wiring: wiring)
    }

    public func install() throws {
        lock.lock()
        defer { lock.unlock() }
        if port != nil {
            return
        }
        let eventMask = eventBit(.keyDown) | eventBit(.keyUp) | eventBit(.flagsChanged)
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
        let loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, createdSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        port = created
        source = createdSource
        runLoop = loop
        box.setPort(created)
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
        box.setPort(nil)
        if let source, let runLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        source = nil
        port = nil
        runLoop = nil
    }

    private func eventBit(_ type: CGEventType) -> CGEventMask {
        CGEventMask(1) << CGEventMask(type.rawValue)
    }
}

private final class EventTapBox: @unchecked Sendable {
    let wiring: EventTapWiring
    private let lock = NSLock()
    private var port: CFMachPort?

    init(wiring: EventTapWiring) {
        self.wiring = wiring
    }

    func setPort(_ port: CFMachPort?) {
        lock.lock()
        self.port = port
        lock.unlock()
    }

    func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let current = port
            lock.unlock()
            if let current {
                CGEvent.tapEnable(tap: current, enable: true)
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

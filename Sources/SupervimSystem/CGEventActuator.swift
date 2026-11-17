#if canImport(CoreGraphics) && canImport(ApplicationServices)
import ApplicationServices
import CoreGraphics
import Foundation
import SupervimCore

/// Accessibility operations the wheel and mouse events cannot express.
/// A plain click uses `kAXPressAction` when the element supports it.
/// Command-click does not: AXPress cannot hold Command, and it is not a right click.
/// Focus scrolls and edge scrolls set the scroll bar's `AXValue`.
/// A missing element or a missing attribute does nothing. It does not substitute a wheel event.
public protocol AccessibilityManipulating: AnyObject, Sendable {
    /// `false` means the element is missing or `AXPress` returned an error.
    func press(elementID: String) -> Bool
    func nudgeScrollBar(elementID: String, direction: ScrollDirection, pixels: Int, scrollRange: Double)
    func scrollBarToEdge(elementID: String, direction: ScrollDirection)
}

/// Holds accessibility elements registered by a later scanner.
/// Identifiers are the same strings carried on actuator effects.
public final class AXElementStore: AccessibilityManipulating, @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [String: AXUIElement] = [:]

    public init() {}

    public func bind(_ element: AXUIElement, identifier: String) {
        lock.lock()
        elements[identifier] = element
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        elements.removeAll()
        lock.unlock()
    }

    public func press(elementID: String) -> Bool {
        guard let element = element(for: elementID) else {
            return false
        }
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return false
        }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    public func nudgeScrollBar(
        elementID: String,
        direction: ScrollDirection,
        pixels: Int,
        scrollRange: Double
    ) {
        guard pixels > 0, scrollRange.isFinite, scrollRange > 0 else {
            return
        }
        guard let element = element(for: elementID), let bar = scrollBar(element, direction: direction) else {
            return
        }
        guard let current = copyDouble(bar, kAXValueAttribute as CFString) else {
            return
        }
        let minValue = copyDouble(bar, kAXMinValueAttribute as CFString) ?? 0
        let maxValue = copyDouble(bar, kAXMaxValueAttribute as CFString) ?? 1
        let span = maxValue - minValue
        guard span.isFinite, span > 0 else {
            return
        }
        let delta = Double(pixels) / scrollRange * span
        let signed: Double
        switch direction {
        case .down, .right:
            signed = delta
        case .up, .left:
            signed = -delta
        }
        let next = min(max(current + signed, minValue), maxValue)
        setDouble(bar, kAXValueAttribute as CFString, next)
    }

    public func scrollBarToEdge(elementID: String, direction: ScrollDirection) {
        guard let element = element(for: elementID), let bar = scrollBar(element, direction: direction) else {
            return
        }
        let minValue = copyDouble(bar, kAXMinValueAttribute as CFString) ?? 0
        let maxValue = copyDouble(bar, kAXMaxValueAttribute as CFString) ?? 1
        let target: Double
        switch direction {
        case .up, .left:
            target = minValue
        case .down, .right:
            target = maxValue
        }
        setDouble(bar, kAXValueAttribute as CFString, target)
    }

    private func element(for identifier: String) -> AXUIElement? {
        lock.lock()
        defer { lock.unlock() }
        return elements[identifier]
    }

    private func scrollBar(_ element: AXUIElement, direction: ScrollDirection) -> AXUIElement? {
        let attribute: CFString
        switch direction {
        case .up, .down:
            attribute = kAXVerticalScrollBarAttribute as CFString
        case .left, .right:
            attribute = kAXHorizontalScrollBarAttribute as CFString
        }
        return copyElement(element, attribute)
    }

    private func copyElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func copyDouble(_ element: AXUIElement, _ attribute: CFString) -> Double? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        guard let number = value as? NSNumber else {
            return nil
        }
        return number.doubleValue
    }

    private func setDouble(_ element: AXUIElement, _ attribute: CFString, _ number: Double) {
        _ = AXUIElementSetAttributeValue(element, attribute, NSNumber(value: number))
    }
}

extension AXElementStore: EdgeScrollBars {
    public func bar(elementID: String, direction: ScrollDirection) -> EdgeBar? {
        guard let element = element(for: elementID), let scroll = scrollBar(element, direction: direction) else {
            return nil
        }
        guard let value = copyDouble(scroll, kAXValueAttribute as CFString) else {
            return nil
        }
        let minimum = copyDouble(scroll, kAXMinValueAttribute as CFString) ?? 0
        let maximum = copyDouble(scroll, kAXMaxValueAttribute as CFString) ?? 1
        return EdgeBar(
            value: value,
            minimum: minimum,
            maximum: maximum,
            settable: attributeIsSettable(scroll, kAXValueAttribute as CFString)
        )
    }

    public func writeBar(elementID: String, direction: ScrollDirection, value: Double) -> Double? {
        guard let element = element(for: elementID), let scroll = scrollBar(element, direction: direction) else {
            return nil
        }
        guard AXUIElementSetAttributeValue(scroll, kAXValueAttribute as CFString, NSNumber(value: value)) == .success else {
            return nil
        }
        return copyDouble(scroll, kAXValueAttribute as CFString)
    }

    private func attributeIsSettable(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }
}

/// Posts marked Quartz events. The event tap ignores this source user data,
/// so a synthesized shortcut is not parsed as another Supervim command.
/// Unit tests must not construct this type: constructing it can move the pointer.
public final class CGEventActuatorPoster: ActuatorPosting, @unchecked Sendable {
    private let accessibility: any AccessibilityManipulating

    public init(accessibility: any AccessibilityManipulating = AXElementStore()) {
        self.accessibility = accessibility
    }

    public func post(_ effect: ActuatorEffect) {
        switch effect {
        case .accessibilityPress(let elementID, let fallback):
            if !accessibility.press(elementID: elementID) {
                postLeftClick(at: fallback, modifiers: [])
            }
        case .mouseClick(let point, _, let modifiers):
            postLeftClick(at: point, modifiers: modifiers)
        case .pointerScroll(_, _, _, let location, let horizontal, let vertical):
            postWheel(horizontal: horizontal, vertical: vertical, at: location)
        case .edgeScroll:
            break
        case .scrollBarEdge:
            break
        case .focusScroll(let targetID, let direction, let amount, let pixels, let scrollRange):
            if case .edge = amount {
                accessibility.scrollBarToEdge(elementID: targetID, direction: direction)
            } else if let scrollRange {
                accessibility.nudgeScrollBar(
                    elementID: targetID,
                    direction: direction,
                    pixels: pixels,
                    scrollRange: scrollRange
                )
            }
        case .shortcut(let combo):
            postShortcut(combo)
        }
    }

    private func postLeftClick(at point: ActuatorPoint, modifiers: KeyModifiers) {
        let location = CGPoint(x: point.x, y: point.y)
        let source = makeSource()
        guard let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: location,
            mouseButton: .left
        ), let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else {
            return
        }
        let flags = eventFlags(modifiers)
        down.flags = flags
        up.flags = flags
        stamp(down)
        stamp(up)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func postWheel(horizontal: Int, vertical: Int, at point: ActuatorPoint) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: makeSource(),
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(clamping: vertical),
            wheel2: Int32(clamping: horizontal),
            wheel3: 0
        ) else {
            return
        }
        event.location = CGPoint(x: point.x, y: point.y)
        stamp(event)
        event.post(tap: .cghidEventTap)
    }

    private func postShortcut(_ combo: KeyCombo) {
        guard let keyCode = SystemKeyTranslation.virtualKeyCode(forUnshifted: combo.character) else {
            return
        }
        let source = makeSource()
        let virtualKey = CGKeyCode(keyCode)
        guard let down = keyboardEvent(source: source, virtualKey: virtualKey, kind: .keyDown),
              let up = keyboardEvent(source: source, virtualKey: virtualKey, kind: .keyUp)
        else {
            return
        }
        let flags = eventFlags(combo.modifiers)
        down.flags = flags
        up.flags = flags
        stamp(down)
        stamp(up)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func keyboardEvent(source: CGEventSource?, virtualKey: CGKeyCode, kind: CGEventType) -> CGEvent? {
        let isDown = kind == .keyDown
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: isDown) else {
            return nil
        }
        event.type = kind
        return event
    }

    private func makeSource() -> CGEventSource? {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return nil
        }
        source.userData = SynthesizedEventMark.userData
        return source
    }

    private func stamp(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: SynthesizedEventMark.userData)
    }

    private func eventFlags(_ modifiers: KeyModifiers) -> CGEventFlags {
        var flags = CGEventFlags()
        if modifiers.contains(.shift) {
            flags.insert(.maskShift)
        }
        if modifiers.contains(.control) {
            flags.insert(.maskControl)
        }
        if modifiers.contains(.option) {
            flags.insert(.maskAlternate)
        }
        if modifiers.contains(.command) {
            flags.insert(.maskCommand)
        }
        return flags
    }
}
#endif

import Foundation
import SupervimCore

public struct ActuatorPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ActuatorRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Inclusive on every edge. A non-positive size contains nothing.
    /// Non-finite coordinates contain nothing.
    public func contains(_ point: ActuatorPoint) -> Bool {
        guard width > 0, height > 0, point.x.isFinite, point.y.isFinite else {
            return false
        }
        return point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
    }
}

/// One accessibility scroll area the caller already found.
/// `depth` is larger for a more deeply nested area.
/// `travel*` is the remaining distance in that direction, in points.
/// Zero or less means that edge is already reached.
/// `contentWidth` / `contentHeight` are the full scrolled size.
/// Nil means the caller does not know it.
public struct ScrollArea: Equatable, Sendable {
    public var identifier: String
    public var frame: ActuatorRect
    public var depth: Int
    public var containsPointer: Bool
    public var isFocusContainer: Bool
    public var visibleWidth: Double
    public var visibleHeight: Double
    public var travelLeft: Double
    public var travelDown: Double
    public var travelUp: Double
    public var travelRight: Double
    public var contentWidth: Double?
    public var contentHeight: Double?
    /// Accessibility role copied with the area. Nil for callers that do not know it.
    public var role: String?
    /// The focused text input. Content scroll does not use it as the wheel target.
    public var isTextInput: Bool

    public init(
        identifier: String,
        frame: ActuatorRect,
        depth: Int,
        containsPointer: Bool,
        isFocusContainer: Bool,
        visibleWidth: Double,
        visibleHeight: Double,
        travelLeft: Double,
        travelDown: Double,
        travelUp: Double,
        travelRight: Double,
        contentWidth: Double?,
        contentHeight: Double?,
        role: String? = nil,
        isTextInput: Bool = false
    ) {
        self.identifier = identifier
        self.frame = frame
        self.depth = depth
        self.containsPointer = containsPointer
        self.isFocusContainer = isFocusContainer
        self.visibleWidth = visibleWidth
        self.visibleHeight = visibleHeight
        self.travelLeft = travelLeft
        self.travelDown = travelDown
        self.travelUp = travelUp
        self.travelRight = travelRight
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
        self.role = role
        self.isTextInput = isTextInput
    }
}

public struct ActuationContext: Equatable, Sendable {
    public var bundleIdentifier: String
    public var pointer: ActuatorPoint?
    public var scrollAreas: [ScrollArea]
    /// Front window in accessibility points.
    public var windowFrame: ActuatorRect?
    /// `AXScrollArea` / `AXWebArea` frames with no scroll bar to measure.
    public var structuralAreas: [ScrollArea]
    /// The focused text input while Normal is held on it. Scrolls go to the
    /// content around it and never to the input itself.
    public var composerFrame: ActuatorRect?

    public init(
        bundleIdentifier: String,
        pointer: ActuatorPoint? = nil,
        scrollAreas: [ScrollArea] = [],
        windowFrame: ActuatorRect? = nil,
        structuralAreas: [ScrollArea] = [],
        composerFrame: ActuatorRect? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.pointer = pointer
        self.scrollAreas = scrollAreas
        self.windowFrame = windowFrame
        self.structuralAreas = structuralAreas
        self.composerFrame = composerFrame
    }
}

public enum ClickKind: Equatable, Sendable {
    /// `f`. May use AXPress when the element supports it.
    case plain
    /// `F`. Left click with Command held. Never a context menu.
    case command
}

public struct ClickRequest: Equatable, Sendable {
    public var point: ActuatorPoint
    public var kind: ClickKind
    public var elementID: String?
    public var canAccessibilityPress: Bool

    public init(
        point: ActuatorPoint,
        kind: ClickKind,
        elementID: String? = nil,
        canAccessibilityPress: Bool = false
    ) {
        self.point = point
        self.kind = kind
        self.elementID = elementID
        self.canAccessibilityPress = canAccessibilityPress
    }
}

/// The actuator posts left clicks only. `F` is not a right-click.
public enum MouseButton: Equatable, Sendable {
    case left
}

public enum ActuatorEffect: Equatable, Sendable {
    /// `fallback` is the accessibility-frame center. The poster uses it only
    /// when `AXPress` is missing or returns an error.
    case accessibilityPress(elementID: String, fallback: ActuatorPoint)
    case mouseClick(point: ActuatorPoint, button: MouseButton, modifiers: KeyModifiers)
    /// Pixel wheel event aimed at the pointer. Positive vertical is up.
    /// Positive horizontal is to the right. Same sign as a Quartz scroll wheel.
    case pointerScroll(
        targetID: String,
        direction: ScrollDirection,
        amount: ScrollAmount,
        location: ActuatorPoint,
        horizontal: Int,
        vertical: Int
    )
    /// Accessibility scroll-bar change for a focus target, or for an edge.
    /// `pixels` is the magnitude. `scrollRange` is content size minus visible
    /// size. Nil means jump to the edge instead of nudging by pixels.
    case focusScroll(
        targetID: String,
        direction: ScrollDirection,
        amount: ScrollAmount,
        pixels: Int,
        scrollRange: Double?
    )
    case shortcut(KeyCombo)
    /// `gg` / `G`. Resolved before posting: either `scrollBarEdge` or wheels.
    case edgeScroll(
        targetID: String,
        direction: ScrollDirection,
        location: ActuatorPoint,
        role: String?
    )
    /// The vertical or horizontal bar was set to this edge. No key is typed.
    case scrollBarEdge(targetID: String, direction: ScrollDirection, value: Double)
    /// Puts the pointer here before a wheel. macOS routes a wheel event by
    /// where the pointer is, not by the location written on the event.
    case pointerMove(to: ActuatorPoint)
}

public enum ActuatorOutcome: Equatable, Sendable {
    case performed([ActuatorEffect])
    case passedThrough
    case notActuatorWork
}

/// Bundle ids for the apps where yy, history, and tab shortcuts are promised.
///
/// Decision, not confirmed by the owner. The spec names Safari and Chromium
/// and does not list bundle identifiers. Chromium-family here is Chrome,
/// Chromium, Edge, Brave, Arc, and Vivaldi. Firefox and Opera are not included.
/// Comparison is exact: case and surrounding spaces are significant.
public enum PromisedApplications {
    public static let browserBundleIdentifiers: [String] = [
        "com.apple.Safari",
        "com.google.Chrome",
        "org.chromium.Chromium",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi",
    ]

    public static func isPromisedBrowser(_ bundleIdentifier: String) -> Bool {
        browserBundleIdentifiers.contains(bundleIdentifier)
    }
}

/// Mark on every event the actuator synthesizes.
/// The event tap passes a record with this source user data through and does
/// not parse it. ASCII "SVM1".
public enum SynthesizedEventMark {
    public static let userData: Int64 = 0x5356_4D31
}

public protocol ActuatorPosting: AnyObject, Sendable {
    func post(_ effect: ActuatorEffect)
}

/// Where Normal `j` / `k` should wheel while the caret is still in a text input.
///
/// The focused input is not a target. Prefer an `AXScrollArea` or `AXWebArea`
/// under the pointer. Otherwise use the largest remaining area that can move.
/// The wheel location is that area's center, so the event hits the history
/// instead of the composer under the pointer.
public struct ContentScrollAim: Equatable, Sendable {
    public var area: ScrollArea
    public var location: ActuatorPoint

    public init(area: ScrollArea, location: ActuatorPoint) {
        self.area = area
        self.location = location
    }
}

public enum ContentScroll {
    public static func aim(
        areas: [ScrollArea],
        pointer: ActuatorPoint?,
        excludedFrame: ActuatorRect?,
        direction: ScrollDirection
    ) -> ContentScrollAim? {
        let candidates = areas.filter { area in
            travel(area, direction) > 0 && !isFocusedInput(area, excludedFrame)
        }
        let hovered = candidates.filter { area in
            isContentRole(area.role) && contains(area.frame, pointer)
        }
        guard let chosen = bestHovered(hovered) ?? largest(candidates) else {
            return nil
        }
        return ContentScrollAim(area: chosen, location: center(chosen.frame))
    }

    private static func isContentRole(_ role: String?) -> Bool {
        role == "AXScrollArea" || role == "AXWebArea"
    }

    private static func contains(_ frame: ActuatorRect, _ pointer: ActuatorPoint?) -> Bool {
        guard let pointer else {
            return false
        }
        return frame.contains(pointer)
    }

    /// An area about the same size as the focused input, and sitting on it,
    /// is the composer. A much larger parent that happens to contain the caret
    /// is the history and stays eligible.
    static func isFocusedInput(_ area: ScrollArea, _ focus: ActuatorRect?) -> Bool {
        if area.isTextInput {
            return true
        }
        guard let focus, focus.width > 0, focus.height > 0 else {
            return false
        }
        guard area.frame.width > 0, area.frame.height > 0 else {
            return false
        }
        let areaSize = area.frame.width * area.frame.height
        let focusSize = focus.width * focus.height
        guard areaSize.isFinite, focusSize.isFinite, areaSize > 0, focusSize > 0 else {
            return false
        }
        if areaSize > focusSize * 2 {
            return false
        }
        let areaCenter = ActuatorPoint(
            x: area.frame.x + area.frame.width / 2,
            y: area.frame.y + area.frame.height / 2
        )
        if focus.contains(areaCenter) {
            return true
        }
        let focusCenter = ActuatorPoint(x: focus.x + focus.width / 2, y: focus.y + focus.height / 2)
        return area.frame.contains(focusCenter)
    }

    private static func bestHovered(_ areas: [ScrollArea]) -> ScrollArea? {
        areas.max { lhs, rhs in
            if lhs.depth != rhs.depth {
                return lhs.depth < rhs.depth
            }
            let left = areaSize(lhs)
            let right = areaSize(rhs)
            if left != right {
                return left < right
            }
            return lhs.identifier > rhs.identifier
        }
    }

    private static func largest(_ areas: [ScrollArea]) -> ScrollArea? {
        areas.max { lhs, rhs in
            let left = areaSize(lhs)
            let right = areaSize(rhs)
            if left != right {
                return left < right
            }
            return lhs.identifier > rhs.identifier
        }
    }

    private static func areaSize(_ area: ScrollArea) -> Double {
        let size = area.frame.width * area.frame.height
        return size.isFinite && size > 0 ? size : 0
    }

    private static func center(_ frame: ActuatorRect) -> ActuatorPoint {
        ActuatorPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
    }

    private static func travel(_ area: ScrollArea, _ direction: ScrollDirection) -> Double {
        switch direction {
        case .left:
            return area.travelLeft
        case .down:
            return area.travelDown
        case .up:
            return area.travelUp
        case .right:
            return area.travelRight
        }
    }
}

/// One scrollbar the edge-scroll strategy can read and, when settable, write.
public struct EdgeBar: Equatable, Sendable {
    public var value: Double
    public var minimum: Double
    public var maximum: Double
    public var settable: Bool

    public init(value: Double, minimum: Double, maximum: Double, settable: Bool) {
        self.value = value
        self.minimum = minimum
        self.maximum = maximum
        self.settable = settable
    }
}

public protocol EdgeScrollBars: AnyObject, Sendable {
    func bar(elementID: String, direction: ScrollDirection) -> EdgeBar?
    /// The value read back after the write. Nil when the write is refused.
    func writeBar(elementID: String, direction: ScrollDirection, value: Double) -> Double?
}

public struct EdgeScrollReport: Equatable, Sendable {
    public var sequence: String
    public var command: String
    public var role: String
    public var targetID: String
    public var strategy: String
    public var result: String
    public var value: Double?

    public init(
        sequence: String,
        command: String,
        role: String,
        targetID: String,
        strategy: String,
        result: String,
        value: Double?
    ) {
        self.sequence = sequence
        self.command = command
        self.role = role
        self.targetID = targetID
        self.strategy = strategy
        self.result = result
        self.value = value
    }

    public var logLine: String {
        EdgeScroll.logLine(
            sequence: sequence,
            command: command,
            role: role,
            target: targetID,
            strategy: strategy,
            result: result
        )
    }
}

/// `gg` / `G` scroll to an edge.
///
/// The area is the one `j` / `k` would use. A settable bar is written to its
/// minimum or maximum. The write counts only when the value read back is that
/// edge. Otherwise large wheel events are posted at the area center. A bar
/// that is not settable does not stop the wheels when its value sits still,
/// because web areas often ignore `AXValue` and do not update it for a
/// synthetic wheel. No Home, End, or arrow key is posted.
public enum EdgeScroll {
    public static let wheelPixels = 50_000
    public static let maxBursts = 30
    public static let unobservedBursts = 8

    public static func names(for direction: ScrollDirection) -> (sequence: String, command: String) {
        switch direction {
        case .up:
            return ("gg", "scrollToTop")
        case .down:
            return ("G", "scrollToBottom")
        case .left:
            return ("edge-left", "scrollToLeftEdge")
        case .right:
            return ("edge-right", "scrollToRightEdge")
        }
    }

    public static func logLine(
        sequence: String,
        command: String,
        role: String,
        target: String,
        strategy: String,
        result: String
    ) -> String {
        "scroll-edge sequence=\(sequence) command=\(command) role=\(role) target=\(target) strategy=\(strategy) result=\(result)"
    }

    public static func perform(
        targetID: String,
        direction: ScrollDirection,
        role: String?,
        sequence: String,
        command: String,
        bars: (any EdgeScrollBars)?,
        postWheel: (Int, Int) -> Void
    ) -> EdgeScrollReport {
        let roleText = displayed(role)
        func finish(strategy: String, result: String, value: Double?) -> EdgeScrollReport {
            let made = EdgeScrollReport(
                sequence: sequence,
                command: command,
                role: roleText,
                targetID: targetID,
                strategy: strategy,
                result: result,
                value: value
            )
            ModeTrace.noteLine(made.logLine)
            return made
        }

        let initial = bars?.bar(elementID: targetID, direction: direction)
        if let initial, atEdge(initial, direction: direction) {
            return finish(strategy: "scrollBarValue", result: "alreadyAtEdge", value: edgeValue(initial, direction: direction))
        }
        if let initial, initial.settable, let target = edgeValue(initial, direction: direction),
           let written = bars?.writeBar(elementID: targetID, direction: direction, value: target) {
            var after = initial
            after.value = written
            if atEdge(after, direction: direction) {
                return finish(strategy: "scrollBarValue", result: "atEdge", value: target)
            }
        }

        let signed = wheelDelta(direction)
        if bars == nil || !usable(initial) {
            for _ in 0..<unobservedBursts {
                postWheel(signed.horizontal, signed.vertical)
            }
            return finish(strategy: "wheel", result: "unobserved", value: nil)
        }
        let trust = initial?.settable == true
        let limit = trust ? maxBursts : unobservedBursts
        var previous = initial?.value
        var sawChange = false
        for _ in 0..<limit {
            postWheel(signed.horizontal, signed.vertical)
            guard let next = bars?.bar(elementID: targetID, direction: direction), usable(next) else {
                if trust {
                    return finish(strategy: "wheel", result: sawChange ? "moved" : "unchanged", value: nil)
                }
                continue
            }
            if atEdge(next, direction: direction) {
                return finish(
                    strategy: "wheel",
                    result: "atEdge",
                    value: edgeValue(next, direction: direction)
                )
            }
            if let previous, !changed(from: previous, to: next.value, bar: next) {
                if trust {
                    return finish(strategy: "wheel", result: sawChange ? "moved" : "unchanged", value: next.value)
                }
            } else {
                sawChange = true
            }
            previous = next.value
        }
        return finish(strategy: "wheel", result: sawChange ? "moved" : "unobserved", value: nil)
    }

    private static func wheelDelta(_ direction: ScrollDirection) -> (horizontal: Int, vertical: Int) {
        switch direction {
        case .left:
            return (-wheelPixels, 0)
        case .right:
            return (wheelPixels, 0)
        case .up:
            return (0, wheelPixels)
        case .down:
            return (0, -wheelPixels)
        }
    }

    private static func displayed(_ role: String?) -> String {
        guard let role, !role.isEmpty else {
            return "-"
        }
        return role
    }

    private static func usable(_ bar: EdgeBar?) -> Bool {
        guard let bar, bar.value.isFinite, bar.minimum.isFinite, bar.maximum.isFinite else {
            return false
        }
        let span = bar.maximum - bar.minimum
        return span.isFinite && span > 0
    }

    private static func edgeValue(_ bar: EdgeBar, direction: ScrollDirection) -> Double? {
        guard usable(bar) else {
            return nil
        }
        switch direction {
        case .up, .left:
            return bar.minimum
        case .down, .right:
            return bar.maximum
        }
    }

    private static func atEdge(_ bar: EdgeBar, direction: ScrollDirection) -> Bool {
        guard let target = edgeValue(bar, direction: direction) else {
            return false
        }
        let span = bar.maximum - bar.minimum
        let slack = max(span * 0.002, 0.0001)
        return abs(bar.value - target) <= slack
    }

    private static func changed(from previous: Double, to next: Double, bar: EdgeBar) -> Bool {
        let span = bar.maximum - bar.minimum
        let slack = max(span * 0.0005, 0.0001)
        return abs(next - previous) > slack
    }
}

/// Turns CommandMap actions into click, scroll, and shortcut effects.
/// The recording poster in tests is the stand-in for the system poster.
///
/// Planning reads only the context it is given. With a `deferral` scheduler
/// the outcome is returned as soon as the plan exists, and the scroll-bar
/// reads, the accessibility press and the event posts run on that scheduler.
/// The key hook uses that form. Without one, everything happens in the call.
public final class ActionActuator: @unchecked Sendable {
    private let poster: any ActuatorPosting
    private let edgeBars: (any EdgeScrollBars)?
    private let deferral: (any WorkScheduling)?

    public init(
        poster: any ActuatorPosting,
        edgeBars: (any EdgeScrollBars)? = nil,
        deferral: (any WorkScheduling)? = nil
    ) {
        self.poster = poster
        self.edgeBars = edgeBars
        self.deferral = deferral
    }

    public func perform(_ action: Action, context: ActuationContext) -> ActuatorOutcome {
        switch plan(action, context: context) {
        case .notActuatorWork:
            return .notActuatorWork
        case .pass:
            return .passedThrough
        case .effects(let effects):
            guard let deferral else {
                return .performed(post(effects))
            }
            deferral.run { [self] in
                _ = post(effects)
            }
            return .performed(effects)
        }
    }

    @discardableResult
    private func post(_ effects: [ActuatorEffect]) -> [ActuatorEffect] {
        let watch = TraceStopwatch()
        let resolved = resolve(effects)
        for effect in resolved {
            poster.post(effect)
        }
        if ModeTrace.isEnabled {
            ModeTrace.noteTiming(
                stage: "actuate",
                milliseconds: watch.milliseconds,
                fields: [("effects", "\(resolved.count)"), ("kind", Self.kind(resolved))]
            )
        }
        return resolved
    }

    private static func kind(_ effects: [ActuatorEffect]) -> String {
        guard let last = effects.last else {
            return "none"
        }
        switch last {
        case .accessibilityPress:
            return "press"
        case .mouseClick:
            return "click"
        case .pointerScroll, .focusScroll, .edgeScroll, .scrollBarEdge, .pointerMove:
            return "scroll"
        case .shortcut:
            return "shortcut"
        }
    }

    /// Edge scrolls are not posted as `edgeScroll`. A settable bar becomes one
    /// `scrollBarEdge`, and the pointer stays where it is. Anything else
    /// becomes wheel events at the area center, after the pointer move.
    private func resolve(_ effects: [ActuatorEffect]) -> [ActuatorEffect] {
        var resolved: [ActuatorEffect] = []
        for effect in effects {
            guard case .edgeScroll(let targetID, let direction, let location, let role) = effect else {
                resolved.append(effect)
                continue
            }
            let names = EdgeScroll.names(for: direction)
            var wheels: [ActuatorEffect] = []
            let report = EdgeScroll.perform(
                targetID: targetID,
                direction: direction,
                role: role,
                sequence: names.sequence,
                command: names.command,
                bars: edgeBars
            ) { horizontal, vertical in
                wheels.append(.pointerScroll(
                    targetID: targetID,
                    direction: direction,
                    amount: .edge,
                    location: location,
                    horizontal: horizontal,
                    vertical: vertical
                ))
            }
            if wheels.isEmpty {
                if case .pointerMove? = resolved.last {
                    resolved.removeLast()
                }
                resolved.append(.scrollBarEdge(targetID: targetID, direction: direction, value: report.value ?? 0))
            } else {
                resolved.append(contentsOf: wheels)
            }
        }
        return resolved
    }

    public func click(_ request: ClickRequest) -> ActuatorOutcome {
        guard request.point.x.isFinite, request.point.y.isFinite else {
            return .passedThrough
        }
        let effect = clickEffect(request)
        guard let deferral else {
            _ = post([effect])
            return .performed([effect])
        }
        deferral.run { [self] in
            _ = post([effect])
        }
        return .performed([effect])
    }

    private func clickEffect(_ request: ClickRequest) -> ActuatorEffect {
        switch request.kind {
        case .command:
            return .mouseClick(point: request.point, button: .left, modifiers: .command)
        case .plain:
            if request.canAccessibilityPress, let identifier = trimmed(request.elementID) {
                return .accessibilityPress(elementID: identifier, fallback: request.point)
            }
            return .mouseClick(point: request.point, button: .left, modifiers: [])
        }
    }

    private func trimmed(_ identifier: String?) -> String? {
        guard let identifier else {
            return nil
        }
        let stripped = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    private enum Plan {
        case notActuatorWork
        case pass
        case effects([ActuatorEffect])
    }

    private func plan(_ action: Action, context: ActuationContext) -> Plan {
        switch action {
        case .beginHint, .showHelp, .focusFirstInput, .passNextKey, .escape, .enterInsert:
            return .notActuatorWork
        case .scroll(let direction, let amount):
            guard let aim = ScrollTargeting.aim(context: context, direction: direction),
                  let effects = ScrollTargeting.effects(context: context, direction: direction, amount: amount)
            else {
                ModeTrace.noteLine(ScrollFallback.missLine(direction: direction))
                return .pass
            }
            ModeTrace.noteLine(ScrollTargeting.logLine(aim, direction: direction))
            return .effects(effects)
        case .sendShortcut(let combo):
            if restrictsToPromisedBrowsers(action), !PromisedApplications.isPromisedBrowser(context.bundleIdentifier) {
                return .pass
            }
            guard SystemKeyTranslation.virtualKeyCode(forUnshifted: combo.character) != nil else {
                return .pass
            }
            return .effects([.shortcut(combo)])
        case .sequence(let steps):
            if restrictsToPromisedBrowsers(action), !PromisedApplications.isPromisedBrowser(context.bundleIdentifier) {
                return .pass
            }
            var effects: [ActuatorEffect] = []
            for step in steps {
                switch plan(step, context: context) {
                case .notActuatorWork:
                    return .notActuatorWork
                case .pass:
                    return .pass
                case .effects(let part):
                    effects.append(contentsOf: part)
                }
            }
            return .effects(effects)
        }
    }

    /// yy, history, and tab shortcuts are promised only for the allowlist.
    /// Close, new, reload, and find are not limited to those apps.
    private func restrictsToPromisedBrowsers(_ action: Action) -> Bool {
        switch action {
        case .sendShortcut(let combo):
            return isHistoryOrTab(combo)
        case .sequence(let steps):
            return isCopyURL(steps) || steps.contains(where: restrictsToPromisedBrowsers)
        case .scroll, .beginHint, .showHelp, .focusFirstInput, .passNextKey, .escape, .enterInsert:
            return false
        }
    }

    private func isHistoryOrTab(_ combo: KeyCombo) -> Bool {
        guard combo.character == "[" || combo.character == "]" else {
            return false
        }
        return combo.modifiers == .command || combo.modifiers == [.command, .shift]
    }

    private func isCopyURL(_ steps: [Action]) -> Bool {
        guard steps.count == 2,
              case .sendShortcut(let first) = steps[0],
              case .sendShortcut(let second) = steps[1]
        else {
            return false
        }
        return first == KeyCombo("l", modifiers: .command) && second == KeyCombo("c", modifiers: .command)
    }
}

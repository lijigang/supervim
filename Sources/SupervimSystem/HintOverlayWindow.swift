#if canImport(AppKit)
import AppKit
import QuartzCore
import SupervimCore

/// Transparent hint labels and the shortcut sheet. The panel does not activate
/// the app and does not become key, so the frontmost window keeps focus.
/// Mouse events pass through. Hint coordinates stay in the space the markers
/// already use. This file does not convert them. Help text is centered on the
/// main screen when one exists. Placement on a real display is not measured here.
///
/// The caller is the key hook or the scan queue. It is never made to wait:
/// the drawing is queued on the main thread and the call returns. When
/// several label updates are queued, only the newest is drawn.
///
/// Each screen has one panel and one canvas view, made once and kept. A
/// keystroke gives the canvas a new list of labels and redraws it. Nothing
/// is hidden and shown again in between, so the labels do not flicker.
public final class NonActivatingHintPanel: OverlayPresenting, HelpPresenting, @unchecked Sendable {
    private let tickets = OverlayTickets()

    public init() {}

    public func present(_ presentation: OverlayPresentation) {
        let markers = presentation.markers
        let typedPrefix = presentation.typedPrefix
        let ticket = tickets.next()
        let asked = TraceStopwatch()
        PanelDispatch.perform { [tickets] holder in
            guard tickets.isNewest(ticket) else {
                return
            }
            holder.show(markers, typedPrefix: typedPrefix, queuedMilliseconds: asked.milliseconds)
        }
    }

    public func presentHelp(_ presentation: HelpPresentation) {
        let page = presentation.page
        PanelDispatch.perform { holder in
            holder.showHelp(page)
        }
    }

    public func hideHelp() {
        hideOverlay()
    }

    public func hideOverlay() {
        _ = tickets.next()
        PanelDispatch.perform { holder in
            holder.hideAll()
        }
    }

    /// Makes the first panel and draws one label off screen. The first `f`
    /// after launch then finds the window, the font and the glyphs ready.
    public func prewarm() {
        PanelDispatch.later { holder in
            holder.prewarm()
        }
    }
}

/// Numbers the label updates so a queued one can tell it has been replaced.
private final class OverlayTickets: @unchecked Sendable {
    private let lock = NSLock()
    private var newest = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        newest += 1
        return newest
    }

    func isNewest(_ ticket: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ticket == newest
    }
}

private enum PanelDispatch {
    /// Runs now on the main thread, and otherwise queues there and returns.
    static func perform(_ body: @escaping @MainActor @Sendable (PanelHolder) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                body(PanelRegistry.shared.current())
            }
        } else {
            later(body)
        }
    }

    static func later(_ body: @escaping @MainActor @Sendable (PanelHolder) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                body(PanelRegistry.shared.current())
            }
        }
    }
}

@MainActor
private final class PanelRegistry {
    static let shared = PanelRegistry()
    private var holder: PanelHolder?

    func current() -> PanelHolder {
        if let holder {
            return holder
        }
        let created = PanelHolder()
        holder = created
        return created
    }
}

@MainActor
private final class PanelHolder {
    let panel: NSPanel
    private var hintPanels: [NSPanel] = []
    private var canvases: [HintCanvasView] = []
    private var sizes: [String: NSSize] = [:]
    /// Read once. `classic` unless the user set `HintLabelStyle.defaultsKey`.
    private let style: HintLabelStyle
    /// Targets of the hint pass on screen, kept from the keystroke that
    /// showed all of them. Placement reads them while a prefix is typed, so
    /// the labels that remain do not move.
    private var passTargets: [HintRect] = []

    init() {
        panel = Self.makePanel()
        style = HintLabelStyle.preferred()
    }

    func hideAll() {
        panel.orderOut(nil)
        hideHints(from: 0)
        passTargets.removeAll(keepingCapacity: true)
    }

    private func hideHints(from first: Int) {
        for index in hintPanels.indices where index >= first {
            if hintPanels[index].isVisible {
                hintPanels[index].orderOut(nil)
            }
            canvases[index].replace([], typedPrefix: "")
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        return panel
    }

    private func ensureHintPanels(_ count: Int) {
        while hintPanels.count < count {
            let created = Self.makePanel()
            let canvas = HintCanvasView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            canvas.autoresizingMask = [.width, .height]
            canvas.style = style
            created.contentView = canvas
            hintPanels.append(created)
            canvases.append(canvas)
        }
    }

    private func badgeSize(_ label: String) -> NSSize {
        if let known = sizes[label] {
            return known
        }
        if sizes.count > 4_000 {
            sizes.removeAll(keepingCapacity: true)
        }
        let measured = HintLabelRenderer.size(for: label, style: style)
        sizes[label] = measured
        return measured
    }

    func prewarm() {
        ensureHintPanels(1)
        let size = badgeSize("AS")
        let canvas = HintCanvasView(frame: NSRect(origin: .zero, size: size))
        canvas.style = style
        canvas.replace([HintCanvasView.Badge(label: "AS", frame: canvas.bounds)], typedPrefix: "a")
        if let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) {
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        }
    }

    func show(_ markers: [HintMarker], typedPrefix: String = "", queuedMilliseconds: Double = 0) {
        let watch = TraceStopwatch()
        let tracing = ModeTrace.isEnabled
        let screens = NSScreen.screens.map { screen in
            DisplayFrame(
                x: screen.frame.origin.x,
                y: screen.frame.origin.y,
                width: screen.frame.width,
                height: screen.frame.height,
                backingScale: Double(screen.backingScaleFactor)
            )
        }
        if tracing {
            for (index, screen) in screens.enumerated() {
                ModeTrace.noteLine(ModeTrace.formatHintPlace(screen: screen, index: index))
            }
        }
        if style.spec.pointer == .caret, typedPrefix.isEmpty || passTargets.isEmpty {
            passTargets = markers.map(HintOverlayLayout.element(of:))
        }
        let arrangement = HintOverlayLayout.arrange(
            markers: markers,
            style: style,
            screens: screens,
            neighbours: passTargets
        ) { text in
            let size = badgeSize(text)
            return HintBadgeSize(width: Double(size.width), height: Double(size.height))
        }
        if tracing {
            for label in arrangement.labels {
                ModeTrace.noteLine(
                    ModeTrace.formatHintLabel(index: label.markerIndex, ax: label.element, ns: label.placed)
                )
            }
        }
        let labels = arrangement.labels
        let groups = arrangement.panels
        ensureHintPanels(groups.count)
        for (slot, group) in groups.enumerated() {
            let hintPanel = hintPanels[slot]
            let canvas = canvases[slot]
            var badges: [HintCanvasView.Badge] = []
            badges.reserveCapacity(group.items.count)
            for item in group.items where labels.indices.contains(item.sourceIndex) {
                let label = labels[item.sourceIndex]
                badges.append(HintCanvasView.Badge(
                    label: label.text,
                    frame: NSRect(
                        x: CGFloat(item.local.x),
                        y: CGFloat(item.local.y),
                        width: CGFloat(item.local.width),
                        height: CGFloat(item.local.height)
                    ),
                    tipX: label.box.tipX.map { CGFloat($0 - group.frame.x) },
                    tailDown: label.box.tailDown
                ))
            }
            let frame = NSRect(
                x: CGFloat(group.frame.x),
                y: CGFloat(group.frame.y),
                width: CGFloat(group.frame.width),
                height: CGFloat(group.frame.height)
            )
            if hintPanel.frame != frame {
                hintPanel.setFrame(frame, display: false)
            }
            canvas.replace(badges, typedPrefix: typedPrefix)
            hintPanel.displayIfNeeded()
            if tracing {
                ModeTrace.noteLine(ModeTrace.formatHintPanel(
                    screen: group.screenIndex,
                    scale: group.backingScale,
                    frame: group.frame
                ))
            }
            reveal(hintPanel, duration: ChromeMotion.hintAppearDuration(
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ))
        }
        hideHints(from: groups.count)
        ModeTrace.noteTiming(
            stage: "overlay",
            milliseconds: watch.milliseconds,
            fields: [
                ("labels", "\(labels.count)"),
                ("panels", "\(groups.count)"),
                ("queued_ms", String(format: "%.1f", queuedMilliseconds)),
            ]
        )
    }

    func showHelp(_ page: HelpPage) {
        guard !page.entries.isEmpty else {
            panel.orderOut(nil)
            return
        }
        let content = HelpSheetView(page: page)
        let size = content.bounds.size
        panel.hasShadow = true
        panel.contentView = content
        var frame = NSRect(x: 80, y: 80, width: size.width, height: size.height)
        if let visible = FloatingScreen.underMouse()?.visibleFrame {
            let maxX = max(visible.minX + 12, visible.maxX - size.width - 12)
            let maxY = max(visible.minY + 12, visible.maxY - size.height - 12)
            frame.origin.x = min(max(visible.midX - size.width / 2, visible.minX + 12), maxX)
            frame.origin.y = min(max(visible.midY - size.height / 2, visible.minY + 12), maxY)
        }
        panel.setFrame(frame, display: true)
        if panel.isVisible {
            panel.alphaValue = 1
        }
        reveal(panel, duration: ChromeMotion.appearDuration(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ))
    }

    /// Fades a panel in when it was hidden. A panel that is already showing
    /// is left as it is, so typing a hint does not replay the fade. Reduce
    /// Motion shows the panel at once.
    private func reveal(_ target: NSPanel, duration: Double) {
        if target.isVisible {
            if target.alphaValue < 1, duration == 0 {
                target.alphaValue = 1
            }
            return
        }
        if duration == 0 {
            target.alphaValue = 1
            target.orderFrontRegardless()
            return
        }
        target.alphaValue = 0
        target.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            target.animator().alphaValue = 1
        }
    }
}
#endif

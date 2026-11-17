#if canImport(AppKit)
import AppKit
import QuartzCore
import SupervimCore

/// Transparent hint labels and the shortcut sheet. The panel does not activate
/// the app and does not become key, so the frontmost window keeps focus.
/// Mouse events pass through. Hint coordinates stay in the space the markers
/// already use. This file does not convert them. Help text is centered on the
/// main screen when one exists. Placement on a real display is not measured here.
public final class NonActivatingHintPanel: OverlayPresenting, HelpPresenting, @unchecked Sendable {
    public init() {}

    public func present(_ presentation: OverlayPresentation) {
        let markers = presentation.markers
        let typedPrefix = presentation.typedPrefix
        PanelDispatch.perform { holder in
            holder.show(markers, typedPrefix: typedPrefix)
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
        PanelDispatch.perform { holder in
            holder.panel.orderOut(nil)
        }
    }
}

private enum PanelDispatch {
    /// The operation is not stored. A stored closure is escaping, and the
    /// caller’s panel update is not.
    static func perform(_ body: @MainActor (PanelHolder) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                body(PanelRegistry.shared.current())
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    body(PanelRegistry.shared.current())
                }
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

    init() {
        panel = NSPanel(
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
    }

    func show(_ markers: [HintMarker], typedPrefix: String = "") {
        let screens = NSScreen.screens.map { screen in
            DisplayFrame(
                x: screen.frame.origin.x,
                y: screen.frame.origin.y,
                width: screen.frame.width,
                height: screen.frame.height,
                backingScale: Double(screen.backingScaleFactor)
            )
        }
        for (index, screen) in screens.enumerated() {
            ModeTrace.noteLine(ModeTrace.formatHintPlace(screen: screen, index: index))
        }
        let content = NSView(frame: .zero)
        var globals: [HintRect] = []
        var badges: [HintBadgeView] = []
        for marker in markers {
            let element = HintRect(
                x: marker.anchor.x,
                y: marker.anchor.y,
                width: marker.elementWidth,
                height: marker.elementHeight
            )
            let badge = HintBadgeView(label: marker.text, typedPrefix: typedPrefix)
            let size = badge.badgeSize
            let width = Double(size.width)
            let height = Double(size.height)
            guard let placed = HintGeometry.labelRect(
                element: element,
                badgeWidth: width,
                badgeHeight: height,
                screens: screens
            ) else {
                continue
            }
            ModeTrace.noteLine(ModeTrace.formatHintLabel(index: marker.index, ax: element, ns: placed))
            badge.frame = NSRect(
                x: CGFloat(placed.x),
                y: CGFloat(placed.y),
                width: CGFloat(placed.width),
                height: CGFloat(placed.height)
            )
            content.addSubview(badge)
            badges.append(badge)
            globals.append(placed)
        }
        guard let arranged = HintGeometry.arrange(badges: globals), !badges.isEmpty else {
            panel.orderOut(nil)
            return
        }
        for (badge, local) in zip(badges, arranged.local) {
            badge.frame = NSRect(
                x: CGFloat(local.x),
                y: CGFloat(local.y),
                width: CGFloat(local.width),
                height: CGFloat(local.height)
            )
        }
        let frame = arranged.frame
        content.frame = NSRect(x: 0, y: 0, width: CGFloat(frame.width), height: CGFloat(frame.height))
        if #available(macOS 14.0, *) {
            content.clipsToBounds = false
        }
        panel.hasShadow = false
        panel.contentView = content
        panel.setFrame(
            NSRect(
                x: CGFloat(frame.x),
                y: CGFloat(frame.y),
                width: CGFloat(frame.width),
                height: CGFloat(frame.height)
            ),
            display: true
        )
        reveal()
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
        reveal()
    }

    /// Fades the panel in once. Later hint keystrokes replace the labels
    /// without playing the fade again. Reduce Motion shows the sheet at once.
    private func reveal() {
        let duration = ChromeMotion.appearDuration(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let alreadyVisible = panel.isVisible && panel.alphaValue > 0.95
        if duration == 0 || alreadyVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }
}
#endif

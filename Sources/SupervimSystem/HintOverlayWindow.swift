#if canImport(AppKit)
import AppKit
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
        PanelDispatch.perform { holder in
            holder.show(markers)
        }
    }

    public func presentHelp(_ presentation: HelpPresentation) {
        let text = presentation.page.text
        PanelDispatch.perform { holder in
            holder.showHelp(text)
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

    func show(_ markers: [HintMarker]) {
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
        var badges: [NSTextField] = []
        for marker in markers {
            let element = HintRect(
                x: marker.anchor.x,
                y: marker.anchor.y,
                width: marker.elementWidth,
                height: marker.elementHeight
            )
            let badge = badgeField(marker.text)
            let fitted = badge.fittingSize
            let width = max(Double(fitted.width) + 8, 18)
            let height = max(Double(fitted.height) + 4, 16)
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
        panel.orderFrontRegardless()
    }

    func showHelp(_ text: String) {
        guard !text.isEmpty else {
            panel.orderOut(nil)
            return
        }
        let field = NSTextField(wrappingLabelWithString: text)
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = NSColor(srgbRed: 1, green: 0.97, blue: 0.86, alpha: 0.96)
        field.textColor = .black
        field.font = NSFont.systemFont(ofSize: 13)
        let width: CGFloat = 560
        field.preferredMaxLayoutWidth = width - 24
        let fitted = field.fittingSize
        let height = max(fitted.height + 20, 40)
        field.frame = NSRect(x: 12, y: 10, width: width - 24, height: height - 20)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.addSubview(field)
        panel.contentView = content
        var frame = NSRect(x: 80, y: 80, width: width, height: height)
        if let screen = NSScreen.main?.visibleFrame {
            frame.origin.x = screen.midX - width / 2
            frame.origin.y = screen.midY - height / 2
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func badgeField(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = NSColor(srgbRed: 1, green: 0.93, blue: 0.4, alpha: 0.95)
        field.textColor = .black
        field.font = NSFont.boldSystemFont(ofSize: 12)
        field.alignment = .center
        return field
    }
}
#endif

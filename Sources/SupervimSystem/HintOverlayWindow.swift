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
        let content = NSView(frame: .zero)
        var bounds = NSRect.null
        for marker in markers {
            let badge = badgeField(marker.text)
            let fitted = badge.fittingSize
            let width = max(fitted.width + 8, 18)
            let height = max(fitted.height + 4, 16)
            badge.frame = NSRect(x: marker.anchor.x, y: marker.anchor.y, width: width, height: height)
            content.addSubview(badge)
            bounds = bounds.union(badge.frame)
        }
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else {
            panel.orderOut(nil)
            return
        }
        let origin = bounds.origin
        for subview in content.subviews {
            subview.frame.origin.x -= origin.x
            subview.frame.origin.y -= origin.y
        }
        content.frame = NSRect(origin: .zero, size: bounds.size)
        panel.contentView = content
        panel.setFrame(bounds, display: true)
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

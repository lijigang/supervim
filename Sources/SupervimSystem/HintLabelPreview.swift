#if canImport(AppKit)
import AppKit
import SupervimCore

/// Hint labels over a still picture, for the preview tool. The markers go
/// through the overlay's own placement and are drawn by the overlay's own
/// canvas; only the window is missing. The view's bounds stand in for one
/// screen: marker frames are in points from its top-left corner, y down, as
/// accessibility frames are on a real display.
@MainActor
public final class HintLabelPreviewView: NSView {
    public let style: HintLabelStyle
    public let labelCount: Int
    /// Every label's frame, margin included, measured from the view's
    /// top-left corner with y down.
    public let labelFrames: [NSRect]

    /// `pass` is every marker of the hint pass when `markers` are only the
    /// ones left after `typedPrefix`, as the overlay remembers them.
    public init(
        markers: [HintMarker],
        typedPrefix: String,
        style: HintLabelStyle,
        size: NSSize,
        pass: [HintMarker]? = nil
    ) {
        self.style = style
        let screen = DisplayFrame(
            x: 0,
            y: 0,
            width: Double(size.width),
            height: Double(size.height),
            backingScale: 2
        )
        let arrangement = HintOverlayLayout.arrange(
            markers: markers,
            style: style,
            screens: [screen],
            neighbours: (pass ?? markers).map(HintOverlayLayout.element(of:))
        ) { text in
            let measured = HintLabelRenderer.size(for: text, style: style)
            return HintBadgeSize(width: Double(measured.width), height: Double(measured.height))
        }
        self.labelCount = arrangement.labels.count
        self.labelFrames = arrangement.labels.map { label in
            NSRect(
                x: CGFloat(label.box.frame.x),
                y: size.height - CGFloat(label.box.frame.y + label.box.frame.height),
                width: CGFloat(label.box.frame.width),
                height: CGFloat(label.box.frame.height)
            )
        }
        super.init(frame: NSRect(origin: .zero, size: size))
        for group in arrangement.panels {
            let canvas = HintCanvasView(frame: NSRect(
                x: CGFloat(group.frame.x),
                y: CGFloat(group.frame.y),
                width: CGFloat(group.frame.width),
                height: CGFloat(group.frame.height)
            ))
            canvas.style = style
            var badges: [HintCanvasView.Badge] = []
            badges.reserveCapacity(group.items.count)
            for item in group.items where arrangement.labels.indices.contains(item.sourceIndex) {
                let label = arrangement.labels[item.sourceIndex]
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
            canvas.replace(badges, typedPrefix: typedPrefix)
            addSubview(canvas)
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public override var isOpaque: Bool { false }

    /// Size of a label's body in `style`, without the clear margin.
    public static func bodySize(for label: String, style: HintLabelStyle) -> NSSize {
        let frame = HintLabelRenderer.size(for: label, style: style)
        let margin = CGFloat(style.spec.margin)
        return NSSize(width: frame.width - margin * 2, height: frame.height - margin * 2)
    }
}
#endif

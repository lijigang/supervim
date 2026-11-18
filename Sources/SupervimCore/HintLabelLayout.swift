import Foundation

/// One label's frame in AppKit points, and where its pointer goes.
public struct HintLabelBox: Equatable, Sendable {
    /// Body and margin, origin at the bottom-left, y up.
    public var frame: HintRect
    /// Global x of the caret's tip. `nil` when the style has no caret.
    public var tipX: Double?
    /// The label sits above its target and the caret points down.
    public var tailDown: Bool

    public init(frame: HintRect, tipX: Double? = nil, tailDown: Bool = false) {
        self.frame = frame
        self.tipX = tipX
        self.tailDown = tailDown
    }
}

/// One marker after placement.
public struct HintPlacedLabel: Equatable, Sendable {
    /// `HintMarker.index`.
    public var markerIndex: Int
    public var text: String
    /// The target in accessibility points.
    public var element: HintRect
    /// Where placement put the frame, before labels were moved apart.
    public var placed: HintRect
    public var box: HintLabelBox

    public init(markerIndex: Int, text: String, element: HintRect, placed: HintRect, box: HintLabelBox) {
        self.markerIndex = markerIndex
        self.text = text
        self.element = element
        self.placed = placed
        self.box = box
    }
}

/// Every label of one hint pass, and the panels that hold them.
/// `HintPanelItem.sourceIndex` is an index into `labels`.
public struct HintOverlayArrangement: Equatable, Sendable {
    public var labels: [HintPlacedLabel]
    public var panels: [HintPanelPlacement]

    public init(labels: [HintPlacedLabel], panels: [HintPanelPlacement]) {
        self.labels = labels
        self.panels = panels
    }
}

extension HintGeometry {
    /// Frame and pointer of one label.
    ///
    /// Without a caret this is `labelRect`: the frame's top-left is the
    /// target's top-left. A drawn-out corner reaches that same point, so the
    /// frame does not move for it.
    ///
    /// With a caret the tip touches the target and the body hangs below it.
    /// The tip is in the middle of a narrow target and `caretLead` along a
    /// wide one. It is just inside the bottom edge of a short target and at
    /// most `caretDepth` down a tall one, so the label of a tall row stays
    /// inside the row. When the frame would leave the bottom of the screen
    /// the label goes above the target and the caret points down. The frame
    /// is kept on the screen sideways; the tip does not move with it.
    public static func labelBox(
        element: HintRect,
        badgeWidth: Double,
        badgeHeight: Double,
        spec: HintLabelSpec,
        screens: [DisplayFrame]
    ) -> HintLabelBox? {
        guard spec.pointer == .caret else {
            return labelRect(
                element: element,
                badgeWidth: badgeWidth,
                badgeHeight: badgeHeight,
                screens: screens
            ).map { HintLabelBox(frame: $0) }
        }
        guard let primary = screens.first,
              primary.height.isFinite, primary.height > 0,
              element.isUsable,
              badgeWidth.isFinite, badgeHeight.isFinite,
              badgeWidth > 0, badgeHeight > 0
        else {
            return nil
        }
        let tipX = element.x + min(element.width / 2, HintLabelMetrics.caretLead)
        let inset = min(HintLabelMetrics.caretInset, element.height / 4)
        let reach = min(element.height - inset, HintLabelMetrics.caretDepth)
        let gap = max(spec.margin - HintLabelMetrics.caretHeight, 0)
        let screen = screenIndex(containingAX: HintPoint(x: tipX, y: element.y + reach), screens: screens)
            .map { accessibilityFrame(of: screens[$0], primaryHeight: primary.height) }

        var top = element.y + reach - gap
        var tailDown = false
        if let screen, top + badgeHeight > screen.y + screen.height {
            let above = element.y + element.height - reach + gap - badgeHeight
            if above >= screen.y {
                top = above
                tailDown = true
            }
        }
        var left = tipX - badgeWidth / 2
        if let screen {
            let lowest = screen.x - spec.margin + 2
            let highest = screen.x + screen.width - badgeWidth + spec.margin - 2
            if highest >= lowest {
                left = min(max(left, lowest), highest)
            }
        }
        return HintLabelBox(
            frame: HintRect(
                x: left,
                y: primary.height - top - badgeHeight,
                width: badgeWidth,
                height: badgeHeight
            ),
            tipX: tipX,
            tailDown: tailDown
        )
    }

    /// `nudge`, but two labels count as touching only when the rectangles
    /// `slack` inside their frames do. A candidate's frame has a clear margin
    /// around its body, and margins may overlap.
    public static func nudge(_ labels: [HintRect], slack: Double) -> [HintRect] {
        guard slack > 0, slack.isFinite else {
            return nudge(labels)
        }
        let cores = labels.map { label -> HintRect in
            guard label.isUsable, label.width > slack * 2, label.height > slack * 2 else {
                return label
            }
            return HintRect(
                x: label.x + slack,
                y: label.y + slack,
                width: label.width - slack * 2,
                height: label.height - slack * 2
            )
        }
        let moved = nudge(cores)
        guard moved.count == labels.count else {
            return labels
        }
        return labels.indices.map { index in
            var next = labels[index]
            next.x += moved[index].x - cores[index].x
            return next
        }
    }
}

/// Places every marker of a hint pass for one style.
public enum HintOverlayLayout {
    /// `size` returns the frame of a label for its text: body and margin.
    ///
    /// `classic` is placed exactly as before: `labelRect`, then `nudge` on
    /// the whole frames. A candidate is placed with `labelBox`, and its
    /// bodies may come within a point and a half of each other before one
    /// is moved.
    public static func arrange(
        markers: [HintMarker],
        style: HintLabelStyle,
        screens: [DisplayFrame],
        size: (String) -> HintBadgeSize
    ) -> HintOverlayArrangement {
        let spec = style.spec
        var labels: [HintPlacedLabel] = []
        labels.reserveCapacity(markers.count)
        for marker in markers {
            let element = HintRect(
                x: marker.anchor.x,
                y: marker.anchor.y,
                width: marker.elementWidth,
                height: marker.elementHeight
            )
            let badge = size(marker.text)
            guard let box = HintGeometry.labelBox(
                element: element,
                badgeWidth: badge.width,
                badgeHeight: badge.height,
                spec: spec,
                screens: screens
            ) else {
                continue
            }
            labels.append(HintPlacedLabel(
                markerIndex: marker.index,
                text: marker.text,
                element: element,
                placed: box.frame,
                box: box
            ))
        }
        let frames = labels.map(\.box.frame)
        let nudged = style == .classic
            ? HintGeometry.nudge(frames)
            : HintGeometry.nudge(frames, slack: spec.margin + 1.5)
        if nudged.count == labels.count {
            for index in labels.indices {
                labels[index].box.frame = nudged[index]
            }
        }
        let panels = HintGeometry.panels(labels: labels.map(\.box.frame), screens: screens)
        return HintOverlayArrangement(labels: labels, panels: panels)
    }
}

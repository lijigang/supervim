#if canImport(AppKit)
import AppKit
import SupervimCore
import SupervimSystem

enum LabelPreviewError: Error {
    case bitmap
    case png
    case noTypedState(String)
}

/// Offscreen rendering of a view to a bitmap at a chosen pixel density.
@MainActor
enum Raster {
    static func render(_ view: NSView, dark: Bool, scale: CGFloat) throws -> NSBitmapImageRep {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        apply(appearance, to: view)
        let bounds = NSRect(origin: .zero, size: view.bounds.size)
        guard bounds.width >= 1, bounds.height >= 1 else {
            throw LabelPreviewError.bitmap
        }
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        view.frame = bounds
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(Int((bounds.width * scale).rounded()), 1),
            pixelsHigh: max(Int((bounds.height * scale).rounded()), 1),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw LabelPreviewError.bitmap
        }
        rep.size = bounds.size
        if let appearance {
            appearance.performAsCurrentDrawingAppearance {
                view.cacheDisplay(in: bounds, to: rep)
            }
        } else {
            view.cacheDisplay(in: bounds, to: rep)
        }
        window.contentView = nil
        return rep
    }

    static func write(_ rep: NSBitmapImageRep, to url: URL) throws {
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw LabelPreviewError.png
        }
        try data.write(to: url)
    }

    private static func apply(_ appearance: NSAppearance?, to view: NSView) {
        view.appearance = appearance
        for child in view.subviews {
            apply(appearance, to: child)
        }
    }
}

/// A page of pictures and captions. Flipped: y runs down.
@MainActor
final class SheetView: NSView {
    enum Item {
        case fill(NSRect, NSColor, radius: CGFloat)
        case outline(NSRect, NSColor, radius: CGFloat, width: CGFloat)
        /// `source` is in the picture's own points, origin top-left. `nil` is all of it.
        case picture(NSBitmapImageRep, source: NSRect?, dest: NSRect, radius: CGFloat)
        case text(String, NSPoint, NSFont, NSColor)
    }

    private let background: NSColor
    private var items: [Item] = []

    init(size: NSSize, background: NSColor) {
        self.background = background
        super.init(frame: NSRect(origin: .zero, size: size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    func add(_ item: Item) {
        items.append(item)
    }

    @discardableResult
    func addText(_ string: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor) -> CGFloat {
        items.append(.text(string, NSPoint(x: x, y: y), font, color))
        return x + ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    func addTrailingText(_ string: String, right: CGFloat, y: CGFloat, font: NSFont, color: NSColor) {
        let width = ceil((string as NSString).size(withAttributes: [.font: font]).width)
        items.append(.text(string, NSPoint(x: right - width, y: y), font, color))
    }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        bounds.fill()
        for item in items {
            switch item {
            case .fill(let rect, let color, let radius):
                color.setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            case .outline(let rect, let color, let radius, let width):
                let path = NSBezierPath(
                    roundedRect: rect.insetBy(dx: width / 2, dy: width / 2),
                    xRadius: max(radius - width / 2, 0),
                    yRadius: max(radius - width / 2, 0)
                )
                path.lineWidth = width
                color.setStroke()
                path.stroke()
            case .picture(let rep, let source, let dest, let radius):
                var from = NSRect.zero
                if let source {
                    from = NSRect(
                        x: source.minX,
                        y: rep.size.height - source.maxY,
                        width: source.width,
                        height: source.height
                    )
                }
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: dest, xRadius: radius, yRadius: radius).addClip()
                _ = rep.draw(
                    in: dest,
                    from: from,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
                )
                NSGraphicsContext.restoreGraphicsState()
            case .text(let string, let point, let font, let color):
                (string as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
            }
        }
    }
}

/// The three pictures of one style in one appearance, and what was typed
/// to reach the third.
struct StyleShots {
    let browser: NSBitmapImageRep
    let chat: NSBitmapImageRep
    let typed: NSBitmapImageRep
}

/// The labels of the two scenes: before a key, and after the first key of a
/// two-letter label. They do not depend on the style.
@MainActor
struct PreviewLabels {
    let browser: [HintMarker]
    let chat: [HintMarker]
    let typed: [HintMarker]
    let typedText: String

    init() throws {
        var session = PreviewScenes.browser.session()
        browser = session.markers
        chat = PreviewScenes.chat.session().markers
        guard let prefix = browser.first(where: { $0.text.count > 1 })?.text.lowercased().first else {
            throw LabelPreviewError.noTypedState("the browser scene has no two-letter label")
        }
        guard case .showing(let remaining) = session.handle(.character(prefix)), !remaining.isEmpty else {
            throw LabelPreviewError.noTypedState("typing \(prefix) did not leave labels on screen")
        }
        typed = remaining
        typedText = session.typedText
    }

    /// The window of `size` in the browser scene that holds the most of the
    /// labels left after the key. A caret label hangs below its target, so
    /// room for it is counted with the target.
    func typedCrop(size: NSSize) -> NSRect {
        let scene = PreviewScenes.browser.size
        var best = NSRect(origin: .zero, size: size)
        var bestCount = -1
        var y: CGFloat = 0
        while y + size.height <= scene.height {
            var x: CGFloat = 0
            while x + size.width <= scene.width {
                let window = NSRect(x: x, y: y, width: size.width, height: size.height)
                let count = typed.filter { marker in
                    let reach = NSRect(
                        x: marker.anchor.x - 6,
                        y: marker.anchor.y - 4,
                        width: min(marker.elementWidth, 64) + 12,
                        height: min(marker.elementHeight, 30) + 30
                    )
                    return window.contains(reach)
                }.count
                if count > bestCount {
                    bestCount = count
                    best = window
                }
                x += 6
            }
            y += 6
        }
        return best
    }
}

@MainActor
enum LabelSheets {
    static let sceneScale: CGFloat = 4
    static let sheetScale: CGFloat = 2

    static let browserZoom = NSRect(x: 0, y: 38, width: 262, height: 66)
    static let chatZoom = NSRect(x: 0, y: 50, width: 262, height: 66)
    static let zoomSize = NSSize(width: 262, height: 66)

    static let compareCell = NSSize(width: 270, height: 150)
    static let compareBrowser = NSRect(x: 0, y: 36, width: 270, height: 150)
    static let compareChat = NSRect(x: 0, y: 44, width: 270, height: 150)

    static func fileStem(_ style: HintLabelStyle) -> String {
        style.optionLetter.map { "option-\($0)" } ?? "current"
    }

    static func heading(_ style: HintLabelStyle) -> String {
        if let letter = style.optionLetter {
            return "Option \(letter) · \(style.title)"
        }
        return "Current · v0.1.5"
    }

    static func summary(_ style: HintLabelStyle) -> String {
        let spec = style.spec
        let size = spec.fontSize == spec.fontSize.rounded()
            ? String(Int(spec.fontSize))
            : String(spec.fontSize)
        let weight = spec.fontWeight.rawValue.prefix(1).uppercased() + spec.fontWeight.rawValue.dropFirst()
        return "\(spec.fontDesign.familyName) \(weight) \(size)"
    }

    static func detail(_ style: HintLabelStyle) -> String {
        let spec = style.spec
        let pointer: String
        switch spec.pointer {
        case .none:
            pointer = "no pointer"
        case .corner:
            pointer = "corner drawn out to the target's top-left"
        case .caret:
            pointer = "caret touching the target, label below"
        }
        let typed: String
        switch spec.typed {
        case .recolor:
            typed = "typed letters turn green"
        case .dim:
            typed = "typed letters fade"
        case .inverse:
            typed = "typed letters invert"
        case .dimWithCursor:
            typed = "typed letters fade, bar under the next"
        }
        return "\(summary(style)) · \(pointer) · \(typed)"
    }

    private static func labelled(
        scene: PreviewScene,
        markers: [HintMarker],
        typed: String,
        style: HintLabelStyle
    ) -> NSView {
        let root = NSView(frame: NSRect(origin: .zero, size: scene.size))
        root.addSubview(SceneView(scene: scene))
        root.addSubview(HintLabelPreviewView(markers: markers, typedPrefix: typed, style: style, size: scene.size))
        return root
    }

    static func shots(style: HintLabelStyle, dark: Bool, labels: PreviewLabels) throws -> StyleShots {
        StyleShots(
            browser: try Raster.render(
                labelled(scene: PreviewScenes.browser, markers: labels.browser, typed: "", style: style),
                dark: dark, scale: sceneScale
            ),
            chat: try Raster.render(
                labelled(scene: PreviewScenes.chat, markers: labels.chat, typed: "", style: style),
                dark: dark, scale: sceneScale
            ),
            typed: try Raster.render(
                labelled(scene: PreviewScenes.browser, markers: labels.typed, typed: labels.typedText, style: style),
                dark: dark, scale: sceneScale
            )
        )
    }

    private struct Ink {
        let background: NSColor
        let text: NSColor
        let secondary: NSColor
        let frame: NSColor

        init(dark: Bool) {
            background = dark ? rgb(0x0C0C0E) : rgb(0xD8D8DE)
            text = dark ? rgb(0xF5F5F7) : rgb(0x1D1D1F)
            secondary = dark ? rgb(0xA1A1A6) : rgb(0x55555A)
            frame = dark ? rgb(0xFFFFFF, 0.16) : rgb(0x000000, 0.18)
        }
    }

    /// One style in one appearance: both windows with every label, the
    /// browser after one key, and three strips at twice the size.
    static func optionSheet(
        style: HintLabelStyle,
        dark: Bool,
        shots: StyleShots,
        labels: PreviewLabels
    ) throws -> NSBitmapImageRep {
        let ink = Ink(dark: dark)
        let browser = PreviewScenes.browser.size
        let chat = PreviewScenes.chat.size
        let margin: CGFloat = 12
        let gap: CGFloat = 16
        let header: CGFloat = 52
        let caption: CGFloat = 20
        let width = margin + browser.width + gap + chat.width + margin
        let firstRow = header + caption
        let secondRow = firstRow + browser.height + 10 + caption
        let height = secondRow + browser.height + margin
        let sheet = SheetView(size: NSSize(width: width, height: height), background: ink.background)

        let title = NSFont.systemFont(ofSize: 20, weight: .bold)
        let note = NSFont.systemFont(ofSize: 12, weight: .regular)
        let small = NSFont.systemFont(ofSize: 11, weight: .medium)
        let afterTitle = sheet.addText(heading(style), x: margin + 2, y: 14, font: title, color: ink.text)
        sheet.addText(detail(style), x: afterTitle + 14, y: 21, font: note, color: ink.secondary)
        sheet.addTrailingText(
            dark ? "Dark appearance" : "Light appearance",
            right: width - margin - 2, y: 21, font: note, color: ink.secondary
        )

        let typedKey = labels.typedText.uppercased()
        let rightX = margin + browser.width + gap
        func panel(_ rep: NSBitmapImageRep, x: CGFloat, y: CGFloat, size: NSSize, caption text: String) {
            sheet.addText(text, x: x + 2, y: y - caption + 3, font: small, color: ink.secondary)
            let dest = NSRect(x: x, y: y, width: size.width, height: size.height)
            sheet.add(.picture(rep, source: nil, dest: dest, radius: 9))
            sheet.add(.outline(dest, ink.frame, radius: 9, width: 1))
        }
        panel(shots.browser, x: margin, y: firstRow, size: browser,
              caption: "Browser · every label · \(labels.browser.count) targets")
        panel(shots.chat, x: rightX, y: firstRow, size: chat,
              caption: "Chat · every label · \(labels.chat.count) targets")
        panel(shots.typed, x: margin, y: secondRow, size: browser,
              caption: "Browser · after typing \(typedKey) · \(labels.typed.count) labels left")

        let typedZoom = labels.typedCrop(size: zoomSize)
        let strips: [(NSBitmapImageRep, NSRect, String)] = [
            (shots.browser, browserZoom, "2× · toolbar and site header"),
            (shots.typed, typedZoom, "2× · after typing \(typedKey)"),
            (shots.chat, chatZoom, "2× · chat list"),
        ]
        let stripHeight = zoomSize.height * 2
        let stripGap = (browser.height - stripHeight * 3) / 2
        for (index, strip) in strips.enumerated() {
            let y = secondRow + CGFloat(index) * (stripHeight + stripGap)
            let dest = NSRect(x: rightX, y: y, width: zoomSize.width * 2, height: stripHeight)
            sheet.addText(strip.2, x: rightX + 2, y: y - caption + 3, font: small, color: ink.secondary)
            sheet.add(.picture(strip.0, source: strip.1, dest: dest, radius: 9))
            sheet.add(.outline(dest, ink.frame, radius: 9, width: 1))
        }
        return try Raster.render(sheet, dark: dark, scale: sheetScale)
    }

    /// Three labels of one style on a plain page: one letter, two letters,
    /// and two letters with the first one typed.
    private static func specimen(style: HintLabelStyle, dark: Bool, size: NSSize) throws -> NSBitmapImageRep {
        let page = SheetView(size: size, background: dark ? rgb(0x1C1C1E) : rgb(0xFFFFFF))
        let margin = CGFloat(style.spec.margin)
        let badges = [
            HintBadgeView(label: "F", typedPrefix: "", style: style),
            HintBadgeView(label: "JK", typedPrefix: "", style: style),
            HintBadgeView(label: "ZF", typedPrefix: "z", style: style),
        ]
        let spacing: CGFloat = 7
        let bodies = badges.map { $0.frame.width - margin * 2 }
        let total = bodies.reduce(0, +) + spacing * CGFloat(badges.count - 1)
        var x = ((size.width - total) / 2).rounded()
        for (badge, body) in zip(badges, bodies) {
            badge.frame.origin = NSPoint(
                x: x - margin,
                y: ((size.height - badge.frame.height) / 2).rounded()
            )
            page.addSubview(badge)
            x += body + spacing
        }
        return try Raster.render(page, dark: dark, scale: sceneScale)
    }

    /// Every style side by side: the current one first, then A to D.
    static func compareSheet(
        shots: [HintLabelStyle: [Bool: StyleShots]],
        labels: PreviewLabels
    ) throws -> NSBitmapImageRep {
        let styles = [HintLabelStyle.classic] + HintLabelStyle.candidates
        let ink = Ink(dark: false)
        let cell = compareCell
        let gutter: CGFloat = 92
        let gap: CGFloat = 10
        let margin: CGFloat = 12
        let header: CGFloat = 58
        let specimenHeight: CGFloat = 68
        let width = gutter + CGFloat(styles.count) * cell.width + CGFloat(styles.count - 1) * gap + margin
        let typedCrop = labels.typedCrop(size: cell)
        let typedKey = labels.typedText.uppercased()

        enum Kind {
            case specimen
            case browser
            case chat
            case typed
        }
        struct Row {
            let title: String
            let subtitle: String
            let dark: Bool
            let height: CGFloat
            let kind: Kind
        }
        var rows: [Row] = []
        for dark in [false, true] {
            let name = dark ? "Dark" : "Light"
            rows.append(Row(title: name, subtitle: "2× labels", dark: dark, height: specimenHeight, kind: .specimen))
            rows.append(Row(title: name, subtitle: "browser", dark: dark, height: cell.height, kind: .browser))
            rows.append(Row(title: name, subtitle: "chat", dark: dark, height: cell.height, kind: .chat))
            rows.append(Row(title: name, subtitle: "after \(typedKey)", dark: dark, height: cell.height, kind: .typed))
        }
        let height = header + rows.reduce(0) { $0 + $1.height + gap } + margin - gap
        let sheet = SheetView(size: NSSize(width: width, height: height), background: ink.background)

        let columnTitle = NSFont.systemFont(ofSize: 15, weight: .bold)
        let columnNote = NSFont.systemFont(ofSize: 11, weight: .regular)
        let rowTitle = NSFont.systemFont(ofSize: 13, weight: .semibold)
        for (column, style) in styles.enumerated() {
            let x = gutter + CGFloat(column) * (cell.width + gap)
            sheet.addText(heading(style), x: x + 2, y: 12, font: columnTitle, color: ink.text)
            sheet.addText(summary(style), x: x + 2, y: 33, font: columnNote, color: ink.secondary)
        }
        sheet.addText("supervim", x: margin, y: 12, font: columnTitle, color: ink.text)
        sheet.addText("hint labels", x: margin, y: 33, font: columnNote, color: ink.secondary)

        var y = header
        for row in rows {
            sheet.addText(row.title, x: margin, y: y + 4, font: rowTitle, color: ink.text)
            sheet.addText(row.subtitle, x: margin, y: y + 22, font: columnNote, color: ink.secondary)
            for (column, style) in styles.enumerated() {
                let x = gutter + CGFloat(column) * (cell.width + gap)
                let dest = NSRect(x: x, y: y, width: cell.width, height: row.height)
                switch row.kind {
                case .specimen:
                    let rep = try specimen(
                        style: style,
                        dark: row.dark,
                        size: NSSize(width: cell.width / 2, height: row.height / 2)
                    )
                    sheet.add(.picture(rep, source: nil, dest: dest, radius: 8))
                case .browser:
                    if let rep = shots[style]?[row.dark]?.browser {
                        sheet.add(.picture(rep, source: compareBrowser, dest: dest, radius: 8))
                    }
                case .chat:
                    if let rep = shots[style]?[row.dark]?.chat {
                        sheet.add(.picture(rep, source: compareChat, dest: dest, radius: 8))
                    }
                case .typed:
                    if let rep = shots[style]?[row.dark]?.typed {
                        sheet.add(.picture(rep, source: typedCrop, dest: dest, radius: 8))
                    }
                }
                sheet.add(.outline(dest, ink.frame, radius: 8, width: 1))
            }
            y += row.height + gap
        }
        return try Raster.render(sheet, dark: false, scale: sheetScale)
    }
}

/// Writes every preview picture and prints the measured size of each label.
@MainActor
enum LabelPreviewRunner {
    static func writeAll(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let labels = try PreviewLabels()
        let styles = [HintLabelStyle.classic] + HintLabelStyle.candidates
        var written: [URL] = []
        var shots: [HintLabelStyle: [Bool: StyleShots]] = [:]
        for style in styles {
            for dark in [false, true] {
                let taken = try LabelSheets.shots(style: style, dark: dark, labels: labels)
                shots[style, default: [:]][dark] = taken
                let sheet = try LabelSheets.optionSheet(style: style, dark: dark, shots: taken, labels: labels)
                let name = "\(LabelSheets.fileStem(style))-\(dark ? "dark" : "light").png"
                let url = directory.appendingPathComponent(name)
                try Raster.write(sheet, to: url)
                written.append(url)
            }
        }
        let compare = directory.appendingPathComponent("compare.png")
        try Raster.write(try LabelSheets.compareSheet(shots: shots, labels: labels), to: compare)
        written.append(compare)

        var lines: [String] = []
        lines.append("typed key: \(labels.typedText.uppercased())")
        lines.append("browser targets: \(labels.browser.count), chat targets: \(labels.chat.count), left after the key: \(labels.typed.count)")
        for style in styles {
            let one = HintLabelPreviewView.bodySize(for: "F", style: style)
            let wide = HintLabelPreviewView.bodySize(for: "W", style: style)
            let two = HintLabelPreviewView.bodySize(for: "JK", style: style)
            lines.append(
                "\(style.rawValue): \(LabelSheets.summary(style)); body F \(text(one)), W \(text(wide)), JK \(text(two)) pt"
            )
        }
        let metrics = directory.appendingPathComponent("metrics.txt")
        try (lines.joined(separator: "\n") + "\n").write(to: metrics, atomically: true, encoding: .utf8)
        written.append(metrics)
        return written
    }

    private static func text(_ size: NSSize) -> String {
        "\(Int(size.width.rounded()))×\(Int(size.height.rounded()))"
    }
}
#endif

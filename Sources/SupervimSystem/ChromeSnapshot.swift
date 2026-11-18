#if canImport(AppKit)
import AppKit
import SupervimCore

public enum ChromeSnapshotError: Error, Equatable {
    case bitmap
    case png
}

/// Renders every on-screen surface, in the previous look and the current one,
/// for light and dark appearances. The runner writes the PNGs; this type does
/// not read the network and does not install an event tap.
@MainActor
public enum ChromeSnapshot {
    public static let scale: CGFloat = 2

    public static func writeAll(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        let appearances: [(String, NSAppearance.Name)] = [
            ("light", .aqua),
            ("dark", .darkAqua),
        ]
        for (name, appearance) in appearances {
            for polished in [false, true] {
                let era = polished ? "polished" : "legacy"
                written.append(try write(hints(polished: polished, contrast: false), "\(era)-\(name)-hints.png", appearance, directory))
                written.append(try write(help(polished: polished), "\(era)-\(name)-help.png", appearance, directory))
                written.append(try write(banner(polished: polished), "\(era)-\(name)-banner.png", appearance, directory))
                written.append(try write(status(polished: polished), "\(era)-\(name)-status.png", appearance, directory))
                written.append(try write(permissions(polished: polished), "\(era)-\(name)-permissions.png", appearance, directory))
                written.append(try write(settings(polished: polished), "\(era)-\(name)-settings.png", appearance, directory))
                written.append(try write(menu(polished: polished), "\(era)-\(name)-menu.png", appearance, directory))
            }
            written.append(try write(hints(polished: true, contrast: true), "polished-\(name)-hints-contrast.png", appearance, directory))
        }
        let appearing = hints(polished: true, contrast: false)
        appearing.alphaValue = 0.4
        written.append(try write(appearing, "polished-light-hints-appear.png", .aqua, directory))
        return written
    }

    private static func write(
        _ view: NSView,
        _ name: String,
        _ appearance: NSAppearance.Name,
        _ directory: URL
    ) throws -> URL {
        let data = try png(view: view, appearance: appearance)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private static func png(view: NSView, appearance: NSAppearance.Name) throws -> Data {
        let named = NSAppearance(named: appearance)
        view.appearance = named
        apply(appearance: named, to: view)
        if let help = view as? HelpSheetView {
            help.refreshAppearance()
        }
        let bounds = NSRect(origin: .zero, size: view.bounds.size)
        guard bounds.width >= 1, bounds.height >= 1 else {
            throw ChromeSnapshotError.bitmap
        }
        let window = NSWindow(
            contentRect: bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = named
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        view.frame = bounds
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        let pixelsWide = max(Int((bounds.width * scale).rounded()), 1)
        let pixelsHigh = max(Int((bounds.height * scale).rounded()), 1)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ChromeSnapshotError.bitmap
        }
        rep.size = bounds.size
        named?.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: bounds, to: rep)
        }
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ChromeSnapshotError.png
        }
        return data
    }

    private static func apply(appearance: NSAppearance?, to view: NSView) {
        view.appearance = appearance
        for child in view.subviews {
            apply(appearance: appearance, to: child)
        }
    }

    private static func hints(polished: Bool, contrast: Bool) -> NSView {
        let root = ColorBands(frame: NSRect(x: 0, y: 0, width: 640, height: 132))
        let samples = [("S", "s"), ("SA", "s"), ("D", ""), ("JK", "j")]
        let count = CGFloat(samples.count)
        for (index, sample) in samples.enumerated() {
            let badge: NSView
            if polished {
                let view = HintBadgeView(label: sample.0, typedPrefix: sample.1)
                if contrast {
                    view.forcesIncreaseContrast = true
                    view.forcesDifferentiateWithoutColor = true
                    view.forcesReduceTransparency = true
                }
                badge = view
            } else {
                badge = LegacyBadge(text: sample.0)
            }
            let slot = root.bounds.width / count
            badge.frame.origin = NSPoint(
                x: slot * CGFloat(index) + (slot - badge.frame.width) / 2,
                y: (root.bounds.height - badge.frame.height) / 2
            )
            root.addSubview(badge)
        }
        return root
    }

    private static func help(polished: Bool) -> NSView {
        let page = HelpPage(bindings: CommandMap().bindings)
        if polished {
            return HelpSheetView(page: page)
        }
        return LegacyHelp(text: page.text)
    }

    private static func banner(polished: Bool) -> NSView {
        let message = "没找到可点击元素"
        if polished {
            let band = ColorBands(frame: NSRect(x: 0, y: 0, width: 640, height: 96))
            let banner = BannerView(message: message)
            banner.frame.origin = NSPoint(
                x: (band.bounds.width - banner.frame.width) / 2,
                y: (band.bounds.height - banner.frame.height) / 2
            )
            band.addSubview(banner)
            return band
        }
        return LegacyStatusStrip(titles: [message])
    }

    private static func status(polished: Bool) -> NSView {
        if polished {
            return StatusGlyphStrip()
        }
        return LegacyStatusStrip(titles: ["Normal", "Insert", "Paused"])
    }

    private static func permissions(polished: Bool) -> NSView {
        let guidance = sampleGuidance()
        if polished {
            let chrome = PermissionGuideChrome(onOpen: { _ in }, onCheckAgain: {})
            chrome.render(guidance)
            return WindowCard(content: chrome.root, size: NSSize(width: 500, height: 520))
        }
        return LegacyPermissions(guidance: guidance)
    }

    private static func settings(polished: Bool) -> NSView {
        let editor = sampleEditor()
        if polished {
            let chrome = SettingsChrome(onAdd: {}, onRemove: { _ in }, onLaunchAtLogin: { _ in })
            chrome.render(editor)
            return WindowCard(content: chrome.root, size: NSSize(width: 460, height: 360))
        }
        return LegacySettings(editor: editor)
    }

    private static func menu(polished: Bool) -> NSView {
        let snapshot = MenuBarSnapshot(
            statusTitle: "Normal",
            commands: [
                MenuCommand(kind: .pause, title: "Pause", enabled: true),
                MenuCommand(kind: .resume, title: "Resume", enabled: false),
                MenuCommand(kind: .settings, title: "Settings", enabled: true),
                MenuCommand(kind: .separator, title: "", enabled: false),
                MenuCommand(kind: .quit, title: "Quit Supervim", enabled: true),
            ]
        )
        let items = MenuChrome.items(snapshot: snapshot, permissionsTitle: "Permissions")
        return MenuCard(items: items, polished: polished)
    }

    private static func sampleGuidance() -> PermissionGuidance {
        PermissionGuide(status: SnapshotStatus(), opener: SnapshotOpener()).refresh()
    }

    private static func sampleEditor() -> ExclusionEditor {
        ExclusionEditor(
            bundleIdentifiers: Settings.defaultExcludedBundleIdentifiers,
            launchAtLogin: false,
            frontmostBundleIdentifier: "com.apple.Safari",
            canAddFrontmost: true,
            notice: "",
            isVisible: true,
            windowTitle: "Settings",
            addButtonTitle: "Add \"Safari\"",
            removeButtonTitle: "Remove",
            launchAtLoginTitle: "Launch at Login"
        )
    }
}

private struct SnapshotStatus: PermissionStatusProviding, Sendable {
    func currentPermissionStatus() -> PermissionStatus {
        PermissionStatus(accessibility: .missing, inputMonitoring: .missing)
    }
}

private struct SnapshotOpener: PrivacyPaneOpening, Sendable {
    func openPrivacyPane(destination: String) -> Bool { false }
}

@MainActor
private final class ColorBands: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let colors: [NSColor] = [
            NSColor(srgbRed: 1, green: 0.84, blue: 0.04, alpha: 1),
            NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1),
            .white,
            NSColor(srgbRed: 0.2, green: 0.78, blue: 0.35, alpha: 1),
            .black,
        ]
        let slice = bounds.width / CGFloat(colors.count)
        for (index, color) in colors.enumerated() {
            color.setFill()
            NSRect(x: slice * CGFloat(index), y: 0, width: slice + 1, height: bounds.height).fill()
        }
    }
}

@MainActor
private final class LegacyBadge: NSView {
    let text: String

    init(text: String) {
        self.text = text
        let font = NSFont.boldSystemFont(ofSize: 12)
        let fitted = (text as NSString).size(withAttributes: [.font: font])
        super.init(frame: NSRect(x: 0, y: 0, width: max(fitted.width + 8, 18), height: max(fitted.height + 4, 16)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 1, green: 0.93, blue: 0.4, alpha: 0.95).setFill()
        bounds.fill()
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor.black,
                .paragraphStyle: style,
            ]
        ).draw(in: bounds.insetBy(dx: 2, dy: 1))
    }
}

@MainActor
private final class LegacyHelp: NSView {
    private let text: String

    init(text: String) {
        self.text = text
        let font = NSFont.systemFont(ofSize: 13)
        let bound = (text as NSString).boundingRect(
            with: NSSize(width: 536, height: 4000),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font]
        )
        let height = max(bound.height + 20, 40)
        super.init(frame: NSRect(x: 0, y: 0, width: 560, height: height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 1, green: 0.97, blue: 0.86, alpha: 0.96).setFill()
        bounds.fill()
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.black,
                .paragraphStyle: style,
            ]
        ).draw(in: bounds.insetBy(dx: 12, dy: 10))
    }
}

@MainActor
private final class LegacyStatusStrip: NSView {
    let titles: [String]

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 36))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let font = NSFont.systemFont(ofSize: 13)
        var x: CGFloat = 8
        for title in titles {
            let width = (title as NSString).size(withAttributes: [.font: font]).width + 16
            chromeDraw(
                title,
                in: NSRect(x: x, y: 8, width: width, height: 18),
                font: font,
                color: .labelColor
            )
            x += width
        }
    }
}

@MainActor
private final class StatusGlyphStrip: NSView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 64))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ChromeAppearance.isDark(effectiveAppearance)
        (dark ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1) : NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)).setFill()
        bounds.fill()
        let ink = dark ? NSColor.white : NSColor.black
        let kinds: [(MenuBarGlyphKind, String)] = [(.normal, "Normal"), (.insert, "Insert"), (.paused, "Paused")]
        for (index, item) in kinds.enumerated() {
            let origin = NSPoint(x: 24 + CGFloat(index) * 88, y: 16)
            ink.setFill()
            let glyph = NSRect(x: origin.x, y: origin.y + 8, width: 16, height: 16)
            NSGraphicsContext.current?.cgContext.saveGState()
            MenuBarGlyphImage.draw(item.0, in: glyph)
            NSGraphicsContext.current?.cgContext.restoreGState()
            chromeDraw(
                item.1,
                in: NSRect(x: origin.x + 22, y: origin.y + 6, width: 60, height: 16),
                font: ChromeFont.system(12, weight: .medium),
                color: ink
            )
        }
    }
}

@MainActor
private final class WindowCard: NSView {
    init(content: NSView, size: NSSize) {
        super.init(frame: NSRect(origin: .zero, size: size))
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

@MainActor
private final class LegacyPermissions: NSView {
    let guidance: PermissionGuidance

    init(guidance: PermissionGuidance) {
        self.guidance = guidance
        super.init(frame: NSRect(x: 0, y: 0, width: 500, height: 360))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let font = NSFont.systemFont(ofSize: 13)
        chromeDraw(guidance.title, in: NSRect(x: 16, y: bounds.height - 36, width: 460, height: 20), font: NSFont.boldSystemFont(ofSize: 13), color: .labelColor)
        chromeDraw(guidance.body, in: NSRect(x: 16, y: 80, width: 468, height: bounds.height - 130), font: font, color: .labelColor)
        var y = CGFloat(48)
        for link in guidance.links {
            chromeDraw(link.title, in: NSRect(x: 16, y: y, width: 280, height: 18), font: font, color: .labelColor)
            y -= 22
        }
    }
}

@MainActor
private final class LegacySettings: NSView {
    let editor: ExclusionEditor

    init(editor: ExclusionEditor) {
        self.editor = editor
        super.init(frame: NSRect(x: 0, y: 0, width: 440, height: 240))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let font = NSFont.systemFont(ofSize: 13)
        var y = bounds.height - 32
        chromeDraw(editor.launchAtLoginTitle, in: NSRect(x: 16, y: y, width: 400, height: 18), font: font, color: .labelColor)
        y -= 28
        for bundle in editor.bundleIdentifiers {
            chromeDraw(bundle, in: NSRect(x: 16, y: y, width: 280, height: 18), font: font, color: .labelColor)
            chromeDraw(editor.removeButtonTitle, in: NSRect(x: 320, y: y, width: 80, height: 18), font: font, color: .labelColor)
            y -= 22
        }
        chromeDraw(editor.addButtonTitle, in: NSRect(x: 16, y: 16, width: 200, height: 18), font: font, color: .labelColor)
    }
}

@MainActor
private final class MenuCard: NSView {
    let items: [MenuItemChrome]
    let polished: Bool

    init(items: [MenuItemChrome], polished: Bool) {
        self.items = items
        self.polished = polished
        let height = CGFloat(items.count) * 24 + 12
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ChromeAppearance.isDark(effectiveAppearance)
        let fill = polished
            ? (dark ? NSColor(srgbRed: 0.2, green: 0.2, blue: 0.21, alpha: 0.96) : NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 0.96))
            : NSColor.windowBackgroundColor
        fill.setFill()
        bounds.fill()
        let font = polished ? ChromeFont.system(13, weight: .regular) : NSFont.systemFont(ofSize: 13)
        var y: CGFloat = 6
        for item in items {
            if item.isSeparator {
                NSColor.separatorColor.setStroke()
                let line = NSBezierPath()
                line.move(to: NSPoint(x: 8, y: y + 12))
                line.line(to: NSPoint(x: bounds.width - 8, y: 12 + y))
                line.stroke()
                y += 24
                continue
            }
            let color = item.enabled ? NSColor.labelColor : NSColor.disabledControlTextColor
            var textX: CGFloat = 12
            if polished, let symbol = item.symbolName,
               let image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.title) {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                let sized = image.withSymbolConfiguration(config) ?? image
                sized.draw(in: NSRect(x: 12, y: y + 4, width: 16, height: 16))
                textX = 34
            }
            chromeDraw(item.title, in: NSRect(x: textX, y: y + 3, width: bounds.width - textX - 36, height: 18), font: font, color: color)
            if !item.keyEquivalent.isEmpty {
                chromeDraw("⌘\(item.keyEquivalent.uppercased())", in: NSRect(x: bounds.width - 36, y: y + 3, width: 28, height: 18), font: font, color: .secondaryLabelColor, alignment: .right)
            }
            y += 24
        }
    }
}
#endif

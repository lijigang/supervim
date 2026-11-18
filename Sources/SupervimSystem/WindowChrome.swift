#if canImport(AppKit)
import AppKit
import SupervimCore

/// A rounded group of rows with hairlines between them, like a list in
/// System Settings. It draws its own fill so it follows light and dark.
@MainActor
final class ChromeCardView: NSView {
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func replaceRows(_ rows: [NSView]) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let rule = ChromeRuleView()
                stack.addArrangedSubview(rule)
                rule.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        needsDisplay = true
    }

    /// A row with the given views. The first view takes the spare width, so
    /// the rest sit at the right edge.
    static func row(_ views: [NSView], height: CGFloat = 38) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: height).isActive = true
        if let first = views.first {
            first.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            first.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        for view in views.dropFirst() {
            view.setContentHuggingPriority(.required, for: .horizontal)
        }
        return row
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ChromeAppearance.isDark(effectiveAppearance)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        (dark ? NSColor.white.withAlphaComponent(0.06) : NSColor.white.withAlphaComponent(0.72)).setFill()
        path.fill()
        let line = ChromeNSColor.color(
            dark ? ChromePalette.darkStroke : ChromePalette.lightStroke,
            alpha: contrast ? 0.9 : (dark ? 0.14 : 0.12)
        )
        line.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
private final class ChromeRuleView: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ChromeAppearance.isDark(effectiveAppearance)
        ChromeNSColor.color(
            dark ? ChromePalette.darkStroke : ChromePalette.lightStroke,
            alpha: dark ? 0.12 : 0.1
        ).setFill()
        NSRect(x: 12, y: 0, width: max(bounds.width - 12, 0), height: 1).fill()
    }
}

@MainActor
private enum WindowText {
    static func title(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = ChromeFont.rounded(17, weight: .semibold)
        field.textColor = .labelColor
        return field
    }

    static func section(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.attributedStringValue = NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: ChromeFont.rounded(10.5, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
                .kern: 0.7,
            ]
        )
        return field
    }

    static func rowLabel(_ text: String, mono: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = mono ? ChromeFont.mono(12, weight: .regular) : ChromeFont.system(13, weight: .regular)
        field.textColor = .labelColor
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }

    static func notice() -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.font = ChromeFont.system(12, weight: .medium)
        field.textColor = .systemOrange
        return field
    }
}

/// Permission guide content. The window controller supplies the actions.
///
/// The first paragraph of the guidance is the instruction. The permissions
/// to grant are rows in one card, each with its own button. The remaining
/// paragraphs are background, set smaller and in the secondary color.
@MainActor
public final class PermissionGuideChrome: NSObject {
    public let root = NSView()
    public var onOpen: @MainActor (PermissionKind) -> Void
    public var onCheckAgain: @MainActor () -> Void
    public private(set) var primaryButton: NSButton?

    private let leadField = NSTextField(wrappingLabelWithString: "")
    private let detailField = NSTextField(wrappingLabelWithString: "")
    private let noticeField = WindowText.notice()
    private let card = ChromeCardView()
    private let checkAgainButton = NSButton()
    private let heading = WindowText.title("")
    private var linkKinds: [PermissionKind] = []

    private static let textWidth: CGFloat = 452

    public init(
        onOpen: @escaping @MainActor (PermissionKind) -> Void,
        onCheckAgain: @escaping @MainActor () -> Void
    ) {
        self.onOpen = onOpen
        self.onCheckAgain = onCheckAgain
        super.init()
        install()
    }

    public func render(_ guidance: PermissionGuidance) {
        heading.stringValue = guidance.title
        let paragraphs = guidance.body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        leadField.stringValue = paragraphs.first ?? ""
        leadField.isHidden = paragraphs.isEmpty
        detailField.attributedStringValue = Self.detail(Array(paragraphs.dropFirst()))
        detailField.isHidden = paragraphs.count < 2
        noticeField.stringValue = guidance.notice
        noticeField.isHidden = guidance.notice.isEmpty
        checkAgainButton.title = guidance.checkAgainTitle
        rebuildLinks(guidance.links)
    }

    private static func detail(_ paragraphs: [String]) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 7
        style.lineSpacing = 1.5
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(
            string: paragraphs.joined(separator: "\n"),
            attributes: [
                .font: ChromeFont.system(11.5, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: style,
            ]
        )
    }

    private static func name(for kind: PermissionKind) -> String {
        switch kind {
        case .accessibility:
            return "Accessibility"
        case .inputMonitoring:
            return "Input Monitoring"
        case .screenRecording:
            return "Screen Recording (optional)"
        }
    }

    private func install() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        let mark = IconMarkView(side: 32)
        mark.setContentHuggingPriority(.required, for: .horizontal)
        header.addArrangedSubview(mark)
        header.addArrangedSubview(heading)

        leadField.font = ChromeFont.system(13, weight: .regular)
        leadField.textColor = .labelColor
        leadField.maximumNumberOfLines = 0
        leadField.preferredMaxLayoutWidth = Self.textWidth

        detailField.maximumNumberOfLines = 0
        detailField.preferredMaxLayoutWidth = Self.textWidth

        checkAgainButton.bezelStyle = .rounded
        checkAgainButton.controlSize = .large
        checkAgainButton.font = ChromeFont.system(13, weight: .semibold)
        checkAgainButton.target = self
        checkAgainButton.action = #selector(checkAgainClicked(_:))
        checkAgainButton.keyEquivalent = "\r"
        primaryButton = checkAgainButton

        noticeField.maximumNumberOfLines = 2
        noticeField.preferredMaxLayoutWidth = Self.textWidth

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(leadField)
        stack.addArrangedSubview(card)
        stack.addArrangedSubview(detailField)
        stack.addArrangedSubview(checkAgainButton)
        stack.addArrangedSubview(noticeField)
        stack.setCustomSpacing(16, after: header)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),
            card.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func rebuildLinks(_ links: [PrivacyPaneLink]) {
        linkKinds = links.map(\.kind)
        var rows: [NSView] = []
        for (index, link) in links.enumerated() {
            let name = WindowText.rowLabel(Self.name(for: link.kind))
            let button = NSButton(title: "Open Settings", target: self, action: #selector(linkClicked(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = ChromeFont.system(11.5, weight: .medium)
            button.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)
            button.imagePosition = .imageTrailing
            button.toolTip = link.title
            button.setAccessibilityLabel(link.title)
            rows.append(ChromeCardView.row([name, button]))
        }
        card.replaceRows(rows)
        card.isHidden = rows.isEmpty
    }

    @objc private func linkClicked(_ sender: NSButton) {
        guard linkKinds.indices.contains(sender.tag) else {
            return
        }
        onOpen(linkKinds[sender.tag])
    }

    @objc private func checkAgainClicked(_ sender: NSButton) {
        _ = sender
        onCheckAgain()
    }
}

/// Settings content: launch at login, then the excluded apps as one card.
@MainActor
public final class SettingsChrome: NSObject {
    public let root = NSView()
    public var onAdd: @MainActor () -> Void
    public var onRemove: @MainActor (String) -> Void
    public var onLaunchAtLogin: @MainActor (Bool) -> Void

    private let general = ChromeCardView()
    private let excluded = ChromeCardView()
    private let noticeField = WindowText.notice()
    private let launchLabel = WindowText.rowLabel("")
    private let launchSwitch = NSSwitch()
    private let addButton = NSButton(title: "", target: nil, action: nil)
    private var displayedBundles: [String] = []

    public init(
        onAdd: @escaping @MainActor () -> Void,
        onRemove: @escaping @MainActor (String) -> Void,
        onLaunchAtLogin: @escaping @MainActor (Bool) -> Void
    ) {
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.onLaunchAtLogin = onLaunchAtLogin
        super.init()
        launchSwitch.target = self
        launchSwitch.action = #selector(launchClicked(_:))
        addButton.target = self
        addButton.action = #selector(addClicked(_:))
        install()
    }

    public func render(_ editor: ExclusionEditor) {
        addButton.title = editor.addButtonTitle
        addButton.isEnabled = editor.canAddFrontmost
        launchLabel.stringValue = editor.launchAtLoginTitle
        launchSwitch.setAccessibilityLabel(editor.launchAtLoginTitle)
        launchSwitch.state = editor.launchAtLogin ? .on : .off
        noticeField.stringValue = editor.notice
        noticeField.isHidden = editor.notice.isEmpty
        displayedBundles = editor.bundleIdentifiers
        rebuildRows(editor)
    }

    private func install() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        let mark = IconMarkView(side: 32)
        mark.setContentHuggingPriority(.required, for: .horizontal)
        header.addArrangedSubview(mark)
        header.addArrangedSubview(WindowText.title("Settings"))

        launchSwitch.controlSize = .small
        general.replaceRows([ChromeCardView.row([launchLabel, launchSwitch])])

        let section = WindowText.section("Excluded apps")

        addButton.bezelStyle = .rounded
        addButton.font = ChromeFont.system(13, weight: .medium)

        noticeField.maximumNumberOfLines = 3
        noticeField.preferredMaxLayoutWidth = 400

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(general)
        stack.addArrangedSubview(section)
        stack.addArrangedSubview(excluded)
        stack.addArrangedSubview(addButton)
        stack.addArrangedSubview(noticeField)
        stack.setCustomSpacing(16, after: header)
        stack.setCustomSpacing(18, after: general)
        stack.setCustomSpacing(6, after: section)
        stack.setCustomSpacing(10, after: excluded)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),
            general.widthAnchor.constraint(equalTo: stack.widthAnchor),
            excluded.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func rebuildRows(_ editor: ExclusionEditor) {
        var rows: [NSView] = []
        for (index, bundle) in editor.bundleIdentifiers.enumerated() {
            let label = WindowText.rowLabel(bundle, mono: true)
            let remove = NSButton(title: editor.removeButtonTitle, target: self, action: #selector(removeClicked(_:)))
            remove.tag = index
            remove.bezelStyle = .rounded
            remove.controlSize = .small
            remove.font = ChromeFont.system(11.5, weight: .medium)
            remove.setAccessibilityLabel("\(editor.removeButtonTitle) \(bundle)")
            rows.append(ChromeCardView.row([label, remove], height: 34))
        }
        if rows.isEmpty {
            let empty = WindowText.rowLabel("Nothing excluded.")
            empty.textColor = .secondaryLabelColor
            rows.append(ChromeCardView.row([empty], height: 34))
        }
        excluded.replaceRows(rows)
    }

    @objc private func addClicked(_ sender: NSButton) {
        _ = sender
        onAdd()
    }

    @objc private func removeClicked(_ sender: NSButton) {
        guard displayedBundles.indices.contains(sender.tag) else {
            return
        }
        onRemove(displayedBundles[sender.tag])
    }

    @objc private func launchClicked(_ sender: NSSwitch) {
        onLaunchAtLogin(sender.state == .on)
    }
}
#endif

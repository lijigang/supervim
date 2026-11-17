#if canImport(AppKit)
import AppKit
import SupervimCore

/// Permission guide content. The window controller supplies the actions.
@MainActor
public final class PermissionGuideChrome: NSObject {
    public let root = NSView()
    public var onOpen: @MainActor (PermissionKind) -> Void
    public var onCheckAgain: @MainActor () -> Void
    public private(set) var primaryButton: NSButton?

    private let bodyField = NSTextField(wrappingLabelWithString: "")
    private let noticeField = NSTextField(wrappingLabelWithString: "")
    private let linkStack = NSStackView()
    private let checkAgainButton = NSButton()
    private let heading = NSTextField(labelWithString: "")
    private var linkKinds: [PermissionKind] = []

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
        bodyField.stringValue = guidance.body
        noticeField.stringValue = guidance.notice
        noticeField.isHidden = guidance.notice.isEmpty
        checkAgainButton.title = guidance.checkAgainTitle
        rebuildLinks(guidance.links)
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
        let mark = IconMarkView(side: 36)
        mark.setContentHuggingPriority(.required, for: .horizontal)
        heading.font = ChromeFont.rounded(18, weight: .semibold)
        heading.textColor = .labelColor
        header.addArrangedSubview(mark)
        header.addArrangedSubview(heading)

        bodyField.font = ChromeFont.system(13, weight: .regular)
        bodyField.textColor = .labelColor
        bodyField.maximumNumberOfLines = 0
        bodyField.preferredMaxLayoutWidth = 452

        linkStack.orientation = .vertical
        linkStack.alignment = .leading
        linkStack.spacing = 8

        checkAgainButton.bezelStyle = .rounded
        checkAgainButton.controlSize = .large
        checkAgainButton.font = ChromeFont.system(13, weight: .semibold)
        checkAgainButton.target = self
        checkAgainButton.action = #selector(checkAgainClicked(_:))
        checkAgainButton.keyEquivalent = "\r"
        primaryButton = checkAgainButton

        noticeField.font = ChromeFont.system(12, weight: .medium)
        noticeField.textColor = .systemOrange
        noticeField.maximumNumberOfLines = 2
        noticeField.preferredMaxLayoutWidth = 452

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(bodyField)
        stack.addArrangedSubview(linkStack)
        stack.addArrangedSubview(checkAgainButton)
        stack.addArrangedSubview(noticeField)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),
        ])
    }

    private func rebuildLinks(_ links: [PrivacyPaneLink]) {
        for view in linkStack.arrangedSubviews {
            linkStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        linkKinds = links.map(\.kind)
        for (index, link) in links.enumerated() {
            let button = NSButton(title: link.title, target: self, action: #selector(linkClicked(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.font = ChromeFont.system(13, weight: .medium)
            button.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: link.title)
            button.imagePosition = .imageTrailing
            linkStack.addArrangedSubview(button)
        }
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

/// Settings content for the exclusion list and launch-at-login checkbox.
@MainActor
public final class SettingsChrome: NSObject {
    public let root = NSView()
    public var onAdd: @MainActor () -> Void
    public var onRemove: @MainActor (String) -> Void
    public var onLaunchAtLogin: @MainActor (Bool) -> Void

    private let rows = NSStackView()
    private let noticeField = NSTextField(wrappingLabelWithString: "")
    private let launchButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let addButton = NSButton(title: "", target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "Nothing excluded.")
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
        launchButton.target = self
        launchButton.action = #selector(launchClicked(_:))
        addButton.target = self
        addButton.action = #selector(addClicked(_:))
        install()
    }

    public func render(_ editor: ExclusionEditor) {
        addButton.title = editor.addButtonTitle
        addButton.isEnabled = editor.canAddFrontmost
        launchButton.title = editor.launchAtLoginTitle
        launchButton.state = editor.launchAtLogin ? .on : .off
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
        let title = NSTextField(labelWithString: "Settings")
        title.font = ChromeFont.rounded(18, weight: .semibold)
        title.textColor = .labelColor
        header.addArrangedSubview(mark)
        header.addArrangedSubview(title)

        launchButton.font = ChromeFont.system(13, weight: .regular)

        let section = NSTextField(labelWithString: "EXCLUDED APPS")
        section.font = ChromeFont.rounded(11, weight: .semibold)
        section.textColor = .secondaryLabelColor

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6

        emptyLabel.font = ChromeFont.system(12, weight: .regular)
        emptyLabel.textColor = .secondaryLabelColor

        addButton.bezelStyle = .rounded
        addButton.font = ChromeFont.system(13, weight: .medium)

        noticeField.font = ChromeFont.system(12, weight: .medium)
        noticeField.textColor = .systemOrange
        noticeField.maximumNumberOfLines = 3
        noticeField.preferredMaxLayoutWidth = 400

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(launchButton)
        stack.addArrangedSubview(section)
        stack.addArrangedSubview(rows)
        stack.addArrangedSubview(emptyLabel)
        stack.addArrangedSubview(addButton)
        stack.addArrangedSubview(noticeField)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),
            rows.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func rebuildRows(_ editor: ExclusionEditor) {
        for view in rows.arrangedSubviews {
            rows.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        emptyLabel.isHidden = !editor.bundleIdentifiers.isEmpty
        for (index, bundle) in editor.bundleIdentifiers.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            let label = NSTextField(labelWithString: bundle)
            label.font = ChromeFont.mono(12, weight: .regular)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingMiddle
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let remove = NSButton(title: editor.removeButtonTitle, target: self, action: #selector(removeClicked(_:)))
            remove.tag = index
            remove.bezelStyle = .rounded
            remove.controlSize = .small
            remove.font = ChromeFont.system(12, weight: .medium)
            remove.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(label)
            row.addArrangedSubview(remove)
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
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

    @objc private func launchClicked(_ sender: NSButton) {
        onLaunchAtLogin(sender.state == .on)
    }
}
#endif

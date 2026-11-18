import Foundation

/// sRGB color used by the on-screen chrome. Drawing code converts these
/// components to `NSColor`. Nothing here imports AppKit.
public struct ChromeColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.red = Double((hex >> 16) & 0xFF) / 255
        self.green = Double((hex >> 8) & 0xFF) / 255
        self.blue = Double(hex & 0xFF) / 255
    }

    /// Porter-Duff source-over onto an opaque backdrop.
    public func composited(over background: ChromeColor, alpha: Double) -> ChromeColor {
        let coverage = min(max(alpha, 0), 1)
        return ChromeColor(
            red: red * coverage + background.red * (1 - coverage),
            green: green * coverage + background.green * (1 - coverage),
            blue: blue * coverage + background.blue * (1 - coverage)
        )
    }

    public var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            let clamped = min(max(value, 0), 1)
            if clamped <= 0.04045 {
                return clamped / 12.92
            }
            return pow((clamped + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    public func contrastRatio(against other: ChromeColor) -> Double {
        let left = relativeLuminance
        let right = other.relativeLuminance
        let lighter = max(left, right)
        let darker = min(left, right)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// Colors taken from the app icon: a light gray rounded square and a green
/// normal-mode cursor. Text green is darker than the icon green so 12pt type
/// stays readable on the gray fill. The icon green itself is a graphic mark.
public enum ChromePalette {
    public static let iconGrayTop = ChromeColor(hex: 0xF7F7F8)
    public static let iconGrayBottom = ChromeColor(hex: 0xE9E9EC)
    public static let iconGreen = ChromeColor(hex: 0x34C759)

    public static let lightFill = ChromeColor(hex: 0xF7F7F8)
    public static let lightText = ChromeColor(hex: 0x1C1C1E)
    public static let lightSecondary = ChromeColor(hex: 0x6E6E73)
    public static let lightMatched = ChromeColor(hex: 0x0F7A32)
    public static let lightKeyCap = ChromeColor(hex: 0xFFFFFF)
    public static let lightStroke = ChromeColor(hex: 0x1C1C1E)

    public static let darkFill = ChromeColor(hex: 0x242426)
    public static let darkText = ChromeColor(hex: 0xF5F5F7)
    public static let darkSecondary = ChromeColor(hex: 0xAEAEB2)
    public static let darkMatched = iconGreen
    public static let darkKeyCap = ChromeColor(hex: 0x3A3A3C)
    public static let darkStroke = ChromeColor(hex: 0xF5F5F7)

    /// Near-opaque so a label stays readable on white, black, or a saturated page.
    public static let lightFillAlpha = 0.97
    public static let darkFillAlpha = 0.96
    /// Opacity of the one-point edge around a label, a key cap and a sheet.
    /// Enough to hold the shape on a page of the same gray, and no more.
    public static let lightHairlineAlpha = 0.22
    public static let darkHairlineAlpha = 0.22
    public static let minimumTextContrast = 4.5

    public static let backdrops: [ChromeColor] = [
        ChromeColor(hex: 0xFFFFFF),
        ChromeColor(hex: 0x000000),
        ChromeColor(hex: 0xFFCC00),
        ChromeColor(hex: 0x007AFF),
        ChromeColor(hex: 0xFF3B30),
        iconGreen,
    ]

    public static func surfaces(dark: Bool) -> [(text: ChromeColor, matched: ChromeColor, fill: ChromeColor)] {
        backdrops.map { backdrop in
            if dark {
                return (
                    darkText,
                    darkMatched,
                    darkFill.composited(over: backdrop, alpha: darkFillAlpha)
                )
            }
            return (
                lightText,
                lightMatched,
                lightFill.composited(over: backdrop, alpha: lightFillAlpha)
            )
        }
    }
}

/// How long a hint sheet, help sheet, or banner takes to fade in.
public enum ChromeMotion {
    public static let appearDuration = 0.14
    /// Hint labels answer a key press, so their fade is much shorter than
    /// the help sheet's. It only takes the edge off the labels appearing.
    public static let hintAppearDuration = 0.05

    public static func appearDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : appearDuration
    }

    public static func hintAppearDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : hintAppearDuration
    }
}

/// Splits a displayed hint into the characters the user has already typed
/// and the characters still to type. Matching is case-insensitive. The
/// matched slice keeps the label's own casing.
public struct HintLabelSplit: Equatable, Sendable {
    public var matched: String
    public var remainder: String

    public init(matched: String, remainder: String) {
        self.matched = matched
        self.remainder = remainder
    }
}

public enum HintLabelHighlight {
    public static func split(label: String, typedPrefix: String) -> HintLabelSplit {
        let typed = typedPrefix.lowercased()
        guard !typed.isEmpty else {
            return HintLabelSplit(matched: "", remainder: label)
        }
        let characters = Array(label)
        let typedCharacters = Array(typed)
        guard characters.count >= typedCharacters.count else {
            return HintLabelSplit(matched: "", remainder: label)
        }
        let prefix = String(characters.prefix(typedCharacters.count))
        guard prefix.lowercased() == typed else {
            return HintLabelSplit(matched: "", remainder: label)
        }
        let rest = String(characters.dropFirst(typedCharacters.count))
        return HintLabelSplit(matched: prefix, remainder: rest)
    }
}

public struct HintBadgeSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// Padding inside a hint label. The outer size is what placement receives.
/// `HintGeometry` is not involved; it still positions this rectangle.
public enum HintBadgeMetrics {
    public static let cursorWidth = 2.5
    public static let cursorHeight = 11.0
    public static let cursorGap = 4.0
    public static let textPaddingX = 5.0
    public static let textPaddingY = 2.5
    public static let shadowMargin = 4.0
    public static let minimumHeight = 22.0
    public static let cornerRadius = 5.0

    public static func size(textWidth: Double, textHeight: Double) -> HintBadgeSize {
        let innerWidth = textPaddingX + cursorWidth + cursorGap + max(textWidth, 0) + textPaddingX
        let innerHeight = max(textHeight, 0) + textPaddingY * 2
        let width = (innerWidth + shadowMargin * 2).rounded(.up)
        let height = max((innerHeight + shadowMargin * 2).rounded(.up), minimumHeight)
        return HintBadgeSize(width: width, height: height)
    }
}

public enum MenuBarGlyphKind: String, Equatable, Sendable {
    case normal
    case insert
    case paused
    case other

    /// Hint keeps the Normal title, so it uses the Normal cursor glyph.
    /// There is no visual-mode glyph: the mode machine has no visual mode.
    public init(statusTitle: String) {
        switch statusTitle {
        case "Normal":
            self = .normal
        case "Insert":
            self = .insert
        case "Paused":
            self = .paused
        default:
            self = .other
        }
    }
}

public struct MenuItemChrome: Equatable, Sendable {
    public var title: String
    public var symbolName: String?
    public var enabled: Bool
    public var keyEquivalent: String
    public var kind: MenuCommandKind?
    public var isSeparator: Bool
    public var isPermissions: Bool

    public init(
        title: String,
        symbolName: String?,
        enabled: Bool,
        keyEquivalent: String,
        kind: MenuCommandKind?,
        isSeparator: Bool,
        isPermissions: Bool
    ) {
        self.title = title
        self.symbolName = symbolName
        self.enabled = enabled
        self.keyEquivalent = keyEquivalent
        self.kind = kind
        self.isSeparator = isSeparator
        self.isPermissions = isPermissions
    }
}

/// Menu-item symbols and order. Titles and enablement still come from the snapshot.
public enum MenuChrome {
    public static let permissionsSymbolName = "lock.fill"

    public static func symbolName(for kind: MenuCommandKind) -> String? {
        switch kind {
        case .pause:
            return "pause.fill"
        case .resume:
            return "play.fill"
        case .settings:
            return "gearshape"
        case .quit:
            return "power"
        case .separator:
            return nil
        }
    }

    public static func items(snapshot: MenuBarSnapshot, permissionsTitle: String?) -> [MenuItemChrome] {
        var items: [MenuItemChrome] = []
        for command in snapshot.commands {
            if command.kind == .separator {
                if let permissionsTitle, !permissionsTitle.isEmpty {
                    items.append(
                        MenuItemChrome(
                            title: permissionsTitle,
                            symbolName: permissionsSymbolName,
                            enabled: true,
                            keyEquivalent: "",
                            kind: nil,
                            isSeparator: false,
                            isPermissions: true
                        )
                    )
                }
                items.append(
                    MenuItemChrome(
                        title: "",
                        symbolName: nil,
                        enabled: false,
                        keyEquivalent: "",
                        kind: .separator,
                        isSeparator: true,
                        isPermissions: false
                    )
                )
                continue
            }
            items.append(
                MenuItemChrome(
                    title: command.title,
                    symbolName: symbolName(for: command.kind),
                    enabled: command.enabled,
                    keyEquivalent: command.kind == .quit ? "q" : "",
                    kind: command.kind,
                    isSeparator: false,
                    isPermissions: false
                )
            )
        }
        return items
    }
}

public struct HelpSectionModel: Equatable, Sendable {
    public var title: String
    public var entries: [HelpEntry]

    public init(title: String, entries: [HelpEntry]) {
        self.title = title
        self.entries = entries
    }
}

public struct HelpFrame: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

public struct HelpPlacedRow: Equatable, Sendable {
    public var keys: String
    public var summary: String
    public var note: String
    public var frame: HelpFrame

    public init(keys: String, summary: String, note: String, frame: HelpFrame) {
        self.keys = keys
        self.summary = summary
        self.note = note
        self.frame = frame
    }
}

public struct HelpPlacedSection: Equatable, Sendable {
    public var title: String
    public var header: HelpFrame
    public var rows: [HelpPlacedRow]

    public init(title: String, header: HelpFrame, rows: [HelpPlacedRow]) {
        self.title = title
        self.header = header
        self.rows = rows
    }
}

public struct HelpSheetLayout: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var sections: [HelpPlacedSection]

    public init(width: Double, height: Double, sections: [HelpPlacedSection]) {
        self.width = width
        self.height = height
        self.sections = sections
    }
}

public enum HelpMetrics {
    public static let sheetWidth = 640.0
    public static let margin = 18.0
    public static let columnGap = 28.0
    public static let titleBlock = 32.0
    public static let titleGap = 10.0
    public static let headerHeight = 16.0
    public static let headerGap = 4.0
    public static let rowHeight = 24.0
    public static let notedRowHeight = 36.0
    public static let sectionGap = 10.0
    public static let bottomMargin = 16.0
    public static let minimumHeight = 120.0

    public static var columnWidth: Double {
        (sheetWidth - margin * 2 - columnGap) / 2
    }
}

/// Groups help rows and places them in two columns. The sheet is keyboard-only,
/// so the layout has to fit without scrolling.
public enum HelpChrome {
    public static let sectionOrder = ["Scroll", "Hints", "Navigation", "Find", "Modes"]

    public static func sectionTitle(for keys: String) -> String {
        switch keys {
        case "j", "k", "h", "l", "d", "u", "gg", "G":
            return "Scroll"
        case "f", "F":
            return "Hints"
        case "H", "L", "J", "K", "x", "t", "r":
            return "Navigation"
        case "/", "yy":
            return "Find"
        default:
            return "Modes"
        }
    }

    /// Scroll, hints, and find share the left column. Navigation and modes
    /// share the right, which keeps the two columns the same length.
    public static func columnIndex(for sectionTitle: String) -> Int {
        switch sectionTitle {
        case "Scroll", "Hints", "Find":
            return 0
        default:
            return 1
        }
    }

    /// Right-hand note. Scroll distances stay in the summary so the sheet
    /// does not repeat "scroll down" next to "Scroll down".
    public static func note(for entry: HelpEntry) -> String {
        var parts: [String] = []
        if entry.actionText.contains("Command") {
            parts.append(entry.actionText)
        }
        if let names = entry.promisedApplicationNames, !names.isEmpty {
            parts.append(names.joined(separator: ", "))
        }
        if entry.deviatesFromVimium {
            parts.append("differs from Vimium")
        }
        return parts.joined(separator: " · ")
    }

    public static func sections(in page: HelpPage) -> [HelpSectionModel] {
        var seen: [String] = []
        var buckets: [String: [HelpEntry]] = [:]
        for entry in page.entries {
            let title = sectionTitle(for: entry.keys)
            if buckets[title] == nil {
                seen.append(title)
            }
            buckets[title, default: []].append(entry)
        }
        var titles = sectionOrder.filter { buckets[$0] != nil }
        for title in seen where !titles.contains(title) {
            titles.append(title)
        }
        return titles.map { title in
            HelpSectionModel(title: title, entries: buckets[title] ?? [])
        }
    }

    public static func layout(page: HelpPage) -> HelpSheetLayout {
        let grouped = sections(in: page)
        let width = HelpMetrics.columnWidth
        var columnY = [Double](repeating: HelpMetrics.margin + HelpMetrics.titleBlock + HelpMetrics.titleGap, count: 2)
        var placed: [String: HelpPlacedSection] = [:]
        for section in grouped {
            let column = columnIndex(for: section.title) == 0 ? 0 : 1
            let x = HelpMetrics.margin + Double(column) * (width + HelpMetrics.columnGap)
            let header = HelpFrame(x: x, y: columnY[column], width: width, height: HelpMetrics.headerHeight)
            columnY[column] += HelpMetrics.headerHeight + HelpMetrics.headerGap
            var rows: [HelpPlacedRow] = []
            for entry in section.entries {
                let note = note(for: entry)
                let rowHeight = note.isEmpty ? HelpMetrics.rowHeight : HelpMetrics.notedRowHeight
                let frame = HelpFrame(x: x, y: columnY[column], width: width, height: rowHeight)
                rows.append(HelpPlacedRow(keys: entry.keys, summary: entry.summary, note: note, frame: frame))
                columnY[column] += rowHeight
            }
            columnY[column] += HelpMetrics.sectionGap
            placed[section.title] = HelpPlacedSection(title: section.title, header: header, rows: rows)
        }
        let contentBottom = max(columnY[0], columnY[1]) - HelpMetrics.sectionGap
        let height = max(contentBottom + HelpMetrics.bottomMargin, HelpMetrics.minimumHeight)
        let ordered = grouped.compactMap { placed[$0.title] }
        return HelpSheetLayout(width: HelpMetrics.sheetWidth, height: height, sections: ordered)
    }
}

/// Picks a display for the help sheet and the miss banner.
/// Hint labels do not use this. Their rectangles stay on `HintGeometry`.
public enum OverlayScreen {
    public static func index(containingX x: Double, y: Double, screens: [DisplayFrame]) -> Int? {
        for (index, screen) in screens.enumerated() {
            guard screen.width > 0, screen.height > 0 else {
                continue
            }
            let containsX = x >= screen.x && x < screen.x + screen.width
            let containsY = y >= screen.y && y < screen.y + screen.height
            if containsX && containsY {
                return index
            }
        }
        return nil
    }
}

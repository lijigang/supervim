/// One hint label.
/// `text` is stored lowercase. `displayText` is what the overlay shows.
/// `index` is the caller's element index, not a sorted position.
public struct HintLabel: Equatable, Sendable {
    public var index: Int
    public var text: String

    public init(index: Int, text: String) {
        self.index = index
        self.text = text
    }

    public var displayText: String {
        text.uppercased()
    }
}

/// Labels that still match a typed prefix.
/// `selectedIndex` is set only when `typed` equals exactly one matching label.
/// A proper prefix, even a unique one, does not select.
public struct HintQuery: Equatable, Sendable {
    public var typed: String
    public var matches: [HintLabel]
    public var selectedIndex: Int?

    public init(typed: String, matches: [HintLabel], selectedIndex: Int?) {
        self.typed = typed
        self.matches = matches
        self.selectedIndex = selectedIndex
    }

    public var matchingIndices: [Int] {
        matches.map(\.index)
    }
}

public enum HintLabelInput: Equatable, Sendable {
    case character(Character)
    case backspace
}

/// Result of one hint key.
/// `.noMatch` is the spec's invalid input: the caller cancels the hint.
/// `.selected` is a finished label: the caller clicks `selectedIndex`.
/// Escape is not an input. ModeMachine already leaves Hint on escape.
public enum HintLabelResult: Equatable, Sendable {
    case pending(HintQuery)
    case selected(HintQuery)
    case noMatch
}

/// Vimium alphabet hints for one hint session.
///
/// Labels come from the home-row alphabet `asdfghjkl`. They are as short as
/// possible and prefix-free: no label is a prefix of another. Assignment follows
/// Vimium's `AlphabetHints.hintStrings`: breadth-first expansion, then sort, then
/// reverse each string so the same first character is spread across the list.
///
/// `f` and `F` use the same labels. The click kind stays in `HintClick`.
/// This value does not scan accessibility elements or draw the overlay.
public struct HintLabeler: Equatable, Sendable {
    public static let alphabet = "asdfghjkl"

    public let labels: [HintLabel]
    public private(set) var typed: String

    public init(elementCount: Int) {
        self.init(labels: Self.generated(elementCount: elementCount))
    }

    /// Copies `labels` into lowercase storage, in the order given.
    public init(labels: [HintLabel]) {
        self.labels = labels.map { label in
            HintLabel(index: label.index, text: label.text.lowercased())
        }
        typed = ""
    }

    /// Case-insensitive prefix filter.
    /// Matching labels keep the caller's text and order. `typed` in the result is lowercase.
    /// An empty match list means nothing matches; it does not by itself cancel a session.
    public static func filter(labels: [HintLabel], typed rawTyped: String) -> HintQuery {
        let typed = rawTyped.lowercased()
        let matches = labels.filter { $0.text.lowercased().hasPrefix(typed) }
        let selectedIndex: Int?
        if matches.count == 1, matches[0].text.lowercased() == typed {
            selectedIndex = matches[0].index
        } else {
            selectedIndex = nil
        }
        return HintQuery(typed: typed, matches: matches, selectedIndex: selectedIndex)
    }

    public var filter: HintQuery {
        Self.filter(labels: labels, typed: typed)
    }

    public mutating func handle(_ input: HintLabelInput) -> HintLabelResult {
        switch input {
        case .backspace:
            if !typed.isEmpty {
                typed.removeLast()
            }
            return Self.outcome(of: filter)
        case .character(let character):
            let next = Self.filter(labels: labels, typed: typed + String(character))
            if next.matches.isEmpty {
                return .noMatch
            }
            typed = next.typed
            return Self.outcome(of: next)
        }
    }

    private static func outcome(of query: HintQuery) -> HintLabelResult {
        if query.selectedIndex != nil {
            return .selected(query)
        }
        return .pending(query)
    }

    /// Vimium `AlphabetHints.hintStrings`, fixed to `asdfghjkl`.
    /// A count below 1 yields no labels. The loop condition matches Vimium,
    /// including the extra pass that expands the empty seed.
    private static func generated(elementCount: Int) -> [HintLabel] {
        guard elementCount > 0 else {
            return []
        }
        var hints = [""]
        var offset = 0
        while hints.count - offset < elementCount || hints.count == 1 {
            let hint = hints[offset]
            offset += 1
            for character in alphabet {
                hints.append(String(character) + hint)
            }
        }
        let chosen = hints[offset..<(offset + elementCount)].sorted()
        return chosen.enumerated().map { index, hint in
            HintLabel(index: index, text: String(hint.reversed()))
        }
    }
}

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
/// The default alphabet is home row, then the upper row, then the lower row,
/// strongest fingers first: `fjdkslaghrueiwotypqvbncmxz`. Spec v0.1 named only
/// `asdfghjkl`. The longer order is the deviation that lets a normal window
/// keep a single letter on the likely targets. Pass another alphabet to
/// `init(elementCount:alphabet:)`.
///
/// Labels are prefix-free. Single letters are used for as many targets as
/// possible without making any other label longer than necessary, and the
/// easiest letters come first so the caller can give them to the most likely
/// targets. A letter is split into a two-letter prefix only after the target
/// count exceeds the alphabet, and only as many two-letter labels are emitted
/// as the remainder needs.
///
/// `f` and `F` use the same labels. The click kind stays in `HintClick`.
/// This value does not scan accessibility elements or draw the overlay.
public struct HintLabeler: Equatable, Sendable {
    /// Home row `fjdkslagh`, upper row `rueiwotypq`, lower row `vbncmxz`.
    public static let alphabet = "fjdkslaghrueiwotypqvbncmxz"

    public let labels: [HintLabel]
    public private(set) var typed: String

    public init(elementCount: Int) {
        self.init(elementCount: elementCount, alphabet: Self.alphabet)
    }

    /// `alphabet` is ease order, easiest first. Duplicates and case are folded.
    /// A count below 1 yields no labels.
    public init(elementCount: Int, alphabet: String) {
        self.init(labels: Self.generated(elementCount: elementCount, alphabet: alphabet))
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

    /// Prefix-free labels, easiest first.
    ///
    /// The longest label is only as long as a prefix-free set of `elementCount`
    /// requires. Within that limit the single-letter labels are maximized, and
    /// they are the first characters of `alphabet`. The leftover targets use the
    /// remaining characters as prefixes. One character cannot be both a finished
    /// label and a prefix, so a set one larger than the alphabet keeps every
    /// letter but the last as a single label and needs two labels that start
    /// with that last letter.
    private static func generated(elementCount: Int, alphabet rawAlphabet: String) -> [HintLabel] {
        let alphabet = characters(in: rawAlphabet)
        let texts = strings(count: elementCount, alphabet: alphabet)
        return texts.enumerated().map { index, text in
            HintLabel(index: index, text: text)
        }
    }

    private static func characters(in alphabet: String) -> [Character] {
        var seen = Set<Character>()
        var result: [Character] = []
        for character in alphabet.lowercased() {
            if seen.insert(character).inserted {
                result.append(character)
            }
        }
        return result
    }

    private static func strings(count: Int, alphabet: [Character]) -> [String] {
        guard count > 0, !alphabet.isEmpty else {
            return []
        }
        if alphabet.count == 1 {
            return [String(alphabet[0])]
        }
        return cover(count: count, alphabet: alphabet)
    }

    private static func cover(count: Int, alphabet: [Character]) -> [String] {
        let width = alphabet.count
        if count <= width {
            return (0..<max(count, 0)).map { String(alphabet[$0]) }
        }
        let maxLength = minimumMaxLength(count: count, width: width)
        let singles = maximumSingles(count: count, width: width, maxLength: maxLength)
        var labels = (0..<singles).map { String(alphabet[$0]) }
        let prefixes = Array(alphabet.dropFirst(singles))
        let rest = count - singles
        guard !prefixes.isEmpty, rest > 0 else {
            return labels
        }
        let base = rest / prefixes.count
        let extra = rest % prefixes.count
        for (index, prefix) in prefixes.enumerated() {
            let childCount = base + (index < extra ? 1 : 0)
            guard childCount > 0 else {
                continue
            }
            for child in cover(count: childCount, alphabet: alphabet) {
                labels.append(String(prefix) + child)
            }
        }
        return labels
    }

    /// Smallest L such that `width^L` can name `count` targets.
    private static func minimumMaxLength(count: Int, width: Int) -> Int {
        var length = 1
        var capacity = width
        while capacity < count && length < 8 {
            length += 1
            let next = capacity * width
            if next <= capacity {
                break
            }
            capacity = next
        }
        return length
    }

    /// Most single-letter labels that still leave a prefix-free cover of `count`
    /// whose longest label is `maxLength`.
    private static func maximumSingles(count: Int, width: Int, maxLength: Int) -> Int {
        if count <= width {
            return count
        }
        let childCapacity = widthPower(width, max(maxLength - 1, 0))
        for singles in stride(from: width, through: 0, by: -1) {
            let prefixes = width - singles
            if singles + prefixes * childCapacity >= count {
                return singles
            }
        }
        return 0
    }

    private static func widthPower(_ width: Int, _ exponent: Int) -> Int {
        guard exponent > 0 else {
            return 1
        }
        var value = 1
        for _ in 0..<exponent {
            let next = value * width
            if next <= value {
                return value
            }
            value = next
        }
        return value
    }
}

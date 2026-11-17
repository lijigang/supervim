import XCTest
@testable import SupervimCore

/// Behavior contract for Vimium-style hint labels.
/// Labels are generated and filtered here. Nothing is drawn, clicked, or scanned.
final class HintLabelerTests: XCTestCase {
    func testAlphabetIsHomeRowThenUpperThenLower() {
        XCTAssertEqual(HintLabeler.alphabet, "fjdkslaghrueiwotypqvbncmxz")
        XCTAssertEqual(Set(HintLabeler.alphabet).count, HintLabeler.alphabet.count)
        XCTAssertEqual(HintLabeler.alphabet.count, 26)
    }

    func testOneTargetUsesTheEasiestLetter() {
        XCTAssertEqual(HintLabeler(elementCount: 1).labels.map(\.text), ["f"])
    }

    func testAlphabetSizedSetIsOnlySingleLettersInEaseOrder() {
        let alphabet = HintLabeler.alphabet
        let labels = HintLabeler(elementCount: alphabet.count).labels.map(\.text)
        XCTAssertEqual(labels, alphabet.map { String($0) })
        XCTAssertTrue(labels.allSatisfy { $0.count == 1 })
    }

    func testAlphabetPlusOneKeepsSingleLettersAndTwoDoubles() {
        let alphabet = Array(HintLabeler.alphabet)
        let labels = HintLabeler(elementCount: alphabet.count + 1).labels.map(\.text)
        let singles = alphabet.dropLast().map { String($0) }
        let hardest = String(alphabet.last!)
        XCTAssertEqual(Array(labels.prefix(singles.count)), singles)
        XCTAssertEqual(labels.filter { $0.count == 1 }.count, alphabet.count - 1)
        XCTAssertEqual(labels.filter { $0.count == 2 }.count, 2)
        XCTAssertEqual(labels.suffix(2).map { $0.first.map(String.init) }, [hardest, hardest])
        XCTAssertTrue(isPrefixFree(labels))
    }

    func testLargeCountMaximizesSingleLettersAndStaysPrefixFree() {
        let width = HintLabeler.alphabet.count
        let labels = HintLabeler(elementCount: 100).labels.map(\.text)
        XCTAssertEqual(labels.count, 100)
        XCTAssertEqual(labels.filter { $0.count == 1 }.count, 23)
        XCTAssertEqual(labels.filter { $0.count == 2 }.count, 77)
        XCTAssertEqual(labels.map(\.count).max(), 2)
        XCTAssertEqual(
            Array(labels.prefix(width - 3)),
            Array(HintLabeler.alphabet.prefix(width - 3)).map { String($0) }
        )
        XCTAssertTrue(isPrefixFree(labels))
        XCTAssertEqual(Set(labels).count, labels.count)

        let overflow = HintLabeler(elementCount: 700).labels.map(\.text)
        XCTAssertEqual(overflow.count, 700)
        XCTAssertEqual(overflow.filter { $0.count == 1 }.count, 25)
        XCTAssertTrue(isPrefixFree(overflow))
        XCTAssertLessThanOrEqual(overflow.map(\.count).max() ?? 0, 3)
    }

    func testZeroElementsYieldNoLabels() {
        XCTAssertEqual(HintLabeler(elementCount: 0).labels, [])
    }

    func testNegativeElementCountYieldsNoLabels() {
        XCTAssertEqual(HintLabeler(elementCount: -1).labels, [])
        XCTAssertEqual(HintLabeler(elementCount: -100).labels, [])
    }

    func testTwoElementsUseTheTwoEasiestLetters() {
        assertLabels(HintLabeler(elementCount: 2), ["f", "j"])
    }

    func testNineElementsAreTheFirstNineSingleLetters() {
        assertLabels(
            HintLabeler(elementCount: 9),
            ["f", "j", "d", "k", "s", "l", "a", "g", "h"]
        )
    }

    func testTenElementsStaySingleLetters() {
        assertLabels(
            HintLabeler(elementCount: 10),
            ["f", "j", "d", "k", "s", "l", "a", "g", "h", "r"]
        )
    }

    func testEightyOneElementsStayPrefixFree() {
        let labeler = HintLabeler(elementCount: 81)
        let texts = labeler.labels.map(\.text)
        XCTAssertEqual(texts.count, 81)
        XCTAssertEqual(texts.filter { $0.count == 1 }.count, 23)
        XCTAssertTrue(isPrefixFree(texts))
        XCTAssertEqual(labeler, HintLabeler(elementCount: 81))
    }

    func testOneThousandElementsStayPrefixFreeAndDeterministic() {
        let labeler = HintLabeler(elementCount: 1000)
        let texts = labeler.labels.map(\.text)
        XCTAssertEqual(texts.count, 1000)
        XCTAssertTrue(isPrefixFree(texts))
        XCTAssertLessThanOrEqual(texts.map(\.count).max() ?? 0, 3)
        XCTAssertEqual(labeler, HintLabeler(elementCount: 1000))
    }

    func testCustomAlphabetMaximizesSinglesForOneSizeAndSizePlusOne() {
        XCTAssertEqual(HintLabeler(elementCount: 1, alphabet: "fjdk").labels.map(\.text), ["f"])
        XCTAssertEqual(HintLabeler(elementCount: 4, alphabet: "abcd").labels.map(\.text), ["a", "b", "c", "d"])
        let plus = HintLabeler(elementCount: 5, alphabet: "abcd").labels.map(\.text)
        XCTAssertEqual(plus, ["a", "b", "c", "da", "db"])
        XCTAssertTrue(isPrefixFree(plus))
        let square = HintLabeler(elementCount: 16, alphabet: "abcd").labels.map(\.text)
        XCTAssertEqual(square.filter { $0.count == 1 }.count, 0)
        XCTAssertEqual(square.filter { $0.count == 2 }.count, 16)
        XCTAssertEqual(square.first, "aa")
        XCTAssertEqual(square.last, "dd")
        XCTAssertTrue(isPrefixFree(square))
        let spill = HintLabeler(elementCount: 17, alphabet: "abcd").labels.map(\.text)
        XCTAssertEqual(spill.filter { $0.count == 1 }.count, 3)
        XCTAssertEqual(spill.filter { $0.count == 2 }.count, 0)
        XCTAssertEqual(spill.filter { $0.count == 3 }.count, 14)
        XCTAssertEqual(Array(spill.prefix(3)), ["a", "b", "c"])
        XCTAssertTrue(isPrefixFree(spill))
    }

    func testLabelsAreStoredLowercaseAndDisplayedUppercase() {
        let labels = HintLabeler(elementCount: 10).labels
        XCTAssertEqual(labels.map(\.text), ["f", "j", "d", "k", "s", "l", "a", "g", "h", "r"])
        for label in labels {
            XCTAssertEqual(label.text, label.text.lowercased(), label.text)
            XCTAssertEqual(label.displayText, label.text.uppercased(), label.text)
            XCTAssertNotEqual(label.displayText, label.text)
        }
    }

    func testGeneratedIndicesFollowElementOrder() {
        let labels = HintLabeler(elementCount: 10).labels
        XCTAssertEqual(labels.map(\.index), Array(0..<10))
    }

    func testCustomLabelsAreStoredLowercaseWithoutReordering() {
        let labeler = HintLabeler(labels: [
            HintLabel(index: 4, text: "AS"),
            HintLabel(index: 1, text: "Qa"),
        ])
        XCTAssertEqual(labeler.labels, [
            HintLabel(index: 4, text: "as"),
            HintLabel(index: 1, text: "qa"),
        ])
        XCTAssertEqual(labeler.typed, "")
    }

    func testInitialFilterMatchesEveryLabelAndSelectsNothing() {
        let labeler = HintLabeler(elementCount: 10)
        XCTAssertEqual(labeler.typed, "")
        XCTAssertEqual(
            labeler.filter,
            HintQuery(typed: "", matches: labeler.labels, selectedIndex: nil)
        )
        XCTAssertEqual(labeler.filter.matchingIndices, Array(0..<10))
    }

    func testZeroLabelsStartUnselectedAndAnyCharacterIsNoMatch() {
        var labeler = HintLabeler(elementCount: 0)
        XCTAssertEqual(
            labeler.filter,
            HintQuery(typed: "", matches: [], selectedIndex: nil)
        )
        let before = labeler
        XCTAssertEqual(labeler.handle(.character("a")), .noMatch)
        XCTAssertEqual(labeler.handle(.character("A")), .noMatch)
        XCTAssertEqual(labeler, before)
    }

    func testTypingASingleLetterSelectsThatElement() throws {
        var labeler = HintLabeler(elementCount: 9)
        let selected = try XCTUnwrap(labeler.labels.first { $0.text == "d" })
        XCTAssertEqual(
            labeler.handle(.character("d")),
            .selected(HintQuery(typed: "d", matches: [selected], selectedIndex: selected.index))
        )
        XCTAssertEqual(labeler.typed, "d")
        XCTAssertEqual(labeler.filter.selectedIndex, selected.index)
    }

    func testUppercaseTypingSelectsTheSameElement() throws {
        var lower = HintLabeler(elementCount: 9)
        var upper = HintLabeler(elementCount: 9)
        let selected = try XCTUnwrap(lower.labels.first { $0.text == "k" })
        let expected = HintLabelResult.selected(HintQuery(
            typed: "k",
            matches: [selected],
            selectedIndex: selected.index
        ))
        XCTAssertEqual(lower.handle(.character("k")), expected)
        XCTAssertEqual(upper.handle(.character("K")), expected)
        XCTAssertEqual(lower, upper)
    }

    func testPartialPrefixListsMatchesWithoutSelecting() {
        var labeler = HintLabeler(elementCount: 3, alphabet: "ab")
        let matches = [
            HintLabel(index: 1, text: "ba"),
            HintLabel(index: 2, text: "bb"),
        ]
        XCTAssertEqual(
            labeler.handle(.character("B")),
            .pending(HintQuery(typed: "b", matches: matches, selectedIndex: nil))
        )
        XCTAssertNil(labeler.filter.selectedIndex)
        XCTAssertEqual(labeler.filter.matchingIndices, [1, 2])
    }

    func testCompletingALabelSelectsItsElementIndex() {
        var labeler = HintLabeler(elementCount: 3, alphabet: "ab")
        _ = labeler.handle(.character("b"))
        XCTAssertEqual(
            labeler.handle(.character("a")),
            .selected(HintQuery(
                typed: "ba",
                matches: [HintLabel(index: 1, text: "ba")],
                selectedIndex: 1
            ))
        )
    }

    func testSiblingLabelIsSelectedOnTheOtherBranch() {
        var labeler = HintLabeler(elementCount: 3, alphabet: "ab")
        _ = labeler.handle(.character("b"))
        XCTAssertEqual(labeler.handle(.character("b")).selectedIndex, 2)
    }

    func testUniquePartialPrefixDoesNotSelect() {
        var labeler = HintLabeler(labels: [HintLabel(index: 7, text: "ab")])
        XCTAssertEqual(
            labeler.handle(.character("a")),
            .pending(HintQuery(
                typed: "a",
                matches: [HintLabel(index: 7, text: "ab")],
                selectedIndex: nil
            ))
        )
        XCTAssertEqual(
            labeler.handle(.character("b")),
            .selected(HintQuery(
                typed: "ab",
                matches: [HintLabel(index: 7, text: "ab")],
                selectedIndex: 7
            ))
        )
    }

    func testStaticFilterIsCaseInsensitiveAndKeepsCallerLabels() {
        let labels = [
            HintLabel(index: 2, text: "AS"),
            HintLabel(index: 8, text: "AA"),
        ]
        let query = HintLabeler.filter(labels: labels, typed: "As")
        XCTAssertEqual(query.typed, "as")
        XCTAssertEqual(query.matches, [HintLabel(index: 2, text: "AS")])
        XCTAssertEqual(query.selectedIndex, 2)
        XCTAssertEqual(query.matchingIndices, [2])
    }

    func testStaticFilterOnAnEmptyPrefixReturnsEveryLabelInGivenOrder() {
        let labels = [
            HintLabel(index: 5, text: "b"),
            HintLabel(index: 1, text: "a"),
        ]
        let query = HintLabeler.filter(labels: labels, typed: "")
        XCTAssertEqual(query.matches, labels)
        XCTAssertNil(query.selectedIndex)
        XCTAssertEqual(query.matchingIndices, [5, 1])
    }

    func testMatchOrderFollowsLabelOrderRatherThanIndexOrder() {
        var labeler = HintLabeler(labels: [
            HintLabel(index: 9, text: "ab"),
            HintLabel(index: 2, text: "ac"),
            HintLabel(index: 1, text: "b"),
        ])
        XCTAssertEqual(
            labeler.handle(.character("a")),
            .pending(HintQuery(
                typed: "a",
                matches: [
                    HintLabel(index: 9, text: "ab"),
                    HintLabel(index: 2, text: "ac"),
                ],
                selectedIndex: nil
            ))
        )
    }

    func testFullLabelThatIsAlsoAPrefixDoesNotSelect() {
        var labeler = HintLabeler(labels: [
            HintLabel(index: 0, text: "a"),
            HintLabel(index: 1, text: "ab"),
        ])
        XCTAssertEqual(
            labeler.handle(.character("a")),
            .pending(HintQuery(
                typed: "a",
                matches: labeler.labels,
                selectedIndex: nil
            ))
        )
        XCTAssertEqual(labeler.handle(.character("b")).selectedIndex, 1)
    }

    func testDuplicateLabelsDoNotSelect() {
        var labeler = HintLabeler(labels: [
            HintLabel(index: 3, text: "ab"),
            HintLabel(index: 4, text: "AB"),
        ])
        XCTAssertEqual(labeler.handle(.character("a")), .pending(HintQuery(
            typed: "a",
            matches: [
                HintLabel(index: 3, text: "ab"),
                HintLabel(index: 4, text: "ab"),
            ],
            selectedIndex: nil
        )))
        let completed = labeler.handle(.character("b"))
        XCTAssertEqual(completed, .pending(HintQuery(
            typed: "ab",
            matches: labeler.labels,
            selectedIndex: nil
        )))
        XCTAssertNil(completed.selectedIndex)
    }

    func testEmptyLabelIsSelectedBeforeAnyKeyWhenItIsTheOnlyLabel() {
        let labeler = HintLabeler(labels: [HintLabel(index: 6, text: "")])
        XCTAssertEqual(
            labeler.filter,
            HintQuery(typed: "", matches: [HintLabel(index: 6, text: "")], selectedIndex: 6)
        )
    }

    func testNoMatchLeavesTheTypedPrefixUntouched() {
        var labeler = HintLabeler(elementCount: 3, alphabet: "ab")
        XCTAssertEqual(
            labeler.handle(.character("b")),
            .pending(HintQuery(
                typed: "b",
                matches: [
                    HintLabel(index: 1, text: "ba"),
                    HintLabel(index: 2, text: "bb"),
                ],
                selectedIndex: nil
            ))
        )
        let before = labeler
        XCTAssertEqual(labeler.handle(.character("x")), .noMatch)
        XCTAssertEqual(labeler.handle(.character("Q")), .noMatch)
        XCTAssertEqual(labeler.handle(.character(" ")), .noMatch)
        XCTAssertEqual(labeler.handle(.character("İ")), .noMatch)
        XCTAssertEqual(labeler, before)
        XCTAssertEqual(labeler.typed, "b")
        XCTAssertEqual(labeler.filter.matchingIndices, [1, 2])
    }

    func testInvalidCharacterOnAnEmptyPrefixIsNoMatch() {
        var labeler = HintLabeler(elementCount: 4)
        XCTAssertEqual(labeler.labels.map(\.text), ["f", "j", "d", "k"])
        let before = labeler
        XCTAssertEqual(labeler.handle(.character("z")), .noMatch)
        XCTAssertEqual(labeler.handle(.character("1")), .noMatch)
        XCTAssertEqual(labeler, before)
        XCTAssertEqual(labeler.filter.matches, labeler.labels)
    }

    func testCharacterAfterACompletedLabelIsNoMatch() {
        var labeler = HintLabeler(elementCount: 1)
        XCTAssertNotNil(labeler.handle(.character("f")).selectedIndex)
        let before = labeler
        XCTAssertEqual(labeler.handle(.character("a")), .noMatch)
        XCTAssertEqual(labeler, before)
    }

    func testBackspaceRemovesTheLastTypedCharacter() {
        var labeler = HintLabeler(elementCount: 3, alphabet: "ab")
        _ = labeler.handle(.character("b"))
        _ = labeler.handle(.character("a"))
        XCTAssertEqual(labeler.filter.selectedIndex, 1)
        XCTAssertEqual(
            labeler.handle(.backspace),
            .pending(HintQuery(
                typed: "b",
                matches: [
                    HintLabel(index: 1, text: "ba"),
                    HintLabel(index: 2, text: "bb"),
                ],
                selectedIndex: nil
            ))
        )
        XCTAssertEqual(labeler.typed, "b")
    }

    func testBackspaceOnAnEmptyPrefixKeepsEveryLabel() {
        var labeler = HintLabeler(elementCount: 3)
        XCTAssertEqual(labeler.labels.map(\.text), ["f", "j", "d"])
        let before = labeler
        XCTAssertEqual(labeler.handle(.backspace), .pending(before.filter))
        XCTAssertEqual(labeler.handle(.backspace), .pending(before.filter))
        XCTAssertEqual(labeler, before)
    }

    func testBackspaceOnZeroLabelsStaysPendingAndEmpty() {
        var labeler = HintLabeler(elementCount: 0)
        XCTAssertEqual(
            labeler.handle(.backspace),
            .pending(HintQuery(typed: "", matches: [], selectedIndex: nil))
        )
    }

    func testBackspaceFromAUniquePartialRestoresTheEmptyPrefix() {
        var labeler = HintLabeler(labels: [HintLabel(index: 7, text: "ab")])
        _ = labeler.handle(.character("a"))
        XCTAssertEqual(
            labeler.handle(.backspace),
            .pending(HintQuery(
                typed: "",
                matches: [HintLabel(index: 7, text: "ab")],
                selectedIndex: nil
            ))
        )
    }

    func testBackspaceCanUndoASelectionAndChooseAnotherLabel() {
        var labeler = HintLabeler(labels: [
            HintLabel(index: 0, text: "aaa"),
            HintLabel(index: 73, text: "aas"),
        ])
        _ = labeler.handle(.character("a"))
        _ = labeler.handle(.character("a"))
        XCTAssertEqual(labeler.filter.matchingIndices, [0, 73])
        XCTAssertEqual(labeler.handle(.character("a")).selectedIndex, 0)
        _ = labeler.handle(.backspace)
        XCTAssertNil(labeler.filter.selectedIndex)
        XCTAssertEqual(labeler.handle(.character("s")).selectedIndex, 73)
        XCTAssertEqual(labeler.typed, "aas")
    }

    func testTypingAGeneratedLabelSelectsThatIndex() {
        let counts = [1, 9, 10, 81, 82, 100]
        for count in counts {
            let labeler = HintLabeler(elementCount: count)
            XCTAssertEqual(labeler.labels.count, count, "count \(count)")
            guard labeler.labels.count == count else { continue }
            let target = labeler.labels[count / 2]
            var session = labeler
            var result: HintLabelResult = .pending(labeler.filter)
            for character in target.text {
                result = session.handle(.character(character))
            }
            XCTAssertEqual(result.selectedIndex, target.index, "count \(count) label \(target.text)")
            XCTAssertEqual(session.typed, target.text)
            XCTAssertEqual(session.filter.matches, [target])
        }
    }

    func testValueCopiesDoNotShareTypedText() {
        var original = HintLabeler(elementCount: 10)
        var copy = original
        XCTAssertEqual(copy.handle(.character("j")).selectedIndex, 1)
        XCTAssertEqual(original.typed, "")
        XCTAssertEqual(original.filter.matches.count, 10)
        XCTAssertEqual(copy.typed, "j")
        _ = original.handle(.character("f"))
        XCTAssertEqual(copy.typed, "j")
        XCTAssertEqual(original.typed, "f")
    }

    func testPrefixFreeHelperRejectsALabelThatPrefixesAnother() {
        XCTAssertFalse(isPrefixFree(["a", "ab"]))
        XCTAssertFalse(isPrefixFree(["ab", "a", "b"]))
        XCTAssertTrue(isPrefixFree(["a", "b"]))
        XCTAssertTrue(isPrefixFree(["aa", "as", "d"]))
        XCTAssertTrue(isPrefixFree([]))
        XCTAssertTrue(isPrefixFree(["only"]))
    }
}

private func assertLabels(
    _ labeler: HintLabeler,
    _ texts: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let expected = texts.enumerated().map { HintLabel(index: $0.offset, text: $0.element) }
    XCTAssertEqual(labeler.labels, expected, file: file, line: line)
    assertGeneratedContract(
        labeler,
        lengths: Array(Set(texts.map(\.count))).sorted(),
        head: Array(texts.prefix(texts.count)),
        tail: Array(texts.suffix(texts.count)),
        checksum: checksum(texts),
        file: file,
        line: line
    )
}

private func assertGeneratedContract(
    _ labeler: HintLabeler,
    lengths: [Int],
    lengthCounts: [Int: Int]? = nil,
    head: [String],
    tail: [String],
    checksum expectedChecksum: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let texts = labeler.labels.map(\.text)
    XCTAssertEqual(labeler.labels.map(\.index), Array(texts.indices), file: file, line: line)
    XCTAssertEqual(Set(texts.map(\.count)).sorted(), lengths, file: file, line: line)
    if let lengthCounts {
        XCTAssertEqual(Dictionary(grouping: texts, by: \.count).mapValues(\.count), lengthCounts, file: file, line: line)
    }
    XCTAssertEqual(Array(texts.prefix(head.count)), head, file: file, line: line)
    XCTAssertEqual(Array(texts.suffix(tail.count)), tail, file: file, line: line)
    XCTAssertEqual(checksum(texts), expectedChecksum, file: file, line: line)
    XCTAssertTrue(isPrefixFree(texts), file: file, line: line)
    XCTAssertEqual(Set(texts).count, texts.count, file: file, line: line)
    let alphabet = Set(HintLabeler.alphabet)
    for text in texts {
        XCTAssertFalse(text.isEmpty, file: file, line: line)
        XCTAssertTrue(text.allSatisfy { alphabet.contains($0) }, text, file: file, line: line)
        XCTAssertEqual(text, text.lowercased(), file: file, line: line)
    }
}

private func isPrefixFree(_ labels: [String]) -> Bool {
    let ordered = labels.sorted()
    for index in ordered.indices.dropFirst() {
        if ordered[index].hasPrefix(ordered[index - 1]) {
            return false
        }
    }
    return true
}

private func checksum(_ labels: [String]) -> Int {
    var accumulator = 0
    for character in labels.joined(separator: "|") {
        let value = character.unicodeScalars.map(\.value).reduce(0, +)
        accumulator = (accumulator * 131 + Int(value)) % 1_000_000_007
    }
    return accumulator
}

private extension HintLabelResult {
    var selectedIndex: Int? {
        switch self {
        case .pending(let query), .selected(let query):
            return query.selectedIndex
        case .noMatch:
            return nil
        }
    }
}

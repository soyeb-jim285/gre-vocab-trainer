import Foundation
import Testing
@testable import GRECore

/// The two context modes: a real sentence with the word blanked out, and
/// "which meaning is being used here?" for words whose everyday sense is not
/// the tested one.
@Suite struct ContextModeTests {

    private static let catalog = try! WordCatalog.bundled()

    // MARK: - Cloze sentences

    @Test func everyWordHasAtLeastOneSentenceToBlank() {
        let without = Self.catalog.words.filter { ($0.gre?.cloze ?? []).isEmpty }
        #expect(without.isEmpty, "no cloze sentence for \(without.prefix(5).map(\.id))")
    }

    @Test func everyClozeActuallyContainsABlank() {
        for word in Self.catalog.words {
            for cloze in word.gre?.cloze ?? [] {
                #expect(cloze.contains("____"), "\(word.id): \(cloze)")
            }
        }
    }

    @Test func theBlankHidesTheWordAndNothingElse() {
        // The give-away failure is a blank that leaves the stem behind, as in
        // "the storm abat____". Nothing before the blank may end mid-word.
        for word in Self.catalog.words {
            for cloze in word.gre?.cloze ?? [] {
                let stem = String(word.word.prefix(4)).lowercased()
                let beforeBlank = cloze.components(separatedBy: "____").first ?? ""
                #expect(beforeBlank.lowercased().hasSuffix(stem) == false,
                        "\(word.id) leaks its stem: \(cloze)")
            }
        }
    }

    @Test func theAnswerIsNotSittingInTheSentence() throws {
        // Every occurrence must be blanked, or "a king may abdicate a throne; a
        // parent cannot abdicate a child" prints its own answer. Matched on word
        // boundaries: "disavow" in the sentence for "avow" is a different word,
        // and the contrast is the lesson rather than a leak.
        var leaks: [String] = []
        for word in Self.catalog.words {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word.word))\\b"
            for cloze in word.gre?.cloze ?? [] {
                if cloze.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    leaks.append(word.id)
                }
            }
        }
        #expect(leaks.isEmpty, "the word survives its own blank in \(leaks.prefix(5))")
    }

    // MARK: - Cloze options

    @Test func clozeOptionsAreSameKindAndSimilarDifficulty() throws {
        for id in ["abate", "laconic", "flag", "ubiquitous", "zephyr"] {
            let word = try #require(Self.catalog[id])
            let options = DistractorPicker.clozeDistractors(for: word, from: Self.catalog)
            #expect(options.count == 3, "\(id) got \(options.count) options")
            #expect(options.allSatisfy { $0.id != word.id })
            #expect(options.allSatisfy { $0.primaryPartOfSpeech == word.primaryPartOfSpeech },
                    "\(id) offered a different part of speech")
            // Within two bands: the answer must not stand out as the only hard
            // word among three easy ones.
            #expect(options.allSatisfy { abs($0.rating - word.rating) <= 2 }, "\(id) spread too wide")
        }
    }

    @Test func clozeOptionsAreStableAcrossCalls() throws {
        let word = try #require(Self.catalog["abate"])
        let first = DistractorPicker.clozeDistractors(for: word, from: Self.catalog).map(\.id)
        let second = DistractorPicker.clozeDistractors(for: word, from: Self.catalog).map(\.id)
        #expect(first == second)
    }

    @Test func clozeOptionsDifferFromTheMultipleChoiceOnes() throws {
        // Otherwise the second question is the first one with a blank in it.
        let word = try #require(Self.catalog["abate"])
        let plain = Set(DistractorPicker.distractors(for: word, from: Self.catalog).map(\.id))
        let cloze = Set(DistractorPicker.clozeDistractors(for: word, from: Self.catalog).map(\.id))
        #expect(plain != cloze)
    }

    @Test func everyWordCanBuildAFullClozeQuestion() {
        // Four options for all 2,898, or some learner meets a two-option question.
        let short = Self.catalog.words.filter {
            DistractorPicker.clozeDistractors(for: $0, from: Self.catalog).count < 3
        }
        #expect(short.isEmpty, "not enough options for \(short.prefix(5).map(\.id))")
    }

    // MARK: - Which meaning

    @Test func trapWordsAreFlaggedAndOrdinaryWordsAreNot() throws {
        for id in ["flag", "august", "base", "pine", "wax", "plastic"] {
            #expect(try #require(Self.catalog[id]).isTrap, "\(id) should be a trap")
        }
        for id in ["laconic", "ubiquitous", "abate", "gregarious"] {
            #expect(try #require(Self.catalog[id]).isTrap == false, "\(id) should not be a trap")
        }
    }

    @Test func senseOptionsOfferTheEverydayMeaningAsTheWrongAnswer() throws {
        let flag = try #require(Self.catalog["flag"])
        let options = DistractorPicker.senseDistractors(for: flag, from: Self.catalog)
        #expect(options.count == 3)
        #expect(options.allSatisfy { $0 != flag.teachingDefinition })
        // The wrong answers must include the meaning the learner arrives with:
        // for "flag" that is the piece of cloth, which is a noun where the
        // tested sense is a verb.
        #expect(flag.senses.contains { $0.pos != flag.primaryPartOfSpeech },
                "the everyday sense was truncated away")
        #expect(options.contains { $0.localizedCaseInsensitiveContains("emblem") },
                "no everyday sense among \(options)")
    }

    @Test func everyTrapKeepsItsEverydayMeaning() {
        // Without it the question has no tempting wrong answer, which is the
        // entire pedagogical point of the mode.
        let missing = Self.catalog.words
            .filter(\.isTrap)
            .filter { word in word.senses.allSatisfy { $0.pos == word.primaryPartOfSpeech } }
        #expect(Double(missing.count) / 401.0 < 0.15,
                "\(missing.count) traps lost their everyday sense: \(missing.prefix(5).map(\.id))")
    }

    @Test func everyTrapWordCanBuildAFullSenseQuestion() {
        let traps = Self.catalog.words.filter(\.isTrap)
        #expect(traps.count > 300)
        let short = traps.filter {
            DistractorPicker.senseDistractors(for: $0, from: Self.catalog).count < 3
        }
        #expect(short.isEmpty, "not enough meanings for \(short.prefix(5).map(\.id))")
    }

    @Test func senseOptionsNeverRepeatTheCorrectAnswer() {
        for word in Self.catalog.words.filter(\.isTrap) {
            let options = DistractorPicker.senseDistractors(for: word, from: Self.catalog)
            #expect(options.allSatisfy { $0.lowercased() != word.teachingDefinition.lowercased() },
                    "\(word.id) offers the right answer twice")
        }
    }
}

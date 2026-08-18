import Testing
@testable import GRECore

@Suite struct LevenshteinTests {

    @Test func distanceIsZeroForIdenticalStrings() {
        #expect(levenshtein("abate", "abate") == 0)
    }

    @Test func countsSubstitutionsInsertionsAndDeletions() {
        #expect(levenshtein("abate", "abait") == 2)   // substitution + insertion
        #expect(levenshtein("abate", "abat") == 1)    // deletion
        #expect(levenshtein("abate", "abatee") == 1)  // insertion
        #expect(levenshtein("kitten", "sitting") == 3)
    }

    @Test func handlesEmptyStrings() {
        #expect(levenshtein("", "") == 0)
        #expect(levenshtein("", "abc") == 3)
        #expect(levenshtein("abc", "") == 3)
    }

    @Test func isSymmetric() {
        #expect(levenshtein("perspicacious", "perspicasious") == levenshtein("perspicasious", "perspicacious"))
    }

    @Test func comparesByCharacterNotByteSoAccentsCountOnce() {
        // "é" is one character but two UTF-8 bytes; a byte-wise implementation
        // would report 2 here.
        #expect(levenshtein("resume", "résume") == 1)
    }
}

@Suite struct SpellingGraderTests {

    @Test func exactSpellingScoresFull() {
        #expect(LocalGrader.gradeSpelling(typed: "abate", expected: "abate").grade.score == 100)
    }

    @Test func ignoresSurroundingWhitespaceAndCapitalisation() {
        // The learner is being tested on letters, not on the shift key.
        #expect(LocalGrader.gradeSpelling(typed: "  Abate ", expected: "abate").grade.score == 100)
        #expect(LocalGrader.gradeSpelling(typed: "ABATE", expected: "abate").isExact)
    }

    @Test func aSingleWrongLetterIsNotAPassButComesBackSooner() {
        let result = LocalGrader.gradeSpelling(typed: "abait", expected: "abate")
        #expect(result.isExact == false)
        #expect(result.editDistance == 2)
        // A misspelling must never map to .good -- the whole point of the mode.
        #expect(result.grade.rating(strictness: .standard) != .good)
        #expect(result.grade.rating(strictness: .standard) != .easy)
    }

    @Test func aNearMissScoresAboveACompleteMiss() {
        let near = LocalGrader.gradeSpelling(typed: "abat", expected: "abate")
        let miss = LocalGrader.gradeSpelling(typed: "banana", expected: "abate")
        #expect(near.grade.score > miss.grade.score)
        #expect(miss.grade.score == 0)
    }

    @Test func emptyAnswerScoresZero() {
        #expect(LocalGrader.gradeSpelling(typed: "   ", expected: "abate").grade.score == 0)
    }
}

@Suite struct RecallGraderTests {

    @Test func theExactWordScoresFull() {
        #expect(LocalGrader.gradeRecall(typed: "Abate", expected: "abate").score == 100)
    }

    @Test func aTypoStillCountsAsRecallBecauseTheModeTestsMemoryNotSpelling() {
        let grade = LocalGrader.gradeRecall(typed: "abait", expected: "abate")
        #expect(grade.rating(strictness: .standard) == .good || grade.rating(strictness: .standard) == .hard)
        #expect(grade.score > 0)
    }

    @Test func aDifferentWordScoresZero() {
        #expect(LocalGrader.gradeRecall(typed: "banana", expected: "abate").score == 0)
    }
}

@Suite struct DistractorPickerTests {

    private static let catalog = try! WordCatalog.bundled()

    @Test func returnsTheRequestedNumberOfDistractors() throws {
        let abate = try #require(Self.catalog["abate"])
        let options = DistractorPicker.distractors(for: abate, from: Self.catalog, count: 3)
        #expect(options.count == 3)
    }

    @Test func neverIncludesTheAnswerItself() throws {
        for id in ["abate", "laconic", "obsequious", "ephemeral"] {
            let word = try #require(Self.catalog[id])
            let options = DistractorPicker.distractors(for: word, from: Self.catalog, count: 3)
            #expect(options.contains { $0.id == word.id } == false, "\(id) was offered as its own distractor")
            #expect(Set(options.map(\.id)).count == options.count, "\(id) got duplicate distractors")
        }
    }

    @Test func drawsDistractorsSharingThePartOfSpeechSoTheyStayPlausible() throws {
        for id in ["abate", "laconic", "acumen"] {
            let word = try #require(Self.catalog[id])
            let options = DistractorPicker.distractors(for: word, from: Self.catalog, count: 3)
            #expect(options.allSatisfy { $0.primaryPartOfSpeech == word.primaryPartOfSpeech },
                    "\(id) drew a distractor with a different part of speech")
        }
    }

    @Test func isStableAcrossCallsSoTheSameQuestionLooksTheSameTwice() throws {
        let word = try #require(Self.catalog["laconic"])
        let first = DistractorPicker.distractors(for: word, from: Self.catalog, count: 3)
        let second = DistractorPicker.distractors(for: word, from: Self.catalog, count: 3)
        #expect(first.map(\.id) == second.map(\.id))
    }

    @Test func differentWordsGetDifferentDistractorSets() throws {
        let a = DistractorPicker.distractors(for: try #require(Self.catalog["abate"]), from: Self.catalog, count: 3)
        let b = DistractorPicker.distractors(for: try #require(Self.catalog["abet"]), from: Self.catalog, count: 3)
        #expect(a.map(\.id) != b.map(\.id))
    }

    @Test func stableHashDoesNotDependOnTheProcessSeed() {
        // Swift's own hashValue is seeded per process, which would reshuffle every
        // launch. These are fixed expectations recorded from the implementation.
        #expect(stableHash("abate") == stableHash("abate"))
        #expect(stableHash("abate") != stableHash("abet"))
        #expect(stableHash("") == 14_695_981_039_346_656_037)  // FNV-1a 64-bit offset basis
    }
}

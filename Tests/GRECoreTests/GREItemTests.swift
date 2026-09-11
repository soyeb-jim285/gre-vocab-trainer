import Foundation
import Testing
@testable import GRECore

/// The exam's own question shapes, and the checks a machine can make on them.
@Suite struct GREItemTests {

    private static let catalog = try! WordCatalog.bundled()
    private static let items = try! ItemCatalog.bundled()
    private static let known = Set(catalog.words.map(\.id))

    private func completion(
        stem: String = "The review was so \(GREItem.blank) that even its author winced.",
        options: [String] = ["acerbic", "laconic", "verbose", "candid", "florid"],
        answers: [String] = ["acerbic"],
        explanation: String = "The author wincing is the clue: the review was sharp enough to sting, which acerbic says and the others do not."
    ) -> GREItem {
        GREItem(id: "t1", kind: .textCompletion, stem: stem, options: options,
                answers: answers, explanation: explanation)
    }

    @Test func aWellFormedCompletionHasNothingToReport() {
        #expect(completion().structuralProblems(knownWordIDs: Self.known).isEmpty)
    }

    @Test func theShapeChecksCatchWhatAMachineCanSee() {
        func problems(_ item: GREItem) -> [String] {
            item.structuralProblems(knownWordIDs: Self.known)
        }
        #expect(!problems(completion(stem: "No blank here at all.")).isEmpty)
        #expect(!problems(completion(stem: "\(GREItem.blank) and \(GREItem.blank).")).isEmpty)
        #expect(!problems(completion(options: ["acerbic", "laconic"])).isEmpty)
        #expect(!problems(completion(options: ["acerbic", "acerbic", "verbose", "candid", "florid"])).isEmpty)
        #expect(!problems(completion(answers: ["acerbic", "laconic"])).isEmpty)
        #expect(!problems(completion(answers: ["trenchant"])).isEmpty)
        #expect(!problems(completion(options: ["acerbic", "laconic", "verbose", "candid", "zzznotaword"])).isEmpty)
        #expect(!problems(completion(explanation: "Because.")).isEmpty)
    }

    @Test func anEquivalenceTakesTwoAnswersAndSixOptions() {
        let item = GREItem(
            id: "s1", kind: .sentenceEquivalence,
            stem: "Her remarks were \(GREItem.blank), and the committee thanked her for the brevity.",
            options: ["laconic", "terse", "verbose", "florid", "candid", "acerbic"],
            answers: ["laconic", "terse"],
            explanation: "The committee thanking her for brevity fixes the sense: both words mean said in few words, and either one leaves the sentence meaning the same thing."
        )
        #expect(item.structuralProblems(knownWordIDs: Self.known).isEmpty)
        #expect(item.kind.answerCount == 2)
        #expect(item.kind.optionCount == 6)
    }

    @Test func aPairIsAPairRatherThanASequence() {
        let item = GREItem(
            id: "s2", kind: .sentenceEquivalence, stem: "A \(GREItem.blank) reply.",
            options: ["laconic", "terse", "verbose", "florid", "candid", "acerbic"],
            answers: ["laconic", "terse"], explanation: String(repeating: "x", count: 45)
        )
        #expect(item.isCorrect(["terse", "laconic"]))
        #expect(item.isCorrect(["laconic", "terse"]))
        #expect(!item.isCorrect(["laconic"]))
        #expect(!item.isCorrect(["laconic", "terse", "verbose"]))
        #expect(!item.isCorrect(["laconic", "verbose"]))
    }

    @Test func aCompletionIsMarkedOnTheOneAnswer() {
        let item = completion()
        #expect(item.isCorrect(["acerbic"]))
        #expect(!item.isCorrect(["laconic"]))
        #expect(!item.isCorrect([]))
    }

    @Test func anItemIsScheduledAgainstItsAnswersAndNotItsDistractors() {
        // A distractor teaches nothing about itself: it was the wrong word here
        // and the learner was never asked what it means.
        #expect(completion().testedWordIDs == ["acerbic"])
    }

    // MARK: - The shipped set

    @Test func everyShippedItemIsWellFormedAndReachable() {
        for item in Self.items.items {
            let problems = item.structuralProblems(knownWordIDs: Self.known)
            #expect(problems.isEmpty, "\(item.id): \(problems.joined(separator: "; "))")
            for id in item.testedWordIDs {
                #expect(Self.items.items(testing: id).contains { $0.id == item.id })
            }
        }
        #expect(Set(Self.items.items.map(\.id)).count == Self.items.items.count, "duplicate item ids")
    }

    @Test func anAbsentQuestionFileIsAnEmptyDrillRatherThanACrash() throws {
        // The dataset is written in passes. A build without questions yet still
        // has to launch.
        #expect(ItemCatalog.empty.items.isEmpty)
        #expect(ItemCatalog.empty.items(testing: "abate").isEmpty)
        _ = try ItemCatalog.bundled()
    }
}

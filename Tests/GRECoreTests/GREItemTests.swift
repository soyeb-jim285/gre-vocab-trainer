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

/// Exam questions as a study mode: evidence about a word, on their own screen.
@Suite struct GREItemModeTests {

    private static let catalog = try! WordCatalog.bundled()

    @Test func theExamQuestionIsNeverChosenForAWord() throws {
        // It is picked by the learner opening the drill, not by a word's
        // evidence, and a word session has no stem to show.
        let word = try #require(Self.catalog["abate"])
        #expect(!Curriculum.candidates(for: word, aiEnabled: true).contains(.greItem))
        #expect(!StudyMode.forceable.contains(.greItem))
    }

    @Test func pinningASessionToItFallsBackRatherThanStranding() throws {
        let word = try #require(Self.catalog["abate"])
        let card = StudyCard(wordID: word.id, reviewCount: 3, isIntroduced: true)
        let step = Curriculum.step(
            for: card, word: word, competence: CardCompetence([]),
            settings: SessionSettings(aiEnabled: false, forcedMode: .greItem)
        )
        #expect(step != .drill(.greItem))
    }

    @Test func answeringOneStillCountsAsEvidence() {
        // The point of it being a mode at all: the schedule hears about it.
        #expect(StudyMode.locallyGraded.contains(.greItem))
        #expect(StudyMode.greItem.isTapToAnswer)
        #expect(!StudyMode.greItem.needsAI)
        #expect(StudyMode.greItem.promptSubject == .nothing)
    }
}

/// Choosing which exam questions to serve.
@Suite struct DrillPlannerTests {

    private static let catalog = try! WordCatalog.bundled()
    private let fsrs = FSRS(enableFuzzing: false)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ id: String, answer: String, options: [String]) -> GREItem {
        GREItem(id: id, kind: .textCompletion,
                stem: "A sentence with a \(GREItem.blank) in the middle of it.",
                options: options, answers: [answer],
                explanation: String(repeating: "explanation ", count: 6))
    }

    private var items: ItemCatalog {
        ItemCatalog(items: [
            item("a", answer: "abate", options: ["abate", "wane", "flag", "languish", "ebb"]),
            item("b", answer: "laconic", options: ["laconic", "terse", "verbose", "florid", "candid"]),
            item("c", answer: "cogent", options: ["cogent", "specious", "banal", "tenuous", "trenchant"]),
        ])
    }

    private func met(_ id: String, stability: Double = 10) -> StudyCard {
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: stability, difficulty: 5,
                           due: now.addingTimeInterval(86_400),
                           lastReview: now.addingTimeInterval(-86_400), state: .review, step: nil),
            reviewCount: 2, isIntroduced: true
        )
    }

    @Test func onlyQuestionsWhoseAnswersHaveBeenMetAreServed() {
        let served = DrillPlanner.session(
            from: items, cards: [met("abate")], scheduler: fsrs, seed: 1, now: now
        )
        #expect(served.map(\.id) == ["a"])
    }

    @Test func anUnstartedLearnerGetsNothingRatherThanAGuessingGame() {
        #expect(DrillPlanner.session(from: items, cards: [], scheduler: fsrs, seed: 1, now: now).isEmpty)
    }

    @Test func unmetWordsCanBeOpenedInDeliberately() {
        let served = DrillPlanner.session(
            from: items, cards: [], scheduler: fsrs, allowUnmet: true, seed: 1, now: now
        )
        #expect(served.count == 3)
    }

    @Test func theShakiestWordsAreAskedAbout() {
        // Two solid words and one nearly forgotten; over repeated draws the
        // shaky one should come up far more often.
        let cards = [met("abate", stability: 400), met("laconic", stability: 400),
                     met("cogent", stability: 0.4)]
        let counts = (0..<40).map { seed in
            DrillPlanner.session(from: items, cards: cards, scheduler: fsrs,
                                 count: 1, seed: UInt64(seed), now: now).first?.id
        }
        #expect(counts.filter { $0 == "c" }.count > counts.filter { $0 == "a" }.count)
    }

    @Test func theSameSeedServesTheSameQuestions() {
        let cards = ["abate", "laconic", "cogent"].map { met($0) }
        func run(_ seed: UInt64) -> [String] {
            DrillPlanner.session(from: items, cards: cards, scheduler: fsrs,
                                 count: 2, seed: seed, now: now).map(\.id)
        }
        #expect(run(9) == run(9))
        #expect(run(9).count == 2)
    }

    @Test func aQuestionJustAnsweredGoesToTheBack() {
        // The sentence is remembered even when the word is not, so asking it
        // again straight away tests the wrong thing.
        let cards = ["abate", "laconic", "cogent"].map { met($0) }
        let served = DrillPlanner.session(
            from: items, cards: cards, scheduler: fsrs, count: 2,
            recentItemIDs: ["a"], seed: 3, now: now
        )
        #expect(!served.contains { $0.id == "a" })
    }

    @Test func askingForMoreThanExistsReturnsWhatThereIs() {
        let cards = ["abate", "laconic", "cogent"].map { met($0) }
        let served = DrillPlanner.session(from: items, cards: cards, scheduler: fsrs,
                                          count: 50, seed: 1, now: now)
        #expect(served.count == 3)
        #expect(Set(served.map(\.id)).count == 3, "a question served twice in one run")
    }
}

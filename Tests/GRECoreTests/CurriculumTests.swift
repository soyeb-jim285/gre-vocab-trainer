import Foundation
import Testing
@testable import GRECore

@Suite struct CurriculumTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(
        _ id: String = "laconic", reviews: Int = 3, stability: Double = 10,
        state: FSRSState = .review
    ) -> StudyCard {
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: stability, difficulty: 5, due: now,
                           lastReview: now.addingTimeInterval(-86_400),
                           state: state, step: state == .review ? nil : 0),
            reviewCount: reviews,
            isIntroduced: true
        )
    }

    /// Met but not yet asked about anything: the state a word is in for the one
    /// question between the teaching card and its first review.
    private func justMet(_ id: String = "laconic") -> StudyCard {
        StudyCard(wordID: id, reviewCount: 0, isIntroduced: true)
    }

    private func step(
        _ card: StudyCard, word wordID: String = "laconic",
        competence: CardCompetence = CardCompetence([]),
        ai: Bool = false, writingAfter: Int = 3, forced: StudyMode? = nil
    ) -> StudyStep {
        Curriculum.step(
            for: card, word: Self.catalog[wordID]!, competence: competence,
            settings: SessionSettings(aiEnabled: ai, writingModeAfterReviews: writingAfter,
                                      forcedMode: forced)
        )
    }

    private func evidence(_ mode: StudyMode, _ score: Int) -> ReviewEvidence {
        ReviewEvidence(mode: mode, score: score, at: now)
    }

    // MARK: - Never test an unseen word

    @Test func aBrandNewWordIsTaughtRatherThanTested() {
        #expect(step(StudyCard(wordID: "laconic")) == .introduce)
    }

    @Test func firstContactOutranksAForcedMode() {
        // Forcing a drill says which skill to practise, not that a word the
        // learner has never seen should be guessed at in some other mode.
        for mode in StudyMode.allCases {
            #expect(step(StudyCard(wordID: "laconic"), ai: true, forced: mode) == .pretest)
            #expect(step(StudyCard(wordID: "laconic"), ai: false, forced: mode) == .introduce)
        }
    }

    @Test func firstContactWithAKeyAsksBeforeItTeaches() {
        // The pretest is what separates a word the learner already owns from one
        // they have never seen, and teaching first destroys that evidence.
        #expect(step(StudyCard(wordID: "laconic"), ai: true) == .pretest)
        #expect(step(StudyCard(wordID: "laconic"), ai: true).mode == .typeMeaning)
    }

    @Test func withoutAKeyFirstContactFallsBackToTeaching() {
        // Nothing can grade a written answer offline, so asking for one would
        // leave the answer unjudged and the learner unhelped.
        #expect(step(StudyCard(wordID: "laconic"), ai: false) == .introduce)
    }

    @Test func onlyAWeakPretestSendsTheLearnerToTheTeachingCard() {
        // Three is the right idea held hazily; the corrective feedback covers
        // that without stopping the session to teach.
        #expect(Curriculum.teaches(afterMeaningScore: 0))
        #expect(Curriculum.teaches(afterMeaningScore: 2))
        #expect(!Curriculum.teaches(afterMeaningScore: 3))
        #expect(!Curriculum.teaches(afterMeaningScore: 4))
    }

    @Test func introducingHappensOnceAndOnlyOnce() {
        // Teaching does not count as a review, so being met is what stops it
        // happening again -- not having answered something.
        #expect(step(justMet()) != .introduce)
        for reviews in 1..<20 {
            #expect(step(card(reviews: reviews)) != .introduce, "reintroduced at \(reviews)")
        }
    }

    @Test func aWordAlreadyAnsweredIsNeverTreatedAsUnmet() {
        // Progress from before the teaching card existed must not be re-taught.
        let legacy = StudyCard(wordID: "laconic", reviewCount: 4)
        #expect(legacy.isIntroduced)
        #expect(step(legacy) != .introduce)
    }

    @Test func theQuestionRightAfterTeachingIsRecognition() {
        #expect(step(justMet()) == .drill(.multipleChoice))
    }

    // MARK: - Falling back to recognition

    @Test func aForgottenWordDropsBackToRecognition() {
        let lapsed = card(reviews: 9, stability: 30, state: .relearning)
        #expect(step(lapsed) == .drill(.multipleChoice))
        // Even when the writing threshold would otherwise have been met.
        #expect(step(lapsed, ai: true, writingAfter: 0) == .drill(.multipleChoice))
    }

    @Test func aWordStillInTheLearningStepsStaysOnRecognition() {
        #expect(step(card(reviews: 1, stability: 1, state: .learning)) == .drill(.multipleChoice))
    }

    @Test func aShakyMemoryIsNotHandedTheHarderModes() {
        #expect(step(card(reviews: 4, stability: 2)) == .drill(.multipleChoice))
    }

    // MARK: - Trap words

    @Test func aTrapWordIsChallengedTheTimeAfterItIsIntroduced() throws {
        let flag = try #require(Self.catalog["flag"])
        #expect(flag.isTrap)
        #expect(step(card("flag", reviews: 1), word: "flag") == .drill(.senseInContext))
    }

    @Test func anOrdinaryWordIsNeverAskedWhichMeaning() throws {
        let laconic = try #require(Self.catalog["laconic"])
        #expect(laconic.isTrap == false)
        #expect(Curriculum.candidates(for: laconic).contains(.senseInContext) == false)
        for reviews in 1..<15 {
            for stability in [1.0, 10, 100] {
                let outcome = step(card(reviews: reviews, stability: stability))
                #expect(outcome != .drill(.senseInContext),
                        "asked which meaning about a single-sense word")
            }
        }
    }

    @Test func aTrapWordKeepsSenseInItsRotation() throws {
        let flag = try #require(Self.catalog["flag"])
        #expect(Curriculum.candidates(for: flag).contains(.senseInContext))
    }

    // MARK: - Writing threshold

    @Test func writingArrivesAtTheChosenThresholdAndNotBefore() {
        #expect(step(card(reviews: 2), ai: true, writingAfter: 3) != .drill(.defineAndUse))
        #expect(step(card(reviews: 3), ai: true, writingAfter: 3) == .drill(.defineAndUse))
    }

    @Test func withoutAKeyWritingIsNeverScheduled() {
        for reviews in 1..<15 {
            for threshold in [0, 1, 3] {
                #expect(step(card(reviews: reviews), ai: false, writingAfter: threshold)
                        != .drill(.defineAndUse))
            }
        }
    }

    @Test func aZeroThresholdStillMeetsTheWordFirst() {
        // Zero used to mean "write about it immediately", including on first
        // contact. First contact takes that slot now.
        #expect(step(StudyCard(wordID: "laconic"), ai: true, writingAfter: 0) == .pretest)
        #expect(step(justMet(), ai: true, writingAfter: 0) == .drill(.defineAndUse))
    }

    // MARK: - Forced modes

    @Test func aForcedModeOverridesTheEvidence() {
        #expect(step(card(reviews: 5), forced: .spelling) == .drill(.spelling))
    }

    @Test func aForcedModeCannotConjureAnApiKey() {
        #expect(step(card(reviews: 5), ai: false, forced: .defineAndUse) != .drill(.defineAndUse))
    }

    @Test func aForcedSenseDrillFallsBackOnAWordWithOneMeaning() {
        #expect(step(card(reviews: 5), forced: .senseInContext) != .drill(.senseInContext))
    }

    // MARK: - The point: evidence, not rotation

    @Test func theWeakestModeIsAskedRatherThanTheNextOneRound() {
        // Perfect at recall and cloze, hopeless at spelling. A rotation would
        // offer spelling one time in three.
        let history = CardCompetence((0..<4).flatMap { _ in
            [evidence(.reverseRecall, 100), evidence(.contextCloze, 100),
             evidence(.discriminate, 100), evidence(.spelling, 0)]
        })
        #expect(step(card(reviews: 12), competence: history) == .drill(.spelling))
    }

    @Test func aModeNeverAskedIsReachedBeforeAnyIsRepeated() {
        let history = CardCompetence([evidence(.contextCloze, 100), evidence(.reverseRecall, 100),
                                      evidence(.discriminate, 100)])
        #expect(step(card(reviews: 5), competence: history) == .drill(.spelling))
    }

    @Test func theSameHistoryAlwaysAsksTheSameQuestion() {
        let history = CardCompetence([evidence(.contextCloze, 40), evidence(.reverseRecall, 40),
                                      evidence(.spelling, 40)])
        let first = step(card(reviews: 7), competence: history)
        for _ in 0..<20 {
            #expect(step(card(reviews: 7), competence: history) == first)
        }
    }

    @Test func noHistoryStillProducesAnAnswerableStep() {
        // Reached when a word is strong but every mode is untried, which happens
        // to anyone whose review log predates the mode being added.
        let outcome = step(card(reviews: 7))
        #expect(outcome.mode != nil)
        #expect(outcome.mode != .defineAndUse)
    }

    // MARK: - Whole-catalog sanity

    @Test func everyWordCanBeAskedInEveryModeTheCurriculumOffersIt() {
        for word in Self.catalog.words {
            let modes = Curriculum.candidates(for: word)
            #expect(!modes.isEmpty, "\(word.id) has nothing to be asked")
            if modes.contains(.contextCloze) {
                #expect(!(word.gre?.cloze.isEmpty ?? true), "\(word.id) offered cloze without one")
            }
            if modes.contains(.senseInContext) {
                #expect(word.isTrap, "\(word.id) offered which-meaning without two meanings")
            }
        }
    }

    @Test func everyWordReachesADrillItCanActuallyBeAsked() {
        // A step naming a mode the word has no data for would be a dead end in
        // the session.
        for word in Self.catalog.words.prefix(400) {
            let outcome = Curriculum.step(
                for: card(word.id, reviews: 6), word: word,
                competence: CardCompetence([]), settings: SessionSettings(aiEnabled: false)
            )
            guard let mode = outcome.mode else { continue }
            if mode == .contextCloze { #expect(!(word.gre?.cloze.isEmpty ?? true), "\(word.id)") }
            if mode == .senseInContext { #expect(word.isTrap, "\(word.id)") }
        }
    }
}

/// Rotation: the forms vary across exposures, and the heavy ones stay spaced.
///
/// A day of typed definitions is homework. The budget is what keeps the
/// backbone form from becoming the only form.
@Suite struct FrictionTests {

    private static let catalog = try! WordCatalog.bundled()

    private func held(_ id: String) throws -> (StudyCard, Word) {
        let word = try #require(Self.catalog[id])
        let fsrs = FSRS(enableFuzzing: false)
        var card = FSRSCard()
        for _ in 0..<4 { card = fsrs.review(card, rating: .good, at: .now) }
        return (StudyCard(wordID: id, fsrs: card, reviewCount: 4, isIntroduced: true), word)
    }

    @Test func askingCostsWhatTheFormAsksFor() {
        // Tapping one of four is not the same demand as composing a sentence.
        #expect(StudyMode.multipleChoice.friction < StudyMode.spelling.friction)
        #expect(StudyMode.spelling.friction < StudyMode.defineAndUse.friction)
        #expect(StudyMode.typeMeaning.friction == StudyMode.defineAndUse.friction)
    }

    @Test func theFreeAnswerJoinsThePoolOnlyWhenItCanBeGraded() throws {
        let word = try #require(Self.catalog["abate"])
        #expect(Curriculum.candidates(for: word, aiEnabled: true).contains(.typeMeaning))
        #expect(!Curriculum.candidates(for: word, aiEnabled: false).contains(.typeMeaning))
    }

    @Test func twoHeavyAnswersInARowSpendTheBudget() {
        #expect(!Curriculum.isFatigued(recent: []))
        #expect(!Curriculum.isFatigued(recent: [.typeMeaning, .multipleChoice]))
        #expect(Curriculum.isFatigued(recent: [.typeMeaning, .spelling]))
        #expect(Curriculum.isFatigued(recent: [.typeMeaning, .defineAndUse]))
    }

    @Test func onlyTheRecentPastCounts() {
        // The budget shapes the next few minutes, not the day. Three typed
        // answers ago has been paid for by the two light ones since.
        #expect(!Curriculum.isFatigued(recent: [.typeMeaning, .typeMeaning, .multipleChoice, .contextCloze]))
    }

    @Test func afterAHeavyRunTheNextQuestionIsLight() throws {
        let (card, word) = try held("abate")
        // Evidence says the typed answer is weakest, but the learner has just
        // written two: the schedule can wait, the session cannot.
        let evidence = CardCompetence([])
        let settings = SessionSettings(aiEnabled: true)
        let tired = Curriculum.step(
            for: card, word: word, competence: evidence, settings: settings,
            recentModes: [.typeMeaning, .defineAndUse]
        )
        #expect(tired.mode?.friction == 1)

        let fresh = Curriculum.step(
            for: card, word: word, competence: evidence, settings: settings,
            recentModes: [.multipleChoice, .multipleChoice]
        )
        #expect(fresh.mode?.friction == 3)
    }

    @Test func aFatiguedLearnerIsStillAskedSomethingReal() throws {
        // Light is not nothing: the fallback has to be a question about this
        // word, not a free pass.
        let (card, word) = try held("abate")
        let step = Curriculum.step(
            for: card, word: word, competence: CardCompetence([]),
            settings: SessionSettings(aiEnabled: true),
            recentModes: [.typeMeaning, .typeMeaning]
        )
        let mode = try #require(step.mode)
        #expect(mode == .multipleChoice
                || Curriculum.candidates(for: word, aiEnabled: true).contains(mode))
    }
}

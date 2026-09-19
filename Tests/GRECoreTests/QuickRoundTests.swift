import Foundation
import Testing
@testable import GRECore

/// GregMat's pace, on per-word scheduling: a quick gloss, a quick charge.
@Suite struct QuickRoundTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(_ id: String = "abate", state: FSRSState = .review) -> StudyCard {
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: 10, difficulty: 5, due: now,
                           lastReview: now.addingTimeInterval(-86_400),
                           state: state, step: state == .review ? nil : 0),
            reviewCount: 4, isIntroduced: true
        )
    }

    private func item(_ mode: StudyMode, _ id: String = "abate") -> SessionItem {
        SessionItem(card: card(id), word: Self.catalog[id]!, mode: mode)
    }

    private func forced(_ mode: StudyMode, card: StudyCard, word: String = "abate") -> StudyStep {
        Curriculum.step(
            for: card, word: Self.catalog[word]!, competence: CardCompetence([]),
            settings: SessionSettings(aiEnabled: false, forcedMode: mode)
        )
    }

    @Test func quickRoundsAreLocalAndLight() {
        for mode in [StudyMode.gist, .charge] {
            #expect(mode.isQuickRound)
            #expect(StudyMode.locallyGraded.contains(mode))
            #expect(StudyMode.forceable.contains(mode))
            #expect(mode.friction == 1)
            #expect(!mode.needsAI)
        }
        #expect(!StudyMode.multipleChoice.isQuickRound)
    }

    @Test func aQuickRoundIsOnlyForWordsAlreadyHeld() {
        #expect(forced(.gist, card: card()) == .drill(.gist))
        // Still in its learning steps: the ordinary ladder takes over.
        #expect(forced(.gist, card: card(state: .learning)) != .drill(.gist))
        #expect(forced(.charge, card: card(state: .relearning)) != .drill(.charge))
    }

    @Test func aQuickRoundNeverTeachesANewWord() {
        #expect(forced(.gist, card: StudyCard(wordID: "abate")) == .introduce)
    }

    @Test func aRecalledGlossIsGoodAtBest() throws {
        let hit = try #require(AnswerJudge.judge(.recalled(true), item: item(.gist)))
        #expect(hit.rating == .good)
        let miss = try #require(AnswerJudge.judge(.recalled(false), item: item(.gist)))
        #expect(miss.rating == .again)
        #expect(miss.grade.score == 0)
    }

    @Test func aRightChargeIsHardAtBestBecauseItCanBeGuessed() throws {
        let word = try #require(Self.catalog.words.first { $0.charge != nil })
        let item = SessionItem(card: card(word.id), word: word, mode: .charge)
        let right = try #require(AnswerJudge.judge(
            .choice(word.charge!.rawValue), item: item, selfReport: .confident))
        #expect(right.grade.score == 100)
        #expect(right.rating == .hard)
        let wrongCharge = Charge.allCases.first { $0 != word.charge }!
        let wrong = try #require(AnswerJudge.judge(.choice(wrongCharge.rawValue), item: item))
        #expect(wrong.rating == .again)
    }

    @Test func quickRoundsDoNotCountTowardTheFirstDayCriterion() {
        #expect(!LearningCriterion.counts(score: 100, mode: .gist))
        #expect(!LearningCriterion.counts(score: 100, mode: .charge))
        #expect(LearningCriterion.counts(score: 100, mode: .multipleChoice))
        #expect(!LearningCriterion.counts(score: 50, mode: .multipleChoice))
    }
}

/// Retrieval to a criterion on the day a word is met.
@Suite struct LearningCriterionTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func graduated(_ id: String) -> StudyCard {
        // Through the learning steps and not due until tomorrow.
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: 2, difficulty: 5, due: now.addingTimeInterval(86_400),
                           lastReview: now.addingTimeInterval(-120), state: .review, step: nil),
            reviewCount: 2, isIntroduced: true
        )
    }

    private func next(
        _ cards: [StudyCard], owed: Set<String>, recent: [String] = [], newWords: Int = 99
    ) -> StudyCard? {
        SessionQueue.nextCard(
            cards: cards, catalog: Self.catalog, currentDeckID: nil,
            newWordsAllowed: newWords, scheduler: FSRS(enableFuzzing: false),
            recentAccuracy: nil, recentWordIDs: recent, belowCriterion: owed, now: now
        )
    }

    @Test func threeCorrectAnswersIsTheCriterion() {
        #expect(LearningCriterion.correctAnswersOnFirstDay == 3)
        let unmet = LearningCriterion.unmet(
            introducedToday: ["abate", "laconic", "flag"],
            correctToday: ["abate": 3, "laconic": 2]
        )
        #expect(unmet == ["laconic", "flag"])
    }

    @Test func aWordShortOfTheCriterionComesBackBeforeANewOne() {
        let card = graduated("abate")
        #expect(next([card], owed: ["abate"])?.wordID == "abate")
        // Met the criterion: tomorrow's review is tomorrow's, and a new word is next.
        #expect(next([card], owed: [])?.reviewCount == 0)
    }

    @Test func anOwedWordStillWaitsOutTheRepeatWindow() {
        let cards = [graduated("abate")]
        #expect(next(cards, owed: ["abate"], recent: ["abate"])?.wordID != "abate")
    }

    @Test func anOwedWordIsRepeatedRatherThanEndingTheSessionEarly() {
        let cards = [graduated("abate")]
        #expect(next(cards, owed: ["abate"], recent: ["abate"], newWords: 0)?.wordID == "abate")
        #expect(next(cards, owed: [], recent: ["abate"], newWords: 0) == nil)
    }
}

/// Two similar words that are both new interfere with each other.
@Suite struct ConfusionGatingTests {

    private static let catalog = try! WordCatalog.bundled()

    private func annotated() throws -> Word {
        try #require(Self.catalog.words.first { ($0.confusion?.count ?? 0) >= 2 })
    }

    @Test func aPartnerTheLearnerHasNotMetIsNeverOffered() throws {
        let word = try annotated()
        #expect(ConfusionDrill.question(for: word, from: Self.catalog, met: []) == nil)
        #expect(!ConfusionDrill.isAvailable(for: word, in: Self.catalog, met: []))
        #expect(!Curriculum.candidates(for: word, met: [], catalog: Self.catalog).contains(.discriminate))
    }

    @Test func onlyMetPartnersAreOffered() throws {
        let word = try annotated()
        let metPartner = try #require(word.confusion?.first?.with)
        for attempt in 0..<5 {
            let question = ConfusionDrill.question(
                for: word, from: Self.catalog, attempt: attempt, met: [metPartner]
            )
            #expect(question?.partner.id == metPartner)
        }
        #expect(Curriculum.candidates(for: word, met: [metPartner], catalog: Self.catalog)
            .contains(.discriminate))
    }
}

/// The deadline shapes the last weeks, not only the daily rate.
@Suite struct ExamDateTests {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ n: Int) -> Date { now.addingTimeInterval(Double(n) * 86_400) }

    @Test func theLastDaysAreReviewOnlyForSomeoneWithWordsToReview() {
        let profile = LearnerProfile(testDate: days(5), newWordsPerDayCap: 15)
        let reviewing = Pacing.advise(remaining: 100, profile: profile, met: 200,
                                      from: now, calendar: calendar)
        #expect(reviewing.isFinalReview)
        #expect(reviewing.newWordsToday == 0)
        // Someone starting four days out still has to start.
        let starting = Pacing.advise(remaining: 100, profile: profile, met: 0,
                                     from: now, calendar: calendar)
        #expect(!starting.isFinalReview)
        #expect(starting.newWordsToday > 0)
    }

    @Test func beforeTheStretchNewWordsCarryOn() {
        let profile = LearnerProfile(testDate: days(20), newWordsPerDayCap: 15)
        let advice = Pacing.advise(remaining: 100, profile: profile, met: 200,
                                   from: now, calendar: calendar)
        #expect(!advice.isFinalReview)
        #expect(advice.newWordsToday > 0)
    }

    @Test func noIntervalReachesPastTheTest() {
        #expect(Pacing.maximumIntervalDays(until: days(30), from: now, calendar: calendar) == 29)
        #expect(Pacing.maximumIntervalDays(until: days(1), from: now, calendar: calendar) == 1)
        #expect(Pacing.maximumIntervalDays(until: nil, from: now, calendar: calendar) == nil)
        #expect(Pacing.maximumIntervalDays(until: days(-2), from: now, calendar: calendar) == nil)
    }

    @Test func theCapActuallyHoldsInTheScheduler() {
        let cap = Pacing.maximumIntervalDays(until: days(10), from: now, calendar: calendar)!
        let fsrs = FSRS(maximumIntervalDays: cap, enableFuzzing: false)
        let strong = FSRSCard(stability: 200, difficulty: 3, due: now,
                              lastReview: now.addingTimeInterval(-100 * 86_400),
                              state: .review, step: nil)
        let next = fsrs.review(strong, rating: .easy, at: now)
        #expect(next.due <= days(10))
    }

    @Test func thePlanCountsDaysFromTheFirstStudyDay() throws {
        let plan = try #require(Pacing.planDay(started: days(-11), testDate: days(29),
                                               now: now, calendar: calendar))
        #expect(plan.day == 12)
        #expect(plan.of == 40)
        #expect(Pacing.planDay(started: nil, testDate: days(29), now: now, calendar: calendar) == nil)
    }
}

/// Predicting a word for the blank before seeing the options.
@Suite struct PredictionCheckTests {

    private static let catalog = try! WordCatalog.bundled()

    @Test func theAnswerItselfIsExact() {
        let abate = Self.catalog["abate"]!
        #expect(PredictionCheck.judge("  Abate ", answer: abate, catalog: Self.catalog) == .exact)
    }

    @Test func aListedSynonymCounts() throws {
        let word = try #require(Self.catalog.words.first { !($0.gre?.synonyms.isEmpty ?? true) })
        let synonym = word.gre!.synonyms[0]
        #expect(PredictionCheck.judge(synonym, answer: word, catalog: Self.catalog) == .synonym)
    }

    @Test func anAcceptedParaphraseCounts() throws {
        let word = try #require(Self.catalog["abase"])
        let concept = try #require(word.grounding?.acceptedConcepts.first)
        #expect(PredictionCheck.judge(concept, answer: word, catalog: Self.catalog) == .synonym)
    }

    @Test func somethingUnrecognisableIsLeftToTheLearner() {
        let abate = Self.catalog["abate"]!
        #expect(PredictionCheck.judge("zzqx", answer: abate, catalog: Self.catalog) == .unknown)
        #expect(PredictionCheck.judge("   ", answer: abate, catalog: Self.catalog) == .unknown)
    }

    @Test func chargesDecideWhenMeaningCannot() throws {
        let charged = Self.catalog.words.filter { $0.charge == .positive || $0.charge == .negative }
        try #require(charged.count > 10, "no charge data shipped")
        let answer = charged.first { $0.charge == .negative }!
        let same = charged.first {
            $0.charge == .negative && $0.id != answer.id
                && !(answer.gre?.synonyms.contains($0.word) ?? false)
                && !($0.gre?.synonyms.contains(answer.word) ?? false)
                && !(answer.grounding?.acceptedConcepts.contains($0.word) ?? false)
        }!
        let opposite = charged.first {
            $0.charge == .positive
                && !(answer.gre?.synonyms.contains($0.word) ?? false)
                && !($0.gre?.synonyms.contains(answer.word) ?? false)
        }!
        #expect(PredictionCheck.judge(same.word, answer: answer, catalog: Self.catalog) == .sameCharge)
        #expect(PredictionCheck.judge(opposite.word, answer: answer, catalog: Self.catalog) == .oppositeCharge)
        #expect(PredictionVerdict.sameCharge.isOnTarget)
        #expect(!PredictionVerdict.oppositeCharge.isOnTarget)
    }
}

/// How much of the likely vocabulary is held, and which sentence to show.
@Suite struct CoverageTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(_ id: String, stability: Double, reviews: Int = 3) -> StudyCard {
        StudyCard(wordID: id,
                  fsrs: FSRSCard(stability: stability, difficulty: 5, due: now, state: .review, step: nil),
                  reviewCount: reviews, isIntroduced: true)
    }

    @Test func onlyWordsPastTheLearningStepsCountAsHeld() {
        let cards = ["a": card("a", stability: 10), "b": card("b", stability: 1)]
        let coverage = Coverage(wordIDs: ["a", "b", "c", "d"], cards: cards)
        #expect(coverage.held == 1)
        #expect(coverage.total == 4)
        #expect(coverage.percent == 25)
        #expect(Coverage(wordIDs: [], cards: cards).fraction == 0)
    }

    @Test func aNewWordKeepsOneAnchorSentence() {
        #expect(ContextRotation.index(count: 2, card: card("a", stability: 1, reviews: 1)) == 0)
        #expect(ContextRotation.index(count: 2, card: card("a", stability: 1, reviews: 2)) == 0)
    }

    @Test func aHeldWordRotatesItsSentences() {
        let seen = Set((3...6).map {
            ContextRotation.index(count: 2, card: card("a", stability: 10, reviews: $0))
        })
        #expect(seen == [0, 1])
        #expect(ContextRotation.index(count: 1, card: card("a", stability: 10, reviews: 5)) == 0)
    }
}

/// The new per-word data ships for every word, or the features built on it
/// quietly disappear for the words without it.
@Suite struct EnrichedDatasetTests {

    private static let catalog = try! WordCatalog.bundled()

    @Test func everyWordCarriesAnOriginAndACharge() {
        let bare = Self.catalog.words.filter { $0.etymology == nil || $0.charge == nil }
        #expect(bare.isEmpty, "no origin or charge: \(bare.prefix(5).map(\.id))")
    }

    @Test func gregMatsGroupsAreThirtyWordsInHisOrder() {
        let groups = Dictionary(grouping: Self.catalog.words.filter { $0.gregmatGroup != nil }) {
            $0.gregmatGroup!
        }
        #expect(groups.count == 32)
        // "cumbersome" is listed twice and counted in its first group only.
        #expect(groups.values.filter { $0.count == 30 }.count == 31)
        #expect(Self.catalog["abound"]?.gregmatGroup == 1)
        #expect(Self.catalog["wary"]?.gregmatGroup == 1)
        #expect(Self.catalog["abhor"]?.gregmatGroup == 2)
    }

    @Test func mostRootsAreWorthGuessingFrom() {
        // A sanity floor on the model-drafted data: if this drops, the batch
        // that wrote it went wrong, not the language.
        let guessable = Self.catalog.words.filter { $0.etymology?.invitesGuess == true }.count
        #expect(guessable > Self.catalog.words.count / 2)
    }
}

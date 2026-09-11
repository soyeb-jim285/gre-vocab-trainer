import Foundation
import Testing
@testable import GRECore

@Suite struct DayPlannerTests {

    private static let catalog = try! WordCatalog.bundled()

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func days(_ n: Int) -> Date { now.addingTimeInterval(Double(n) * 86_400) }

    private func met(_ id: String, dueIn days: Double) -> StudyCard {
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: 10, difficulty: 5, due: now.addingTimeInterval(days * 86_400),
                           lastReview: now.addingTimeInterval(-86_400), state: .review, step: nil),
            reviewCount: 3
        )
    }

    private func plan(
        _ cards: [StudyCard], profile: LearnerProfile = LearnerProfile(newWordsPerDayCap: 10),
        introducedToday: Int = 0, answeredToday: Int = 0
    ) -> DayPlan {
        DayPlanner.plan(
            cards: cards, catalog: Self.catalog, profile: profile,
            introducedToday: introducedToday, answeredToday: answeredToday,
            now: now, calendar: calendar
        )
    }

    // MARK: - What is due

    @Test func onlyOverdueCardsCount() {
        let cards = [met("abate", dueIn: -1), met("laconic", dueIn: 0), met("acumen", dueIn: 3)]
        #expect(plan(cards).dueNow == 2)
    }

    @Test func aCardForAWordTheDatasetDroppedIsNotWork() {
        #expect(plan([met("thiswordwasremoved", dueIn: -1)]).dueNow == 0)
    }

    @Test func theSoonestFutureDueDateIsReportedForAFinishedDay() {
        let cards = [met("abate", dueIn: 3), met("laconic", dueIn: 1)]
        let outcome = plan(cards, profile: LearnerProfile(newWordsPerDayCap: 0))
        #expect(outcome.nextDue == now.addingTimeInterval(86_400))
        #expect(outcome.isComplete)
    }

    @Test func nothingScheduledLeavesNoNextDue() {
        #expect(plan([], profile: LearnerProfile(newWordsPerDayCap: 0)).nextDue == nil)
    }

    // MARK: - New words

    @Test func theDayOffersWhatThePacingAllows() {
        #expect(plan([]).newWordsRemaining == 10)
    }

    @Test func wordsAlreadyMetTodayComeOffTheDaysAllowance() {
        #expect(plan([], introducedToday: 4).newWordsRemaining == 6)
    }

    @Test func meetingMoreThanTheAllowanceDoesNotGoNegative() {
        #expect(plan([], introducedToday: 40).newWordsRemaining == 0)
    }

    @Test func aDeadlineCanRaiseTheDayAboveTheDefaultPace() {
        // Pacing asks for what the deadline needs, up to the learner's ceiling.
        let tight = LearnerProfile(testDate: days(60), newWordsPerDayCap: 200)
        #expect(plan([], profile: tight).newWordsRemaining > 10)
    }

    @Test func onlyIntroducedWordsCountAsProgressThroughTheCatalog() {
        // A card exists once a word has been met, so the backlog is the catalog
        // minus those.
        let cards = (0..<300).map { met(Self.catalog.words[$0].id, dueIn: 5) }
        let profile = LearnerProfile(testDate: days(100), newWordsPerDayCap: 500)
        let full = plan([], profile: profile).newWordsRemaining
        let partial = plan(cards, profile: profile).newWordsRemaining
        #expect(partial < full)
        #expect(plan(cards, profile: profile).pacing.wordsRemaining
                == Self.catalog.words.count - 300)
    }

    // MARK: - The countdown

    @Test func theDayIsDoneWhenNothingIsDueAndNothingNewIsAllowed() {
        let outcome = plan([met("abate", dueIn: 5)], profile: LearnerProfile(newWordsPerDayCap: 0))
        #expect(outcome.remainingAnswers == 0)
        #expect(outcome.isComplete)
        #expect(outcome.estimatedMinutes == 0)
    }

    @Test func theCountdownIsDueWorkPlusNewWork() {
        let cards = [met("abate", dueIn: -1), met("laconic", dueIn: -1)]
        #expect(plan(cards, introducedToday: 7).remainingAnswers == 2 + 3)
    }

    @Test func theEstimateRoundsUpSoAMinuteOfWorkNeverReadsAsZero() {
        #expect(plan([met("abate", dueIn: -1)], profile: LearnerProfile(newWordsPerDayCap: 0))
                .estimatedMinutes == 1)
    }

    @Test func progressRunsFromNothingDoneToEverythingDone() {
        let cards = (0..<10).map { met(Self.catalog.words[$0].id, dueIn: -1) }
        let noCap = LearnerProfile(newWordsPerDayCap: 0)
        #expect(plan(cards, profile: noCap, answeredToday: 0).progress == 0)
        #expect(plan(cards, profile: noCap, answeredToday: 10).progress == 0.5)
        #expect(plan([], profile: noCap, answeredToday: 10).progress == 1)
    }

    @Test func anEmptyDayReadsAsCompleteRatherThanDividingByZero() {
        let outcome = plan([], profile: LearnerProfile(newWordsPerDayCap: 0))
        #expect(outcome.progress == 1)
        #expect(outcome.isComplete)
    }

    // MARK: - Pacing carried through

    @Test func anUnreachableDeadlineIsReportedRatherThanSmoothedOver() {
        let profile = LearnerProfile(testDate: days(7), newWordsPerDayCap: 10)
        #expect(plan([], profile: profile).pacing.isOnTrack == false)
    }

    @Test func aComfortableDeadlineIsOnTrack() {
        let profile = LearnerProfile(testDate: days(365), newWordsPerDayCap: 20)
        #expect(plan([], profile: profile).pacing.isOnTrack)
    }

    // MARK: - Day rollover

    @Test func lateNightStudyBelongsToTheDayItFeelsLike() {
        // 01:00 Tuesday is still Monday's work at a 4am rollover.
        let tuesday1am = calendar.date(from: DateComponents(year: 2027, month: 3, day: 2, hour: 1))!
        let monday4am = calendar.date(from: DateComponents(year: 2027, month: 3, day: 1, hour: 4))!
        #expect(Pacing.dayStart(containing: tuesday1am, hour: 4, calendar: calendar) == monday4am)
    }

    @Test func morningStudyBelongsToItsOwnDay() {
        let tuesday9am = calendar.date(from: DateComponents(year: 2027, month: 3, day: 2, hour: 9))!
        let tuesday4am = calendar.date(from: DateComponents(year: 2027, month: 3, day: 2, hour: 4))!
        #expect(Pacing.dayStart(containing: tuesday9am, hour: 4, calendar: calendar) == tuesday4am)
    }

    @Test func aMidnightRolloverIsJustTheStartOfTheDay() {
        let tuesday1am = calendar.date(from: DateComponents(year: 2027, month: 3, day: 2, hour: 1))!
        #expect(Pacing.dayStart(containing: tuesday1am, hour: 0, calendar: calendar)
                == calendar.startOfDay(for: tuesday1am))
    }
}

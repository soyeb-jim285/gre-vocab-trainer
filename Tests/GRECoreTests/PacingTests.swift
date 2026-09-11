import Foundation
import Testing
@testable import GRECore

@Suite struct PacingTests {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00 UTC

    private func days(_ n: Int) -> Date { now.addingTimeInterval(Double(n) * 86_400) }

    // MARK: - Days available

    @Test func todayCountsAndTheExamMorningDoesNot() {
        // A test in 30 days leaves 30 study days: today through the day before.
        #expect(Pacing.studyDaysRemaining(from: now, to: days(30), calendar: calendar) == 30)
    }

    @Test func aTestTomorrowLeavesOnlyToday() {
        #expect(Pacing.studyDaysRemaining(from: now, to: days(1), calendar: calendar) == 1)
    }

    @Test func aTestTodayOrPastStillLeavesOneDayRatherThanZero() {
        // Never zero: the caller divides by this.
        #expect(Pacing.studyDaysRemaining(from: now, to: now, calendar: calendar) == 1)
        #expect(Pacing.studyDaysRemaining(from: now, to: days(-5), calendar: calendar) == 1)
    }

    @Test func timeOfDayDoesNotChangeTheCount() {
        let lateNight = now.addingTimeInterval(13 * 3600)
        #expect(Pacing.studyDaysRemaining(from: lateNight, to: days(30), calendar: calendar)
                == Pacing.studyDaysRemaining(from: now, to: days(30), calendar: calendar))
    }

    // MARK: - Rate from a deadline

    @Test func theRateSpreadsTheBacklogOverTheDaysLeft() {
        #expect(Pacing.newWordsPerDay(remaining: 300, testDate: days(30), from: now, calendar: calendar) == 10)
    }

    @Test func aRemainderRoundsUpSoTheLastWordFitsBeforeTheTest() {
        #expect(Pacing.newWordsPerDay(remaining: 301, testDate: days(30), from: now, calendar: calendar) == 11)
    }

    @Test func nothingLeftNeedsNoRate() {
        #expect(Pacing.newWordsPerDay(remaining: 0, testDate: days(30), from: now, calendar: calendar) == 0)
    }

    @Test func aTestTomorrowDemandsTheWholeBacklogToday() {
        #expect(Pacing.newWordsPerDay(remaining: 40, testDate: days(1), from: now, calendar: calendar) == 40)
    }

    // MARK: - Date from a rate

    @Test func todayIsTheFirstDayNotTheZerothDay() {
        // Ten a day and ten left finishes today, not tomorrow.
        #expect(Pacing.completionDate(remaining: 10, newWordsPerDay: 10, from: now, calendar: calendar)
                == calendar.startOfDay(for: now))
    }

    @Test func theCompletionDateCountsPartialFinalDays() {
        let expected = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now))
        #expect(Pacing.completionDate(remaining: 21, newWordsPerDay: 10, from: now, calendar: calendar)
                == expected)
    }

    @Test func aZeroRateNeverCompletes() {
        #expect(Pacing.completionDate(remaining: 10, newWordsPerDay: 0, from: now, calendar: calendar) == nil)
        // Unless there is nothing left to do, which is already complete.
        #expect(Pacing.completionDate(remaining: 0, newWordsPerDay: 0, from: now, calendar: calendar)
                == calendar.startOfDay(for: now))
    }

    @Test func theRateAndTheDateAgreeWithEachOther() {
        let rate = Pacing.newWordsPerDay(remaining: 500, testDate: days(45), from: now, calendar: calendar)
        let done = Pacing.completionDate(remaining: 500, newWordsPerDay: rate, from: now, calendar: calendar)
        let deadline = calendar.startOfDay(for: days(45))
        #expect(done != nil && done! < deadline, "the derived rate must finish before the test")
    }

    // MARK: - Advice

    @Test func aReachableGoalIsOnTrack() {
        let profile = LearnerProfile(testDate: days(30), newWordsPerDayCap: 15)
        let advice = Pacing.advise(remaining: 300, profile: profile, from: now, calendar: calendar)
        #expect(advice.required == 10)
        #expect(advice.allowed == 15)
        #expect(advice.isOnTrack)
        // Only what the deadline asks for, not the whole cap.
        #expect(advice.newWordsToday == 10)
    }

    @Test func aCapBelowWhatTheDeadlineDemandsSaysSo() {
        let profile = LearnerProfile(testDate: days(10), newWordsPerDayCap: 15)
        let advice = Pacing.advise(remaining: 900, profile: profile, from: now, calendar: calendar)
        #expect(advice.required == 90)
        #expect(advice.isOnTrack == false)
        // And the day still only holds what the learner agreed to.
        #expect(advice.newWordsToday == 15)
    }

    @Test func noTestDateIsAlwaysOnTrackAndFollowsTheCap() {
        let profile = LearnerProfile(testDate: nil, newWordsPerDayCap: 12)
        let advice = Pacing.advise(remaining: 900, profile: profile, from: now, calendar: calendar)
        #expect(advice.required == nil)
        #expect(advice.isOnTrack)
        #expect(advice.newWordsToday == 12)
    }

    @Test func beingWellAheadThrottlesTheDayRatherThanCramming() {
        // Three words and thirty days is one a day, not all three now. There is
        // no prize for finishing the catalog a month early.
        let profile = LearnerProfile(testDate: days(30), newWordsPerDayCap: 15)
        let advice = Pacing.advise(remaining: 3, profile: profile, from: now, calendar: calendar)
        #expect(advice.newWordsToday == 1)
    }

    @Test func theDayNeverAsksForMoreWordsThanRemain() {
        // No deadline, so nothing throttles but the backlog itself.
        let profile = LearnerProfile(testDate: nil, newWordsPerDayCap: 12)
        let advice = Pacing.advise(remaining: 3, profile: profile, from: now, calendar: calendar)
        #expect(advice.newWordsToday == 3)
    }

    @Test func aFinishedCatalogAsksForNothing() {
        let profile = LearnerProfile(testDate: days(30), newWordsPerDayCap: 15)
        let advice = Pacing.advise(remaining: 0, profile: profile, from: now, calendar: calendar)
        #expect(advice.newWordsToday == 0)
        #expect(advice.isOnTrack)
    }

    @Test func theWholeCatalogAgainstARealisticDeadlineIsHonestAboutBeingUnreachable() throws {
        let catalog = try WordCatalog.bundled()
        let profile = LearnerProfile(testDate: days(14), newWordsPerDayCap: 15)
        let advice = Pacing.advise(remaining: catalog.words.count, profile: profile,
                                   from: now, calendar: calendar)
        #expect(advice.isOnTrack == false, "2,898 words in a fortnight is not on track")
    }
}

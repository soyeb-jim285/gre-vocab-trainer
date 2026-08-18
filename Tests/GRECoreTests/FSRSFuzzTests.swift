import Foundation
import Testing
@testable import GRECore

/// Deterministic RNG so fuzz behaviour is reproducible in tests.
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

@Suite struct FSRSFuzzTests {
    private let epoch = Date(timeIntervalSince1970: 0)

    /// A graduated card sitting on a long interval -- the case fuzz applies to.
    private func maturedCard(_ fsrs: FSRS) -> FSRSCard {
        var rng = SeededRNG(seed: 1)
        var card = FSRSCard()
        for (rating, day) in [(FSRSRating.good, 0.0), (.good, 1.0), (.good, 30.0), (.good, 120.0)] {
            card = fsrs.review(card, rating: rating, at: epoch.addingTimeInterval(day * 86_400), using: &rng)
        }
        return card
    }

    @Test func fuzzingIsDisabledWhenTurnedOff() {
        let fsrs = FSRS(enableFuzzing: false)
        var rngA = SeededRNG(seed: 1)
        var rngB = SeededRNG(seed: 999)
        let card = maturedCard(fsrs)
        let a = fsrs.review(card, rating: .good, at: epoch.addingTimeInterval(400 * 86_400), using: &rngA)
        let b = fsrs.review(card, rating: .good, at: epoch.addingTimeInterval(400 * 86_400), using: &rngB)
        #expect(a.due == b.due)
    }

    @Test func fuzzingProducesWholeDayIntervalsNearTheUnfuzzedValue() {
        let plain = FSRS(enableFuzzing: false)
        let fuzzy = FSRS(enableFuzzing: true)
        let reviewedAt = epoch.addingTimeInterval(400 * 86_400)
        let card = maturedCard(plain)

        let baseline = plain.review(card, rating: .good, at: reviewedAt).due
            .timeIntervalSince(reviewedAt) / 86_400

        for seed in UInt64(1)...50 {
            var rng = SeededRNG(seed: seed)
            let days = fuzzy.review(card, rating: .good, at: reviewedAt, using: &rng).due
                .timeIntervalSince(reviewedAt) / 86_400
            #expect(days == days.rounded(), "seed \(seed): fuzzed interval must be whole days")
            #expect(days >= 2, "seed \(seed): fuzz must never schedule sooner than 2 days")
            // Fuzz widens by at most 5% beyond the 20-day mark, so a generous
            // 30% band still catches a fuzz that has come loose from its baseline.
            #expect(abs(days - baseline) <= baseline * 0.3,
                    "seed \(seed): \(days) strayed too far from \(baseline)")
        }
    }

    @Test func fuzzingLeavesShortLearningIntervalsAlone() {
        let fuzzy = FSRS(enableFuzzing: true)
        var rngA = SeededRNG(seed: 3)
        var rngB = SeededRNG(seed: 77)
        // A brand-new card is in .learning, where fuzz must not apply at all.
        let a = fuzzy.review(FSRSCard(), rating: .good, at: epoch, using: &rngA)
        let b = fuzzy.review(FSRSCard(), rating: .good, at: epoch, using: &rngB)
        #expect(a.due == b.due)
        #expect(a.due == epoch.addingTimeInterval(600))
    }

    @Test func fuzzingLeavesLongLearningStepsAloneToo() {
        // The short default steps are already below the 2.5-day fuzz threshold, so
        // only a deck configured with multi-day learning steps can show whether
        // fuzz is correctly restricted to cards in .review.
        let fuzzy = FSRS(learningSteps: [3 * 86_400, 5 * 86_400], enableFuzzing: true)
        var rngA = SeededRNG(seed: 5)
        var rngB = SeededRNG(seed: 4_242)
        let a = fuzzy.review(FSRSCard(), rating: .good, at: epoch, using: &rngA)
        let b = fuzzy.review(FSRSCard(), rating: .good, at: epoch, using: &rngB)
        #expect(a.state == .learning)
        #expect(a.due == b.due)
        #expect(a.due == epoch.addingTimeInterval(5 * 86_400))
    }

    @Test func fuzzingLeavesOneDayReviewIntervalsAlone() {
        let fuzzy = FSRS(enableFuzzing: true)
        // Stability this low schedules the minimum one-day interval, which sits
        // under the 2.5-day threshold and so must come back untouched.
        let card = FSRSCard(stability: 0.01, difficulty: 5,
                            lastReview: epoch, state: .review, step: nil)
        let at = epoch.addingTimeInterval(86_400)

        for seed in UInt64(1)...25 {
            var rng = SeededRNG(seed: seed)
            let due = fuzzy.review(card, rating: .good, at: at, using: &rng).due
            #expect(due == at.addingTimeInterval(86_400), "seed \(seed): short interval was fuzzed")
        }
    }

    @Test func theSameSeedAlwaysSchedulesTheSameDay() {
        let fuzzy = FSRS(enableFuzzing: true)
        let card = maturedCard(FSRS(enableFuzzing: false))
        let at = epoch.addingTimeInterval(400 * 86_400)
        var first = SeededRNG(seed: 42)
        var second = SeededRNG(seed: 42)
        #expect(fuzzy.review(card, rating: .good, at: at, using: &first).due
                == fuzzy.review(card, rating: .good, at: at, using: &second).due)
    }
}

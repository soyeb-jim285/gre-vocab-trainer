import Foundation
import Testing
@testable import GRECore

/// Golden vectors produced by the reference implementation (py-fsrs), via
/// `tools/gen_fsrs_vectors.py`. The Swift port has to agree with it exactly --
/// this is a port, not a reinterpretation.
private struct Vectors: Decodable {
    struct Step: Decodable {
        let rating: Int
        let reviewedAt: Date
        let stability: Double
        let difficulty: Double
        let due: Date
        let state: Int
        let step: Int?
    }
    let parameters: [Double]
    let desiredRetention: Double
    let learningStepsMinutes: [Double]
    let relearningStepsMinutes: [Double]
    let maximumIntervalDays: Int
    let cases: [String: [Step]]
}

private let vectors: Vectors = {
    let url = Bundle.module.url(forResource: "fsrs_vectors", withExtension: "json")!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try! decoder.decode(Vectors.self, from: Data(contentsOf: url))
}()

@Suite struct FSRSTests {

    @Test func defaultParametersMatchReference() {
        let fsrs = FSRS()
        #expect(fsrs.parameters.count == 21)
        #expect(fsrs.parameters == vectors.parameters)
        #expect(fsrs.desiredRetention == vectors.desiredRetention)
        #expect(fsrs.maximumIntervalDays == vectors.maximumIntervalDays)
    }

    @Test(arguments: [
        "all_good", "all_again", "easy_graduates", "hard_path",
        "lapse_recovery", "mixed", "long_gap",
    ])
    func matchesReferenceImplementation(caseName: String) throws {
        let steps = try #require(vectors.cases[caseName])
        // Fuzzing randomises intervals on purpose; vectors were generated without it.
        let fsrs = FSRS(enableFuzzing: false)
        var card = FSRSCard()

        for (index, step) in steps.enumerated() {
            let rating = try #require(FSRSRating(rawValue: step.rating))
            card = fsrs.review(card, rating: rating, at: step.reviewedAt)

            let where_ = "\(caseName) step \(index)"
            #expect(card.stability != nil, "\(where_): stability unset")
            #expect(abs((card.stability ?? 0) - step.stability) < 1e-9, "\(where_): stability")
            #expect(abs((card.difficulty ?? 0) - step.difficulty) < 1e-9, "\(where_): difficulty")
            #expect(card.state.rawValue == step.state, "\(where_): state")
            #expect(card.step == step.step, "\(where_): step")
            // Due dates are whole seconds in the reference output.
            #expect(abs(card.due.timeIntervalSince(step.due)) < 1.0, "\(where_): due")
        }
    }

    @Test func newCardIsDueImmediatelyAndUnlearned() {
        let card = FSRSCard()
        #expect(card.stability == nil)
        #expect(card.difficulty == nil)
        #expect(card.state == .learning)
        #expect(card.lastReview == nil)
    }

    @Test func retrievabilityDecaysToDesiredRetentionAfterOneStabilityPeriod() {
        let fsrs = FSRS()
        // A whole-day stability, because elapsed time is floored to whole days --
        // a fractional stability would never be sampled at exactly t == S.
        let epoch = Date(timeIntervalSince1970: 0)
        let card = FSRSCard(stability: 10, difficulty: 5, lastReview: epoch, state: .review)

        let afterOneStability = epoch.addingTimeInterval(10 * 86_400)
        // R(S, S) == 0.9 is the defining property of the FSRS forgetting curve.
        #expect(abs(fsrs.retrievability(card, at: afterOneStability) - 0.9) < 1e-9)
    }

    @Test func retrievabilityIsFlatWithinASingleDay() {
        let fsrs = FSRS()
        let epoch = Date(timeIntervalSince1970: 0)
        let card = FSRSCard(stability: 10, difficulty: 5, lastReview: epoch, state: .review)

        // Elapsed time is floored to whole days, so everything before the
        // 24-hour mark reads as zero days elapsed and scores a flat 1.0.
        #expect(fsrs.retrievability(card, at: epoch.addingTimeInterval(3_600)) == 1.0)
        #expect(fsrs.retrievability(card, at: epoch.addingTimeInterval(86_399)) == 1.0)
        #expect(fsrs.retrievability(card, at: epoch.addingTimeInterval(86_400)) < 1.0)
    }

    @Test func retrievabilityIsZeroForACardNeverReviewed() {
        #expect(FSRS().retrievability(FSRSCard(), at: Date(timeIntervalSince1970: 0)) == 0)
    }

    @Test func retrievabilityIsOneAtTheMomentOfReview() {
        let fsrs = FSRS()
        let now = Date(timeIntervalSince1970: 0)
        let card = fsrs.review(FSRSCard(), rating: .good, at: now)
        #expect(abs(fsrs.retrievability(card, at: now) - 1.0) < 1e-9)
    }
}

@Suite struct FSRSIntervalRoundingTests {

    /// At the default 0.9 retention the interval formula reduces to `round(stability)`,
    /// so these cases isolate the rounding rule itself.
    @Test func roundsHalfIntervalsToEvenLikeTheReference() {
        let fsrs = FSRS()
        // Python's round() is half-to-even: 2.5 -> 2, 3.5 -> 4, 4.5 -> 4.
        #expect(fsrs.nextIntervalDays(2.5) == 2)
        #expect(fsrs.nextIntervalDays(3.5) == 4)
        #expect(fsrs.nextIntervalDays(4.5) == 4)
        #expect(fsrs.nextIntervalDays(5.5) == 6)
    }

    @Test func roundsNonHalfIntervalsNormally() {
        let fsrs = FSRS()
        #expect(fsrs.nextIntervalDays(2.4) == 2)
        #expect(fsrs.nextIntervalDays(2.6) == 3)
        #expect(fsrs.nextIntervalDays(99.5) == 100)
    }

    @Test func clampsIntervalsToAtLeastOneDayAndAtMostTheMaximum() {
        let fsrs = FSRS(maximumIntervalDays: 100)
        #expect(fsrs.nextIntervalDays(0.0001) == 1)
        #expect(fsrs.nextIntervalDays(1_000_000) == 100)
    }
}

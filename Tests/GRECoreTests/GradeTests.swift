import Testing
@testable import GRECore

@Suite struct GradeTests {

    @Test func clampsScoresIntoRange() {
        // Strict structured outputs can't express minimum/maximum across every
        // provider, so out-of-range scores have to be corrected here.
        #expect(Grade(score: 150).score == 100)
        #expect(Grade(score: -20).score == 0)
        #expect(Grade(score: 73).score == 73)
    }

    @Test func mapsStandardScoresToTheFourRatings() {
        func rating(_ score: Int) -> FSRSRating {
            Grade(score: score).rating(strictness: .standard)
        }
        #expect(rating(0) == .again)
        #expect(rating(49) == .again)
        #expect(rating(50) == .hard)
        #expect(rating(69) == .hard)
        #expect(rating(70) == .good)
        #expect(rating(89) == .good)
        #expect(rating(90) == .easy)
        #expect(rating(100) == .easy)
    }

    @Test func lenientGradingPassesAnswersThatStandardWouldFail() {
        let borderline = Grade(score: 45)
        #expect(borderline.rating(strictness: .standard) == .again)
        #expect(borderline.rating(strictness: .lenient) == .hard)
    }

    @Test func strictGradingFailsAnswersThatStandardWouldPass() {
        let borderline = Grade(score: 55)
        #expect(borderline.rating(strictness: .standard) == .hard)
        #expect(borderline.rating(strictness: .strict) == .again)
    }

    @Test(arguments: GradingStrictness.allCases)
    func ratingRisesMonotonicallyWithScore(strictness: GradingStrictness) {
        // A higher score must never map to a worse rating, whatever the setting.
        var previous = FSRSRating.again
        for score in 0...100 {
            let rating = Grade(score: score).rating(strictness: strictness)
            #expect(rating.rawValue >= previous.rawValue,
                    "score \(score) under \(strictness) dropped from \(previous) to \(rating)")
            previous = rating
        }
    }

    @Test(arguments: GradingStrictness.allCases)
    func everyStrictnessCanReachBothExtremes(strictness: GradingStrictness) {
        #expect(Grade(score: 0).rating(strictness: strictness) == .again)
        #expect(Grade(score: 100).rating(strictness: strictness) == .easy)
    }

    @Test func aPerfectScoreIsAlwaysEasyAndAZeroIsAlwaysAgain() {
        for strictness in GradingStrictness.allCases {
            #expect(Grade(score: 100).rating(strictness: strictness) == .easy)
            #expect(Grade(score: 0).rating(strictness: strictness) == .again)
        }
    }
}

import Foundation
import Testing
@testable import GRECore

@Suite struct CardCompetenceTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func evidence(_ mode: StudyMode, _ score: Int, minutesAgo: Double = 0) -> ReviewEvidence {
        ReviewEvidence(mode: mode, score: score, at: now.addingTimeInterval(-minutesAgo * 60))
    }

    // MARK: - Reading the log

    @Test func anEmptyHistoryKnowsNothingAboutAnyMode() {
        let competence = CardCompetence([])
        #expect(competence.totalAttempts == 0)
        for mode in StudyMode.allCases {
            #expect(competence[mode].attempts == 0)
            #expect(competence[mode].accuracy == nil)
            #expect(competence[mode].lastSeen == nil)
        }
    }

    @Test func attemptsAndPassesAreCountedPerMode() {
        let competence = CardCompetence([
            evidence(.multipleChoice, 100), evidence(.multipleChoice, 0),
            evidence(.spelling, 100),
        ])
        #expect(competence[.multipleChoice].attempts == 2)
        #expect(competence[.multipleChoice].passes == 1)
        #expect(competence[.multipleChoice].accuracy == 0.5)
        #expect(competence[.spelling].accuracy == 1)
        #expect(competence[.contextCloze].attempts == 0)
        #expect(competence.totalAttempts == 3)
    }

    @Test func thePassMarkIsTheGoodBandAndDoesNotFollowStrictness() {
        #expect(CardCompetence.passingScore == 70)
        #expect(CardCompetence([evidence(.reverseRecall, 70)])[.reverseRecall].passes == 1)
        #expect(CardCompetence([evidence(.reverseRecall, 69)])[.reverseRecall].passes == 0)
    }

    @Test func lastSeenIsTheMostRecentAttemptWhateverOrderTheLogArrivesIn() {
        let competence = CardCompetence([
            evidence(.spelling, 100, minutesAgo: 5),
            evidence(.spelling, 100, minutesAgo: 90),
        ])
        #expect(competence[.spelling].lastSeen == now.addingTimeInterval(-300))
    }

    // MARK: - Picking what to ask next

    @Test func aModeNeverTriedWinsOutright() {
        // Even against a mode the learner is demonstrably terrible at: you cannot
        // know someone is weak at something they have never been asked to do.
        let competence = CardCompetence([
            evidence(.contextCloze, 0), evidence(.contextCloze, 0), evidence(.contextCloze, 0),
        ])
        #expect(competence.weakest(among: [.contextCloze, .spelling]) == .spelling)
    }

    @Test func onceEverythingHasBeenTriedTheWeakestAccuracyWins() {
        let competence = CardCompetence([
            evidence(.contextCloze, 100), evidence(.contextCloze, 100),
            evidence(.spelling, 100), evidence(.spelling, 0),
            evidence(.reverseRecall, 100),
        ])
        #expect(competence.weakest(among: [.contextCloze, .spelling, .reverseRecall]) == .spelling)
    }

    @Test func equalAccuracyBreaksTowardTheLessPractisedMode() {
        let competence = CardCompetence([
            evidence(.contextCloze, 100), evidence(.contextCloze, 100), evidence(.contextCloze, 100),
            evidence(.spelling, 100),
        ])
        #expect(competence.weakest(among: [.contextCloze, .spelling]) == .spelling)
    }

    @Test func anIdenticalHistoryAlwaysPicksTheSameMode() {
        let log = [evidence(.contextCloze, 100), evidence(.spelling, 100)]
        let candidates: [StudyMode] = [.contextCloze, .spelling]
        let first = CardCompetence(log).weakest(among: candidates)
        for _ in 0..<20 {
            #expect(CardCompetence(log).weakest(among: candidates) == first)
        }
    }

    @Test func onlyTheOfferedCandidatesAreEverReturned() {
        let competence = CardCompetence([evidence(.spelling, 0)])
        let pick = competence.weakest(among: [.multipleChoice, .contextCloze])
        #expect(pick == .multipleChoice || pick == .contextCloze)
    }

    @Test func nothingToChooseFromReturnsNothing() {
        #expect(CardCompetence([]).weakest(among: []) == nil)
    }

    @Test func aRotationWouldHaveKeptDrillingTheStrongMode() {
        // The point of the whole type. Someone who nails recall and fails
        // spelling should be handed spelling, not one-in-three of it.
        let log = (0..<6).flatMap { _ in
            [evidence(.reverseRecall, 100), evidence(.spelling, 0), evidence(.contextCloze, 100)]
        }
        let competence = CardCompetence(log)
        #expect(competence.weakest(among: [.reverseRecall, .spelling, .contextCloze]) == .spelling)
    }
}

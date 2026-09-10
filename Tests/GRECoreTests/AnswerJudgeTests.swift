import Foundation
import Testing
@testable import GRECore

@Suite struct AnswerJudgeTests {

    private static let catalog = try! WordCatalog.bundled()

    private func item(_ mode: StudyMode, word wordID: String = "abate") -> SessionItem {
        SessionItem(card: StudyCard(wordID: wordID), word: Self.catalog[wordID]!, mode: mode)
    }

    // MARK: - What the model still has to do

    @Test func onlyTheWrittenModeNeedsAModel() {
        let written = AnswerDraft.written(definition: "to lessen", sentence: "The storm abated.")
        #expect(AnswerJudge.judge(written, item: item(.defineAndUse)) == nil)

        // And every other draft is answerable here, whatever mode asked it.
        for mode in StudyMode.allCases {
            #expect(AnswerJudge.judge(.gaveUp, item: item(mode)) != nil)
        }
    }

    // MARK: - Giving up

    @Test func givingUpIsRatedAgainOutrightRatherThanMappedFromZero() {
        // A blank answer is the learner telling us they do not know it, which is
        // stronger evidence than a zero score under a lenient threshold.
        for strictness in GradingStrictness.allCases {
            let judgement = AnswerJudge.judge(.gaveUp, item: item(.multipleChoice),
                                              strictness: strictness)
            #expect(judgement?.rating == .again)
            #expect(judgement?.grade.score == 0)
            #expect(judgement?.showsReference == true)
        }
    }

    @Test func givingUpOnAProductionModeRevealsTheWord() {
        #expect(AnswerJudge.judge(.gaveUp, item: item(.reverseRecall))?.detail == "abate")
        #expect(AnswerJudge.judge(.gaveUp, item: item(.spelling))?.detail == "abate")
        // The tap modes already had it on screen.
        #expect(AnswerJudge.judge(.gaveUp, item: item(.multipleChoice))?.detail == "")
    }

    // MARK: - Tapped answers

    @Test func theCorrectChoiceIsADefinitionExceptInClozeWhereItIsTheWord() {
        #expect(AnswerJudge.correctChoice(for: item(.contextCloze)) == "abate")
        for mode in [StudyMode.multipleChoice, .senseInContext] {
            #expect(AnswerJudge.correctChoice(for: item(mode))
                    == Self.catalog["abate"]!.teachingDefinition)
        }
    }

    @Test func tappingTheRightOptionScoresFullAndTheWrongOneScoresNothing() {
        for mode in [StudyMode.multipleChoice, .contextCloze, .senseInContext] {
            let subject = item(mode)
            let right = AnswerJudge.judge(.choice(AnswerJudge.correctChoice(for: subject)), item: subject)
            let wrong = AnswerJudge.judge(.choice("something else entirely"), item: subject)
            #expect(right?.grade.score == 100, "\(mode)")
            #expect(wrong?.grade.score == 0, "\(mode)")
        }
    }

    @Test func clozeIsCheckedByWordIdentityNotByDefinitionText() {
        let subject = item(.contextCloze)
        #expect(AnswerJudge.judge(.choice("abate"), item: subject)?.grade.score == 100)
        #expect(AnswerJudge.judge(.choice(subject.word.teachingDefinition), item: subject)?.grade.score == 0)
    }

    @Test func theFullEntryIsShownWhereItTeachesAndWithheldWhereItIsNoise() {
        let cloze = item(.contextCloze)
        // Multiple choice listed the definition among the options already.
        #expect(AnswerJudge.judge(.choice(AnswerJudge.correctChoice(for: item(.multipleChoice))),
                                  item: item(.multipleChoice))?.showsReference == false)
        // Missing it in context is exactly when the entry helps.
        #expect(AnswerJudge.judge(.choice("wrong"), item: cloze)?.showsReference == true)
        #expect(AnswerJudge.judge(.choice("abate"), item: cloze)?.showsReference == false)
        // A trap word's whole lesson is the two meanings side by side.
        #expect(AnswerJudge.judge(.choice(AnswerJudge.correctChoice(for: item(.senseInContext))),
                                  item: item(.senseInContext))?.showsReference == true)
    }

    @Test func aMissedSenseQuestionNamesWhatWentWrong() {
        let judgement = AnswerJudge.judge(.choice("wrong"), item: item(.senseInContext))
        #expect(judgement?.headline == "That is the everyday meaning")
    }

    // MARK: - Typed answers

    @Test func spellingAndRecallDisagreeAboutATypoOnPurpose() {
        // Spelling is about the letters, so a near miss fails. Recall is about
        // retrieving the word at all, so a near miss passes.
        let typo = AnswerDraft.typed("abaet")
        let spelling = AnswerJudge.judge(typo, item: item(.spelling))
        let recall = AnswerJudge.judge(typo, item: item(.reverseRecall))
        #expect(spelling!.grade.score < recall!.grade.score)
        #expect(spelling!.rating == .again)
        #expect(recall!.rating != .again)
    }

    @Test func typedAnswersMatchTheGraderTheyDelegateTo() {
        for typed in ["abate", "abaet", "abbate", "nonsense", "", "  Abate "] {
            #expect(AnswerJudge.judge(.typed(typed), item: item(.spelling))?.grade
                    == LocalGrader.gradeSpelling(typed: typed, expected: "abate").grade)
            #expect(AnswerJudge.judge(.typed(typed), item: item(.reverseRecall))?.grade
                    == LocalGrader.gradeRecall(typed: typed, expected: "abate"))
        }
    }

    @Test func aMisspellingQuotesBackWhatWasActuallyTyped() {
        let judgement = AnswerJudge.judge(.typed(" abaet "), item: item(.spelling))
        #expect(judgement?.headline == "Spelling is off")
        #expect(judgement?.detail.contains("abaet") == true)
        #expect(judgement?.detail.contains("abate") == true)
    }

    // MARK: - Cross-cutting

    @Test func everyRatingComesFromTheOneScoreMappingUnlessTheLearnerGaveUp() {
        let drafts: [AnswerDraft] = [.choice("abate"), .choice("wrong"), .typed("abate"),
                                     .typed("abaet"), .typed("")]
        for mode in StudyMode.locallyGraded {
            for draft in drafts {
                for strictness in GradingStrictness.allCases {
                    guard let judgement = AnswerJudge.judge(draft, item: item(mode),
                                                            strictness: strictness) else { continue }
                    #expect(judgement.rating == judgement.grade.rating(strictness: strictness),
                            "\(mode) \(draft) \(strictness) drifted from the score mapping")
                }
            }
        }
    }

    @Test func latencyIsIgnoredUntilConfidenceIsSwitchedOn() {
        let subject = item(.multipleChoice)
        let draft = AnswerDraft.choice(AnswerJudge.correctChoice(for: subject))
        #expect(AnswerJudge.judge(draft, item: subject, latency: .seconds(90))?.rating == .easy)
        #expect(AnswerJudge.judge(draft, item: subject, latency: .seconds(90),
                                  confidence: ConfidenceSettings(isEnabled: true))?.rating == .hard)
    }

    @Test func aTrapWordIsJudgedTheSameWayAnyOtherWordIs() throws {
        let flag = try #require(Self.catalog["flag"])
        #expect(flag.isTrap)
        let subject = SessionItem(card: StudyCard(wordID: "flag"), word: flag, mode: .senseInContext)
        #expect(AnswerJudge.judge(.choice(flag.teachingDefinition), item: subject)?.grade.score == 100)
    }
}

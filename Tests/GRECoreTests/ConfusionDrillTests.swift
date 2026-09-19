import Foundation
import Testing
@testable import GRECore

/// Telling near-misses apart, which is what the exam actually asks.
@Suite struct ConfusionDrillTests {

    private static let catalog = try! WordCatalog.bundled()

    private func annotated() throws -> Word {
        try #require(Self.catalog.words.first {
            ($0.confusion?.count ?? 0) >= 2
        })
    }

    @Test func aQuestionPairsTheWordWithAnAnnotatedNeighbour() throws {
        let word = try annotated()
        let question = try #require(ConfusionDrill.question(for: word, from: Self.catalog))
        #expect(question.partner.id != word.id)
        #expect(word.confusion?.contains { $0.with == question.partner.id } == true)
        #expect(!question.distinction.isEmpty)
    }

    @Test func bothWordsAreOffered() throws {
        let word = try annotated()
        let question = try #require(ConfusionDrill.question(for: word, from: Self.catalog))
        #expect(Set(question.options.map(\.id)) == [word.id, question.partner.id])
    }

    @Test func theAnswerIsNotAlwaysInTheSameSlot() throws {
        // Position must never be the tell. Across the dataset both slots have to
        // come up, or the drill teaches tapping rather than the words.
        var first = 0
        var seen = 0
        for word in Self.catalog.words {
            guard let question = ConfusionDrill.question(for: word, from: Self.catalog)
            else { continue }
            seen += 1
            if question.options.first?.id == word.id { first += 1 }
        }
        #expect(seen > 100, "only \(seen) words can be drilled")
        #expect(first > seen / 4 && first < seen * 3 / 4, "\(first) of \(seen) answers came first")
    }

    @Test func theSameWordIsAskedTheSameWayEveryLaunch() throws {
        let word = try annotated()
        let a = ConfusionDrill.question(for: word, from: Self.catalog)
        let b = ConfusionDrill.question(for: word, from: Self.catalog)
        #expect(a?.partner.id == b?.partner.id)
        #expect(a?.options.map(\.id) == b?.options.map(\.id))
    }

    @Test func laterExposuresReachTheOtherNeighbours() throws {
        let word = try annotated()
        let partners = (0..<4).compactMap {
            ConfusionDrill.question(for: word, from: Self.catalog, attempt: $0)?.partner.id
        }
        #expect(Set(partners).count > 1, "always drilled against \(partners.first ?? "-")")
    }

    @Test func aPairTheLearnerHasActuallyMixedUpWins() throws {
        let word = try annotated()
        let all = try #require(word.confusion).map(\.with)
        let troublesome = try #require(all.last)
        let question = ConfusionDrill.question(
            for: word, from: Self.catalog, preferring: [troublesome]
        )
        #expect(question?.partner.id == troublesome)
    }

    @Test func aWordWithNoNeighbourHasNoDrill() throws {
        let plain = try #require(Self.catalog.words.first { $0.confusion?.isEmpty ?? true })
        #expect(ConfusionDrill.question(for: plain, from: Self.catalog) == nil)
        #expect(!ConfusionDrill.isAvailable(for: plain, in: Self.catalog))
        #expect(!Curriculum.candidates(for: plain, aiEnabled: true).contains(.discriminate))
    }

    @Test func theDrillJoinsTheRotationForAnnotatedWords() throws {
        let word = try annotated()
        #expect(Curriculum.candidates(for: word, aiEnabled: false).contains(.discriminate))
    }

    // MARK: - Grading

    private func item(_ word: Word, against partner: String) -> SessionItem {
        SessionItem(
            card: StudyCard(wordID: word.id, reviewCount: 3, isIntroduced: true),
            word: word, mode: .discriminate, confusedWith: partner
        )
    }

    @Test func theRightWordIsTheWordItself() throws {
        let word = try annotated()
        let question = try #require(ConfusionDrill.question(for: word, from: Self.catalog))
        let asked = item(word, against: question.partner.id)
        #expect(AnswerJudge.correctChoice(for: asked) == word.id)

        let right = try #require(AnswerJudge.judge(.choice(word.id), item: asked))
        #expect(right.grade.score == 100)
        let wrong = try #require(AnswerJudge.judge(.choice(question.partner.id), item: asked))
        #expect(wrong.grade.score == 0)
    }

    @Test func theDistinctionIsReadWhicheverWayItWent() throws {
        // A lucky guess still leaves the pair unseparated, so the line shows
        // either way.
        let word = try annotated()
        let question = try #require(ConfusionDrill.question(for: word, from: Self.catalog))
        let asked = item(word, against: question.partner.id)
        for choice in [word.id, question.partner.id] {
            let judged = try #require(AnswerJudge.judge(.choice(choice), item: asked))
            #expect(judged.detail == question.distinction)
        }
    }

    @Test func everyDistinctionNamesBothWords() {
        // The build verifier enforces this; the drill depends on it, because a
        // line that only describes one word explains nothing about the choice.
        for word in Self.catalog.words {
            for pair in word.confusion ?? [] {
                let line = pair.distinction.lowercased()
                #expect(line.contains(word.id.prefix(4)), "\(word.id)|\(pair.with)")
                #expect(line.contains(pair.with.prefix(4)), "\(word.id)|\(pair.with)")
            }
        }
    }
}

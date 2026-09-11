import Foundation
import Testing
@testable import GRECore

/// The data contract for pass one and pass two of the grounding work.
///
/// These are decoding tests, not content tests: the Python verifiers judge
/// whether a hint leaks its own word or a distinction names both halves of a
/// pair. What matters here is that the app can read what was generated, and
/// that a `Word` without the block still decodes, so today's code keeps working
/// against a dataset built before the block existed.
@Suite struct GroundingTests {

    private static let catalog = try! WordCatalog.bundled()

    @Test func everyShippedWordCarriesAGroundingBlock() {
        let missing = Self.catalog.words.filter { $0.grounding == nil }
        #expect(missing.isEmpty, "\(missing.count) words without grounding")
    }

    @Test func theBlockDecodesFromSnakeCaseKeys() throws {
        // The generator writes snake_case because the Python tooling does; the
        // Swift side renames on the way in. A silent mismatch here would leave
        // every field empty rather than failing, so check a known word.
        let eminent = try #require(Self.catalog["eminent"])
        let g = try #require(eminent.grounding)
        #expect(g.acceptedConcepts.count >= 4)
        #expect(g.incorrectAssociations.count >= 2)
        #expect(!g.requiredNuance.isEmpty)
        #expect(!g.mentalHook.isEmpty)
        #expect(!g.semanticHint.isEmpty)
    }

    @Test func eachIncorrectAssociationNamesTheMisconceptionItReveals() throws {
        // An unlabelled wrong answer is just a wrong answer. The label is what
        // lets the grader correct rather than mark.
        for word in Self.catalog.words {
            let g = try #require(word.grounding)
            for association in g.incorrectAssociations {
                #expect(!association.answer.isEmpty, "\(word.id): blank wrong answer")
                #expect(!association.misconception.isEmpty,
                        "\(word.id): wrong answer with no misconception")
            }
        }
    }

    @Test func confusionPairsPointAtWordsInTheDataset() throws {
        // A discrimination drill needs both sides. A pair naming a word the
        // catalog does not hold would produce a card with nothing to compare.
        for word in Self.catalog.words {
            for pair in word.confusion ?? [] {
                #expect(Self.catalog[pair.with] != nil,
                        "\(word.id) is confused with unknown word \(pair.with)")
                #expect(!pair.distinction.isEmpty, "\(word.id): empty distinction")
            }
        }
    }

    @Test func confusionIsRecordedOnBothHalvesOfThePair() throws {
        // Either word can be the one on screen, so the lookup has to work from
        // either side. Storing it once would make the drill depend on which way
        // round the pair happened to be written.
        for word in Self.catalog.words {
            for pair in word.confusion ?? [] {
                let other = try #require(Self.catalog[pair.with])
                #expect(other.confusion?.contains { $0.with == word.id } == true,
                        "\(pair.with) does not name \(word.id) back")
            }
        }
    }

    @Test func aWordWithoutTheBlockStillDecodes() throws {
        // Phase 0 promises the app keeps running against an older dataset.
        let json = """
        {
          "id": "abate", "word": "abate", "ipa": "", "senses": [
            {"pos": "verb", "definition": "to lessen", "examples": [],
             "synonyms": [], "antonyms": []}
          ],
          "sourceLists": ["gregmat"], "listCount": 1, "tier": "extended",
          "zipf": 2.5, "difficulty": "hard", "isTrap": false, "rating": 3
        }
        """
        let word = try JSONDecoder().decode(Word.self, from: Data(json.utf8))
        #expect(word.grounding == nil)
        #expect(word.confusion == nil)
    }

    @Test func aHandBuiltBlockRoundTrips() throws {
        let grounding = Grounding(
            acceptedConcepts: ["ambiguous", "open to two readings"],
            incorrectAssociations: [
                IncorrectAssociation(answer: "dishonest",
                                     misconception: "confuses evasiveness with lying")
            ],
            requiredNuance: "deliberate ambiguity",
            mentalHook: "Two meanings, and that is on purpose.",
            semanticHint: "The word for an answer built to be read two ways."
        )
        let data = try JSONEncoder().encode(grounding)
        #expect(try JSONDecoder().decode(Grounding.self, from: data) == grounding)
    }
}

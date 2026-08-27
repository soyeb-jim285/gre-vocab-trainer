import Foundation
import Testing
@testable import GRECore

/// The hand-written GRE senses are the app's answer to WordNet's ordering,
/// which leads with a tennis player for "court". These pin that down.
@Suite struct GRESenseTests {

    private static let catalog = try! WordCatalog.bundled()

    @Test func everyWordCarriesAGreSense() {
        let missing = Self.catalog.words.filter { $0.gre == nil }
        #expect(missing.isEmpty, "no GRE sense for \(missing.prefix(5).map(\.id))")
    }

    @Test func everySenseIsUsableAsWritten() {
        for word in Self.catalog.words {
            guard let gre = word.gre else { continue }
            #expect(!gre.definition.isEmpty, "\(word.id): empty definition")
            #expect(gre.definition.split(separator: " ").count <= 20, "\(word.id): definition too long")
            #expect(!gre.sentences.isEmpty, "\(word.id): no example sentence")
            #expect(gre.sentences.allSatisfy { $0.count > 20 }, "\(word.id): stub sentence")
        }
    }

    @Test func theTeachingDefinitionPrefersTheGreSense() throws {
        let court = try #require(Self.catalog["court"])
        #expect(court.teachingDefinition == court.gre?.definition)
        #expect(court.teachingDefinition.contains("tennis") == false, "still the tennis player")
    }

    @Test func wordNetSensesAreOrderedToMatchTheGrePartOfSpeech() {
        // The build sorts WordNet's senses so the tested part of speech leads.
        // A handful legitimately have no WordNet synset in that part of speech.
        let mismatched = Self.catalog.words.filter { word in
            guard let gre = word.gre else { return false }
            return word.senses.allSatisfy { $0.pos != gre.pos }
        }
        #expect(Double(mismatched.count) / Double(Self.catalog.words.count) < 0.2,
                "\(mismatched.count) words have no WordNet sense in the tested part of speech")
    }

    @Test func proseNounsNoLongerLeadWithAProperNoun() throws {
        // The words the instance-filter and the hand-written senses were written for.
        for id in ["court", "ravel", "zephyr", "milk", "hector", "acumen", "arch", "cow"] {
            let word = try #require(Self.catalog[id])
            let definition = word.teachingDefinition.lowercased()
            #expect(definition.contains("united states") == false, "\(id): \(definition)")
            #expect(definition.contains("greek god") == false, "\(id): \(definition)")
        }
    }

    @Test func everyWordHasAHandAssignedDifficulty() {
        #expect(Self.catalog.words.allSatisfy { (1...5).contains($0.rating) })
        // All five levels must be used, or ordering by rating does nothing.
        #expect(Set(Self.catalog.words.map(\.rating)) == [1, 2, 3, 4, 5])
    }

    @Test func trapWordsAreNotRatedEasy() {
        // Common word forms whose tested sense is rare. Frequency called these
        // the easiest words in the list; they are among the hardest.
        for id in ["august", "flag", "pine", "base", "catholic", "plastic", "wax", "retiring"] {
            let word = try! #require(Self.catalog[id])
            #expect(word.rating >= 4, "\(id) is rated \(word.rating), which puts it in an early deck")
        }
    }

    @Test func everyWordHasTwoExampleSentences() {
        let thin = Self.catalog.words.filter { ($0.gre?.sentences.count ?? 0) < 2 }
        #expect(thin.isEmpty, "only one sentence for \(thin.prefix(5).map(\.id))")
    }

    @Test func synonymsAvoidRepeatingTheWordItself() {
        for word in Self.catalog.words {
            guard let gre = word.gre else { continue }
            #expect(gre.synonyms.allSatisfy { $0.lowercased() != word.word.lowercased() },
                    "\(word.id) lists itself as a synonym")
        }
    }
}

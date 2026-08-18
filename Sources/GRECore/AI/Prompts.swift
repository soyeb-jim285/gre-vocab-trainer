import Foundation

enum Prompts {

    /// The reference definition is handed to the model on purpose: without it the
    /// model grades against its own recall of the word, which is exactly the
    /// unreliable thing this app is trying to replace.
    static func grade(
        word: String, referenceDefinition: String, partOfSpeech: String,
        learnerDefinition: String, learnerSentence: String
    ) -> [[String: String]] {
        [
            [
                "role": "system",
                "content": """
                You grade GRE vocabulary answers. Judge the learner strictly against \
                the reference definition supplied, not against your own impression of \
                the word.

                Score the definition on meaning, not wording: a correct paraphrase \
                scores full marks. Score the sentence on whether it shows real command \
                of the word -- a grammatical sentence where the word carries no weight \
                scores poorly. Keep feedback to one or two sentences, addressed to the \
                learner. Return the corrected sentence even when the original was fine.
                """,
            ],
            [
                "role": "user",
                "content": """
                Word: \(word) (\(partOfSpeech))
                Reference definition: \(referenceDefinition)

                Learner's definition: \(learnerDefinition)
                Learner's sentence: \(learnerSentence)
                """,
            ],
        ]
    }

    static func deepDive(word: String, definition: String) -> [[String: String]] {
        [
            [
                "role": "system",
                "content": """
                You help a GRE candidate remember a word for good. Give its real \
                etymology, one vivid memory hook, and the nuance that separates it \
                from words it is often confused with. Be concrete and brief.
                """,
            ],
            ["role": "user", "content": "Word: \(word)\nDefinition: \(definition)"],
        ]
    }

    static func coach(recentMisses: [String], recentWins: [String]) -> [[String: String]] {
        [
            [
                "role": "system",
                "content": """
                You review a GRE learner's recent vocabulary practice. Name the \
                patterns in what they get wrong -- word families, registers, shades \
                of meaning -- rather than listing the words back. Two or three focus \
                areas, no more.
                """,
            ],
            [
                "role": "user",
                "content": """
                Recently missed: \(recentMisses.joined(separator: ", "))
                Recently solid: \(recentWins.joined(separator: ", "))
                """,
            ],
        ]
    }
}

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
                scores poorly. The learner was asked to write about their own life, so \
                a personal, informal sentence is expected; judge whether the word fits \
                that situation, not the register. Keep feedback to one or two sentences, \
                addressed to the learner. Return the corrected sentence even when the \
                original was fine.

                Finish with one memorable sentence of your own: concrete, vivid, and \
                built so the word's meaning is obvious from the situation rather than \
                stated. It should be worth remembering, not a dictionary example.
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

    /// Grade a typed meaning against the word's own grounding.
    ///
    /// Every list handed over here exists to take a judgement away from the
    /// model's memory and give it to the dataset: the accepted concepts fix what
    /// counts as right however it is worded, the incorrect associations let a
    /// wrong answer be named rather than merely marked, and the required nuance
    /// fixes the one boundary a grader would otherwise slide around.
    static func meaning(
        word: String, partOfSpeech: String, grounding: Grounding, learnerAnswer: String
    ) -> [[String: String]] {
        let accepted = grounding.acceptedConcepts.map { "- \($0)" }.joined(separator: "\n")
        let wrong = grounding.incorrectAssociations
            .map { "- \($0.answer) => \($0.misconception)" }
            .joined(separator: "\n")
        return [
            [
                "role": "system",
                "content": """
                You grade one answer to the question "what does this word mean?". \
                Judge it only against the material supplied below, never against \
                your own impression of the word.

                Score 0 to 4:
                4  the meaning is right and includes the required nuance
                3  the meaning is right but the nuance is missing or blurred
                2  partly right, or right about a different sense of the word
                1  wrong, but showing some contact with the word
                0  nothing usable, or blank

                Be strict about meaning and indifferent about wording: a correct \
                paraphrase in the learner's own words scores as well as a polished \
                one. Spelling and grammar are not being graded.

                If the answer matches one of the listed wrong answers, copy that \
                line's misconception verbatim into matched_misconception. Otherwise \
                leave it an empty string. Do not invent a misconception.

                Write one or two sentences of feedback addressed to the learner, \
                naming what they missed. Correct them rather than marking them.
                """,
            ],
            [
                "role": "user",
                "content": """
                Word: \(word) (\(partOfSpeech))

                Answers that score full marks:
                \(accepted)

                Required nuance for a 4: \(grounding.requiredNuance)

                Known wrong answers and what each reveals:
                \(wrong)

                Learner's answer: \(learnerAnswer)
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

    /// - Parameter pace: one line on whether the learner is on track for their
    ///   test date, when they have one. Without it the coach can only talk about
    ///   words, which is half the question someone with a deadline is asking.
    static func coach(
        recentMisses: [String], recentWins: [String], pace: String? = nil
    ) -> [[String: String]] {
        [
            [
                "role": "system",
                "content": """
                You review a GRE learner's recent vocabulary practice. Name the \
                patterns in what they get wrong -- word families, registers, shades \
                of meaning -- rather than listing the words back. Two or three focus \
                areas, no more. If you are told about their pace, say plainly \
                whether it is working and what to change; do not soften it.
                """,
            ],
            [
                "role": "user",
                "content": """
                Recently missed: \(recentMisses.joined(separator: ", "))
                Recently solid: \(recentWins.joined(separator: ", "))
                \(pace.map { "Pace: " + $0 } ?? "")
                """,
            ],
        ]
    }
}

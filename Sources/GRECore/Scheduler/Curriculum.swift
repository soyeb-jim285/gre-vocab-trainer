import Foundation

/// What to do with a word this time round.
public enum StudyStep: Equatable, Sendable {
    /// First contact, asked before anything is shown: type what the word means.
    ///
    /// A learner who already knows the word should never be made to sit through
    /// a teaching card for it, and one who does not should meet the word as a
    /// question rather than as an answer. Both facts are unobtainable until they
    /// have been asked, which is why asking comes first.
    case pretest
    /// The word is taught, not tested: shown with its meaning, hook and example.
    ///
    /// Reached either because the pretest went badly, or because there is no key
    /// to grade a written answer with.
    case introduce
    case drill(StudyMode)

    public var mode: StudyMode? {
        switch self {
        case .pretest: .typeMeaning
        case .introduce: nil
        case let .drill(mode): mode
        }
    }
}

/// Which question to ask about a word, given what the learner has already shown
/// they can and cannot do with it.
///
/// This replaces a rotation. Cycling modes by review count means someone who
/// nails recall and fails spelling gets spelling one time in three, which is the
/// opposite of what their history asks for.
public enum Curriculum {

    /// Ways of asking a word that carry real weight once it is held.
    ///
    /// Multiple choice is missing on purpose: it is the recognition floor the
    /// harder steps fall back to, not something to return to once a word is
    /// known. Writing is missing because reaching it is a threshold decision
    /// rather than an evidence one.
    public static func candidates(for word: Word) -> [StudyMode] {
        var modes: [StudyMode] = []
        if !(word.gre?.cloze.isEmpty ?? true) { modes.append(.contextCloze) }
        modes.append(.reverseRecall)
        modes.append(.spelling)
        // Only a word whose everyday sense competes with the tested one has two
        // meanings to tell apart.
        if word.isTrap { modes.append(.senseInContext) }
        return modes
    }

    /// Whether a pretest answer was weak enough that the word should be taught
    /// before the session moves on.
    ///
    /// Two or less on the five-point meaning scale: the learner either had no
    /// idea or had the wrong idea, and both need the card. Three is a hazier
    /// version of the right answer, which the corrective feedback can fix
    /// without stopping to teach.
    public static func teaches(afterMeaningScore score: Int) -> Bool { score <= 2 }

    public static func step(
        for card: StudyCard, word: Word, competence: CardCompetence, settings: SessionSettings
    ) -> StudyStep {
        // First contact is a question, not a lesson. Asking costs one typed
        // answer and buys the two facts teaching cannot: whether this learner
        // already owns the word, and what they think it means if not.
        //
        // The old objection to testing first was that a graded first contact is
        // a guaranteed zero. That held while the only first question was
        // multiple choice, where a blank answer is a lapse. It does not hold for
        // a written answer graded against the word's grounding, which can tell
        // "no idea" from "nearly" and is what decides whether to teach at all.
        //
        // Without a key there is nothing to grade the answer with, so first
        // contact falls back to teaching. This outranks a forced mode either
        // way: forcing a drill says which skill to practise, not that an unseen
        // word should be guessed at.
        if !card.isIntroduced {
            return settings.aiEnabled ? .pretest : .introduce
        }

        // A forced mode drills one skill and overrides the rest -- except that it
        // cannot conjure an API key, so writing without one still falls back
        // rather than stranding the learner on a locked mode, and "which
        // meaning" only exists for words that have two.
        if let forced = settings.forcedMode,
           !forced.needsAI || settings.aiEnabled,
           !forced.needsTrapWord || word.isTrap {
            return .drill(forced)
        }

        // A forgotten word goes back to recognition regardless of how well it
        // once went.
        if card.fsrs.state == .relearning { return .drill(.multipleChoice) }

        // A trap word's whole difficulty is that the familiar meaning is the
        // wrong one, so meet it head on the time after it is introduced -- early
        // enough to correct the assumption before it sets.
        if word.isTrap, card.reviewCount == 1 { return .drill(.senseInContext) }

        if settings.aiEnabled, card.reviewCount >= settings.writingModeAfterReviews {
            return .drill(.defineAndUse)
        }

        // Still shaky: recognition, until there is a memory worth interrogating.
        if card.fsrs.state != .review || Mastery(card: card) <= .learning {
            return .drill(.multipleChoice)
        }

        let pool = candidates(for: word)
        return .drill(competence.weakest(among: pool) ?? .multipleChoice)
    }
}

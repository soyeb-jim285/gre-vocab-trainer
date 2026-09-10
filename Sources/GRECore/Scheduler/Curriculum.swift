import Foundation

/// What to do with a word this time round.
public enum StudyStep: Equatable, Sendable {
    /// First contact, ungraded: the word is taught, not tested.
    case introduce
    case drill(StudyMode)

    public var mode: StudyMode? {
        if case let .drill(mode) = self { return mode }
        return nil
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

    public static func step(
        for card: StudyCard, word: Word, competence: CardCompetence, settings: SessionSettings
    ) -> StudyStep {
        // Never test a word the learner has not met. A graded first contact is a
        // guaranteed lapse, a wasted review and a zero for something they were
        // never shown -- and it teaches the scheduler a fact about the app rather
        // than about the learner. This outranks a forced mode: forcing a drill
        // says which skill to practise, not that an unseen word should be
        // guessed at.
        if card.reviewCount == 0 { return .introduce }

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

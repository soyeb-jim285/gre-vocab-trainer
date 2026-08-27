# Self-paced Decks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace daily-capped sessions with an endless, self-paced scheduler; group words into tier decks of ~25; add mastery levels, deck/global quizzes, and progress views.

**Architecture:** All logic lands in `GRECore` (Foundation-only, tested on Linux): `Deck` chunking on `WordCatalog`, `Mastery` from FSRS stability, `SessionPlanner.next()` returning one item per call, `QuizPlanner` building fixed item lists. The app (`App/GRE`, macOS-only build) wires these into `SessionViewModel`, a new Decks tab, and Progress.

**Tech Stack:** Swift 6, swift-testing, SwiftUI + SwiftData (iOS 26), FSRS-6 port already in repo.

**Spec:** `docs/superpowers/specs/2026-08-27-self-paced-decks-design.md`

## Global Constraints

- GRECore stays Foundation-only; no new dependencies.
- `swift test` must pass on Linux after every GRECore task: `. ./env.sh && swift test`.
- App target cannot be compiled here (no Xcode). App tasks: write carefully, keep every GRECore call covered by `PublicSurfaceTests` (no `@testable`).
- No `Date.now` inside GRECore planners — `now` is always a parameter.
- Deck size target 25: `count = ceil(n/25)`, `size = ceil(n/count)`.
- Mastery thresholds (days of stability): learning `<3`, familiar `>=3`, known `>=21`, mastered `>=90`; no card → new.
- Learning-load cap by recent accuracy: `<60 → 4`, default `8`, `>=85 → 12`; window 15 min.
- Anti-repeat window: last 3 word ids.
- Quiz needs ≥5 studied words; global test default 20; weight `= (1 − R) + 0.05`.
- Mark deliberate shortcuts with `// ponytail:` comments.

---

### Task 1: Decks on the catalog

**Files:**
- Create: `Sources/GRECore/Model/Deck.swift`
- Modify: `Sources/GRECore/Store/WordCatalog.swift`
- Test: `Tests/GRECoreTests/DeckTests.swift`

**Interfaces:**
- Produces: `Deck { id: String, tier: WordTier, index: Int, wordIDs: [String], title: String }`, `WordTier.label`, `WordCatalog.decks: [Deck]`, `WordCatalog.deck(id:)`, `WordCatalog.deck(containing:)`, `WordCatalog.decks(inTier:)`, `Deck.chunk(_:tier:targetSize:)`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/GRECoreTests/DeckTests.swift
import Foundation
import Testing
@testable import GRECore

@Suite struct DeckTests {

    private static let catalog = try! WordCatalog.bundled()

    @Test func everyWordIsInExactlyOneDeck() {
        let ids = Self.catalog.decks.flatMap(\.wordIDs)
        #expect(ids.count == Self.catalog.words.count)
        #expect(Set(ids).count == ids.count)
        for word in Self.catalog.words {
            #expect(Self.catalog.deck(containing: word.id) != nil, "\(word.id) has no deck")
        }
    }

    @Test func decksAreBetween23And25Words() {
        for deck in Self.catalog.decks {
            #expect((23...25).contains(deck.wordIDs.count), "\(deck.id) has \(deck.wordIDs.count)")
        }
    }

    @Test func decksRunCoreThenCommonThenExtendedAndAreNumberedFromOne() {
        let tiers = Self.catalog.decks.map(\.tier)
        #expect(tiers == tiers.sorted())
        for tier in WordTier.allCases {
            let indices = Self.catalog.decks(inTier: tier).map(\.index)
            #expect(indices == Array(1...indices.count))
        }
        #expect(Self.catalog.decks.first?.id == "core-1")
        #expect(Self.catalog.decks.first?.title == "Core 1")
    }

    @Test func wordsInsideATierRunEasiestFirst() {
        for tier in WordTier.allCases {
            let zipfs = Self.catalog.decks(inTier: tier)
                .flatMap(\.wordIDs)
                .compactMap { Self.catalog[$0]?.zipf }
            #expect(zipfs == zipfs.sorted(by: >), "\(tier) is not easiest-first")
        }
    }

    @Test func aDeckOnlyHoldsWordsOfItsTier() {
        for deck in Self.catalog.decks {
            #expect(deck.wordIDs.allSatisfy { Self.catalog[$0]?.tier == deck.tier })
        }
    }

    @Test func chunkingIsDeterministicAndHasNoRuntDeck() {
        let a = Self.catalog.decks.map(\.wordIDs)
        let b = WordCatalog(words: Self.catalog.words).decks.map(\.wordIDs)
        #expect(a == b)
        // 26 words must become 2 decks of 13, not 25 + 1.
        let words = Array(Self.catalog.words(inTier: .core).prefix(26))
        let sizes = Deck.chunk(words, tier: .core).map(\.wordIDs.count)
        #expect(sizes == [13, 13])
    }

    @Test func lookupsRoundTrip() throws {
        let deck = try #require(Self.catalog.deck(id: "common-2"))
        #expect(deck.tier == .common && deck.index == 2)
        let first = try #require(deck.wordIDs.first)
        #expect(Self.catalog.deck(containing: first)?.id == "common-2")
        #expect(Self.catalog.deck(id: "nope-9") == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `. ./env.sh && swift test --filter DeckTests`
Expected: compile error, `Deck` not found.

- [ ] **Step 3: Implement**

```swift
// Sources/GRECore/Model/Deck.swift
import Foundation

/// A study unit of roughly 25 words: one tier, easiest first.
///
/// Decks are computed from the catalog, never stored, so regenerating the
/// dataset may move a word between decks. Progress lives on words, not decks,
/// so nothing is lost when that happens.
public struct Deck: Identifiable, Hashable, Sendable {
    public let id: String
    public let tier: WordTier
    /// 1-based position within the tier.
    public let index: Int
    public let wordIDs: [String]

    public var title: String { "\(tier.label) \(index)" }

    /// Split a tier's words into decks of 23–25: `ceil(n/25)` decks, sizes as
    /// even as they can be, so the last deck is never a runt.
    static func chunk(_ words: [Word], tier: WordTier, targetSize: Int = 25) -> [Deck] {
        guard !words.isEmpty else { return [] }
        let sorted = words.sorted { $0.zipf != $1.zipf ? $0.zipf > $1.zipf : $0.id < $1.id }
        let count = (sorted.count + targetSize - 1) / targetSize
        let base = sorted.count / count
        let extra = sorted.count % count   // the first `extra` decks take one more
        var start = 0
        return (0..<count).map { n in
            let size = base + (n < extra ? 1 : 0)
            defer { start += size }
            return Deck(
                id: "\(tier.rawValue)-\(n + 1)", tier: tier, index: n + 1,
                wordIDs: sorted[start..<start + size].map(\.id)
            )
        }
    }
}

extension WordTier {
    public var label: String {
        switch self {
        case .core: "Core"
        case .common: "Common"
        case .extended: "Extended"
        }
    }
}
```

In `WordCatalog.swift`, add stored properties and init lines:

```swift
    public let decks: [Deck]
    private let deckByWord: [String: String]
    private let deckByID: [String: Deck]
```

inside `init(words:)` after `byDifficulty`:

```swift
        self.decks = WordTier.allCases.sorted().flatMap { tier in
            Deck.chunk(words.filter { $0.tier == tier }, tier: tier)
        }
        self.deckByID = Dictionary(uniqueKeysWithValues: decks.map { ($0.id, $0) })
        self.deckByWord = Dictionary(uniqueKeysWithValues: decks.flatMap { deck in
            deck.wordIDs.map { ($0, deck.id) }
        })
```

and queries at the bottom:

```swift
    public func deck(id: String) -> Deck? { deckByID[id] }

    public func deck(containing wordID: String) -> Deck? {
        deckByWord[wordID].flatMap { deckByID[$0] }
    }

    public func decks(inTier tier: WordTier) -> [Deck] {
        decks.filter { $0.tier == tier }
    }
```

- [ ] **Step 4: Run tests**

Run: `. ./env.sh && swift test --filter DeckTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GRECore/Model/Deck.swift Sources/GRECore/Store/WordCatalog.swift Tests/GRECoreTests/DeckTests.swift
git commit -m "feat: tier decks of ~25 words computed on the catalog"
```

---

### Task 2: Mastery and deck progress

**Files:**
- Create: `Sources/GRECore/Model/Mastery.swift`
- Test: `Tests/GRECoreTests/MasteryTests.swift`

**Interfaces:**
- Produces: `Mastery: Int, Comparable, CaseIterable { new, learning, familiar, known, mastered }`, `Mastery(card:)`, `Mastery(stability:)`, `Mastery.label`, `DeckProgress(deck:cards:)` with `counts`, `total`, `fraction`, `isComplete`, `count(atLeast:)`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/GRECoreTests/MasteryTests.swift
import Foundation
import Testing
@testable import GRECore

@Suite struct MasteryTests {

    private func card(_ id: String = "abate", stability: Double?, reviews: Int = 1) -> StudyCard {
        StudyCard(wordID: id, fsrs: FSRSCard(stability: stability, difficulty: 5, state: .review, step: nil),
                  reviewCount: reviews)
    }

    @Test func noCardIsNew() {
        #expect(Mastery(card: nil) == .new)
        #expect(Mastery(card: StudyCard(wordID: "abate")) == .new, "a card that was never answered is still new")
    }

    @Test func thresholdsFollowStabilityInDays() {
        #expect(Mastery(card: card(stability: nil)) == .learning)
        #expect(Mastery(card: card(stability: 2.9)) == .learning)
        #expect(Mastery(card: card(stability: 3)) == .familiar)
        #expect(Mastery(card: card(stability: 20.9)) == .familiar)
        #expect(Mastery(card: card(stability: 21)) == .known)
        #expect(Mastery(card: card(stability: 89)) == .known)
        #expect(Mastery(card: card(stability: 90)) == .mastered)
        #expect(Mastery(card: card(stability: 400)) == .mastered)
    }

    @Test func levelsAreOrdered() {
        #expect(Mastery.allCases == [.new, .learning, .familiar, .known, .mastered])
        #expect(Mastery.new < Mastery.learning && Mastery.known < Mastery.mastered)
    }

    @Test func deckProgressAveragesLevels() {
        let deck = Deck(id: "t-1", tier: .core, index: 1, wordIDs: ["a", "b", "c", "d"])
        let cards = [
            "a": card("a", stability: 100),   // mastered = 4
            "b": card("b", stability: 30),    // known = 3
            "c": card("c", stability: nil),   // learning = 1
        ]                                     // d: new = 0
        let progress = DeckProgress(deck: deck, cards: cards)
        #expect(progress.total == 4)
        #expect(progress.counts[.mastered] == 1)
        #expect(progress.counts[.new] == 1)
        #expect(abs(progress.fraction - 8.0 / 16.0) < 1e-9)
        #expect(progress.isComplete == false)
        #expect(progress.count(atLeast: .known) == 2)
    }

    @Test func aDeckIsCompleteWhenEveryWordIsAtLeastKnown() {
        let deck = Deck(id: "t-1", tier: .core, index: 1, wordIDs: ["a", "b"])
        let done = DeckProgress(deck: deck, cards: ["a": card("a", stability: 21), "b": card("b", stability: 95)])
        #expect(done.isComplete)
        #expect(DeckProgress(deck: deck, cards: [:]).fraction == 0)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `. ./env.sh && swift test --filter MasteryTests` → compile error.

- [ ] **Step 3: Implement**

```swift
// Sources/GRECore/Model/Mastery.swift
import Foundation

/// How well a word is held, read straight off FSRS stability (days until recall
/// drops to the desired retention). A lapse collapses stability, so a level is
/// lost automatically -- no separate bookkeeping.
public enum Mastery: Int, Comparable, CaseIterable, Sendable {
    case new, learning, familiar, known, mastered

    public init(stability: Double?) {
        switch stability ?? 0 {
        case 90...: self = .mastered
        case 21...: self = .known
        case 3...: self = .familiar
        default: self = .learning
        }
    }

    /// Nil, or a card that has never been answered, is new.
    public init(card: StudyCard?) {
        guard let card, card.reviewCount > 0 else { self = .new; return }
        self.init(stability: card.fsrs.stability)
    }

    public var label: String {
        switch self {
        case .new: "New"
        case .learning: "Learning"
        case .familiar: "Familiar"
        case .known: "Known"
        case .mastered: "Mastered"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where a deck stands, for rings and bars.
public struct DeckProgress: Equatable, Sendable {
    public let counts: [Mastery: Int]
    public let total: Int

    public init(deck: Deck, cards: [String: StudyCard]) {
        let levels = deck.wordIDs.map { Mastery(card: cards[$0]) }
        self.counts = Dictionary(levels.map { ($0, 1) }, uniquingKeysWith: +)
        self.total = levels.count
    }

    /// Mean level over the deck, 0 (all new) to 1 (all mastered).
    public var fraction: Double {
        guard total > 0 else { return 0 }
        let sum = counts.reduce(0) { $0 + $1.key.rawValue * $1.value }
        return Double(sum) / Double(total * Mastery.mastered.rawValue)
    }

    public func count(atLeast level: Mastery) -> Int {
        counts.filter { $0.key >= level }.values.reduce(0, +)
    }

    public var isComplete: Bool { total > 0 && count(atLeast: .known) == total }
}
```

- [ ] **Step 4: Run tests** → `swift test --filter MasteryTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GRECore/Model/Mastery.swift Tests/GRECoreTests/MasteryTests.swift
git commit -m "feat: mastery levels from FSRS stability, deck progress"
```

---

### Task 3: Dynamic planner — `SessionPlanner.next`

**Files:**
- Modify: `Sources/GRECore/Model/StudyCard.swift` (SessionSettings; delete `NewWordOrder`, `difficultyCeiling`)
- Rewrite: `Sources/GRECore/Scheduler/SessionPlanner.swift`
- Rewrite: `Tests/GRECoreTests/SessionPlannerTests.swift`, `Tests/GRECoreTests/ForcedModeTests.swift`
- Modify: `Tests/GRECoreTests/DifficultyTests.swift` (delete `NewWordOrderTests`, `AdaptiveDifficultyTests` suites; keep `WordDifficultyTests`)
- Modify: `Tests/GRECoreTests/PublicSurfaceTests.swift`

**Interfaces:**
- Consumes: `Deck`, `Mastery`, `WordCatalog.decks`, `FSRS.retrievability`.
- Produces:
  ```swift
  public struct SessionSettings {
      strictness, aiEnabled, writingModeAfterReviews, forcedMode, currentDeckID: String?
      init(strictness: = .standard, aiEnabled: = true, writingModeAfterReviews: = 3,
           forcedMode: = nil, currentDeckID: = nil)
  }
  SessionPlanner.next(cards:catalog:settings:scheduler:recentAccuracy:recentWordIDs:allowEarly:now:) -> SessionItem?
  SessionPlanner.nextDue(cards:now:) -> Date?
  SessionPlanner.learningLoadCap(forAccuracy:) -> Int
  SessionPlanner.mode(for:settings:) -> StudyMode   // internal
  ```

- [ ] **Step 1: Replace `SessionSettings` and delete `NewWordOrder`**

In `StudyCard.swift`, delete the `NewWordOrder` enum and the `extension SessionSettings { difficultyCeiling }`. Replace the settings struct:

```swift
public struct SessionSettings: Equatable, Sendable {
    public var strictness: GradingStrictness
    /// False when no API key is configured, which locks the graded mode.
    public var aiEnabled: Bool
    /// Reviews a word must have before it graduates to writing practice.
    /// Zero starts there immediately; the default eases in through the local modes.
    public var writingModeAfterReviews: Int
    /// Drills one mode for the whole session. Nil follows the automatic ladder.
    public var forcedMode: StudyMode?
    /// Deck new words are drawn from. Nil means the first deck.
    public var currentDeckID: String?

    public init(
        strictness: GradingStrictness = .standard, aiEnabled: Bool = true,
        writingModeAfterReviews: Int = 3, forcedMode: StudyMode? = nil,
        currentDeckID: String? = nil
    ) {
        self.strictness = strictness
        self.aiEnabled = aiEnabled
        self.writingModeAfterReviews = writingModeAfterReviews
        self.forcedMode = forcedMode
        self.currentDeckID = currentDeckID
    }
}
```

- [ ] **Step 2: Write the failing planner tests** (replace file)

```swift
// Tests/GRECoreTests/SessionPlannerTests.swift
import Foundation
import Testing
@testable import GRECore

@Suite struct SessionPlannerTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let fsrs = FSRS(enableFuzzing: false)

    private func seen(
        _ id: String, dueIn days: Double, reviews: Int = 3, stability: Double = 10,
        lastReviewDaysAgo: Double = 1, state: FSRSState = .review
    ) -> StudyCard {
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: stability, difficulty: 5,
                           due: now.addingTimeInterval(days * 86_400),
                           lastReview: now.addingTimeInterval(-lastReviewDaysAgo * 86_400),
                           state: state, step: state == .review ? nil : 0),
            reviewCount: reviews
        )
    }

    /// A card still inside the learning steps, due `minutes` from now.
    private func learning(_ id: String, dueInMinutes minutes: Double) -> StudyCard {
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: 1, difficulty: 5, due: now.addingTimeInterval(minutes * 60),
                           lastReview: now.addingTimeInterval(-60), state: .learning, step: 1),
            reviewCount: 1
        )
    }

    private func next(
        _ cards: [StudyCard], settings: SessionSettings = SessionSettings(aiEnabled: false),
        accuracy: Double? = nil, recent: [String] = [], early: Bool = false
    ) -> SessionItem? {
        SessionPlanner.next(
            cards: cards, catalog: Self.catalog, settings: settings, scheduler: fsrs,
            recentAccuracy: accuracy, recentWordIDs: recent, allowEarly: early, now: now
        )
    }

    // MARK: - Due reviews first

    @Test func aDueCardBeatsANewWord() {
        #expect(next([seen("abate", dueIn: -1)])?.card.wordID == "abate")
    }

    @Test func aCardDueAtThisExactMomentIsDue() {
        #expect(next([seen("abate", dueIn: 0)])?.card.wordID == "abate")
    }

    @Test func theMostLikelyForgottenCardComesFirst() {
        // Same overdue-ness; the weaker memory (lower stability, older review) is at more risk.
        let strong = seen("abate", dueIn: -1, stability: 60, lastReviewDaysAgo: 30)
        let weak = seen("laconic", dueIn: -1, stability: 5, lastReviewDaysAgo: 30)
        #expect(next([strong, weak])?.card.wordID == "laconic")
    }

    @Test func relearningBreaksTiesAheadOfReview() {
        let review = seen("abate", dueIn: -1, stability: 5, lastReviewDaysAgo: 3)
        let lapsed = seen("laconic", dueIn: -1, stability: 5, lastReviewDaysAgo: 3, state: .relearning)
        #expect(next([review, lapsed])?.card.wordID == "laconic")
    }

    @Test func aWordMissingFromTheCatalogIsSkippedRatherThanCrashing() {
        let item = next([seen("thiswordwasremoved", dueIn: -1), seen("abate", dueIn: -1)])
        #expect(item?.card.wordID == "abate")
    }

    // MARK: - Anti-repeat

    @Test func aJustShownWordIsNotShownAgainWhileOthersWait() {
        let cards = [seen("abate", dueIn: -2), seen("laconic", dueIn: -1)]
        #expect(next(cards, recent: ["abate"])?.card.wordID == "laconic")
    }

    @Test func aJustShownWordComesBackWhenNothingElseQualifies() {
        // Rated Again a minute ago, and nothing else is due: better to repeat than to stall.
        let cards = [learning("abate", dueInMinutes: 0)]
        let item = next(cards, settings: SessionSettings(aiEnabled: false, currentDeckID: "extended-52"), recent: ["abate"])
        // A new word from the deck is still preferred over repeating...
        #expect(item?.card.reviewCount == 0)
        // ...but with the whole catalog studied, the repeat wins over nothing.
        let everything = Self.catalog.words.map { seen($0.id, dueIn: 5) } + cards
        #expect(next(everything, recent: ["abate"])?.card.wordID == "abate")
    }

    // MARK: - Learning-load cap

    @Test func theCapFollowsRecentAccuracy() {
        #expect(SessionPlanner.learningLoadCap(forAccuracy: nil) == 8)
        #expect(SessionPlanner.learningLoadCap(forAccuracy: 59) == 4)
        #expect(SessionPlanner.learningLoadCap(forAccuracy: 60) == 8)
        #expect(SessionPlanner.learningLoadCap(forAccuracy: 84.9) == 8)
        #expect(SessionPlanner.learningLoadCap(forAccuracy: 85) == 12)
    }

    @Test func atTheCapAnUpcomingLearningCardIsServedEarlyInsteadOfANewWord() {
        let inFlight = (0..<8).map { learning(Self.catalog.words[$0].id, dueInMinutes: Double($0) + 2) }
        let item = next(inFlight)
        #expect(item?.card.reviewCount == 1)
        #expect(item?.card.wordID == Self.catalog.words[0].id, "soonest due should be served")
    }

    @Test func belowTheCapANewWordIsIntroduced() {
        let inFlight = (0..<7).map { learning(Self.catalog.words[$0].id, dueInMinutes: Double($0) + 2) }
        #expect(next(inFlight)?.card.reviewCount == 0)
    }

    @Test func aStrugglingLearnerHitsTheCapSooner() {
        let inFlight = (0..<4).map { learning(Self.catalog.words[$0].id, dueInMinutes: Double($0) + 2) }
        #expect(next(inFlight, accuracy: 40)?.card.reviewCount == 1)
        #expect(next(inFlight, accuracy: 90)?.card.reviewCount == 0)
    }

    @Test func learningCardsDueBeyondTheWindowDoNotCountTowardTheCap() {
        let later = (0..<12).map { learning(Self.catalog.words[$0].id, dueInMinutes: 30) }
        #expect(next(later)?.card.reviewCount == 0)
    }

    // MARK: - New words from the current deck

    @Test func withNoDeckChosenNewWordsComeFromTheFirstDeck() throws {
        let item = try #require(next([]))
        #expect(item.card.reviewCount == 0)
        #expect(item.card.wordID == Self.catalog.decks[0].wordIDs[0])
        #expect(item.mode == .multipleChoice)
    }

    @Test func newWordsComeFromTheChosenDeckInOrder() throws {
        let deck = try #require(Self.catalog.deck(id: "common-3"))
        let settings = SessionSettings(aiEnabled: false, currentDeckID: deck.id)
        #expect(next([], settings: settings)?.card.wordID == deck.wordIDs[0])
        let studied = deck.wordIDs.prefix(2).map { seen($0, dueIn: 5) }
        #expect(next(studied, settings: settings)?.card.wordID == deck.wordIDs[2])
    }

    @Test func anExhaustedDeckAdvancesToTheNextOne() throws {
        let deck = try #require(Self.catalog.deck(id: "core-1"))
        let nextDeck = try #require(Self.catalog.deck(id: "core-2"))
        let studied = deck.wordIDs.map { seen($0, dueIn: 5) }
        let item = next(studied, settings: SessionSettings(aiEnabled: false, currentDeckID: deck.id))
        #expect(item?.card.wordID == nextDeck.wordIDs[0])
    }

    @Test func theLastDeckWrapsAroundToUnstudiedEarlierDecks() throws {
        let last = try #require(Self.catalog.decks.last)
        let studied = last.wordIDs.map { seen($0, dueIn: 5) }
        let item = next(studied, settings: SessionSettings(aiEnabled: false, currentDeckID: last.id))
        #expect(item?.card.wordID == Self.catalog.decks[0].wordIDs[0])
    }

    @Test func anUnknownDeckIDFallsBackToTheFirstDeck() {
        let item = next([], settings: SessionSettings(aiEnabled: false, currentDeckID: "gone-7"))
        #expect(item?.card.wordID == Self.catalog.decks[0].wordIDs[0])
    }

    // MARK: - Caught up

    @Test func nothingDueAndNothingNewReturnsNil() {
        let everything = Self.catalog.words.map { seen($0.id, dueIn: 5) }
        #expect(next(everything) == nil)
    }

    @Test func allowEarlyServesTheWeakestMemoryWhenCaughtUp() {
        var everything = Self.catalog.words.map { seen($0.id, dueIn: 5, stability: 100) }
        everything[7] = seen(everything[7].wordID, dueIn: 5, stability: 3, lastReviewDaysAgo: 2)
        let item = next(everything, early: true)
        #expect(item?.card.wordID == everything[7].wordID)
    }

    @Test func nextDueIsTheSoonestFutureDueDate() {
        let cards = [seen("abate", dueIn: 3), seen("laconic", dueIn: 1), seen("acumen", dueIn: -1)]
        #expect(SessionPlanner.nextDue(cards: cards, now: now) == now.addingTimeInterval(86_400))
        #expect(SessionPlanner.nextDue(cards: [], now: now) == nil)
    }

    // MARK: - Mode ladder

    private func mode(_ card: StudyCard, ai: Bool = true, writingAfter: Int = 3) -> StudyMode {
        SessionPlanner.mode(for: card, settings: SessionSettings(aiEnabled: ai, writingModeAfterReviews: writingAfter))
    }

    @Test func aBrandNewWordStartsWithMultipleChoice() {
        #expect(mode(StudyCard(wordID: "abate")) == .multipleChoice)
    }

    @Test func modesFollowMemoryStrength() {
        #expect(mode(seen("abate", dueIn: 0, reviews: 1, stability: 2), ai: false) == .multipleChoice)
        #expect(mode(seen("abate", dueIn: 0, reviews: 1, stability: 10), ai: false) == .reverseRecall)
        #expect(mode(seen("abate", dueIn: 0, reviews: 2, stability: 10), ai: false) == .spelling)
        #expect(mode(seen("abate", dueIn: 0, reviews: 3, stability: 10), ai: false) == .reverseRecall)
        #expect(mode(seen("abate", dueIn: 0, reviews: 3, stability: 10)) == .defineAndUse)
    }

    @Test func aLapsedWordDropsBackToMultipleChoice() {
        let lapsed = seen("abate", dueIn: 0, reviews: 9, stability: 30, state: .relearning)
        #expect(mode(lapsed) == .multipleChoice)
        #expect(mode(lapsed, writingAfter: 0) == .multipleChoice)
    }

    @Test func aCardStillInLearningStepsStaysOnMultipleChoice() {
        #expect(mode(learning("abate", dueInMinutes: 0), ai: false) == .multipleChoice)
    }

    @Test func withoutAnApiKeyTheAiModeIsNeverScheduled() {
        for reviews in 0..<12 {
            #expect(mode(seen("abate", dueIn: 0, reviews: reviews), ai: false) != .defineAndUse)
        }
    }
}

@Suite struct WritingModeThresholdTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(reviews: Int) -> StudyCard {
        StudyCard(
            wordID: "abate",
            fsrs: FSRSCard(stability: 10, difficulty: 5, due: now.addingTimeInterval(-86_400),
                           lastReview: now.addingTimeInterval(-172_800), state: .review, step: nil),
            reviewCount: reviews
        )
    }

    private func mode(reviews: Int, writingAfter: Int, ai: Bool = true) -> StudyMode {
        SessionPlanner.mode(
            for: card(reviews: reviews),
            settings: SessionSettings(aiEnabled: ai, writingModeAfterReviews: writingAfter)
        )
    }

    @Test func theDefaultThresholdKeepsTheExistingLadder() {
        #expect(SessionSettings().writingModeAfterReviews == 3)
        #expect(mode(reviews: 1, writingAfter: 3) == .reverseRecall)
        #expect(mode(reviews: 2, writingAfter: 3) == .spelling)
        #expect(mode(reviews: 3, writingAfter: 3) == .defineAndUse)
    }

    @Test func aThresholdOfZeroGoesStraightToWriting() {
        #expect(mode(reviews: 0, writingAfter: 0) == .defineAndUse)
        #expect(mode(reviews: 7, writingAfter: 0) == .defineAndUse)
    }

    @Test func aThresholdOfOneMeetsTheWordThenWritesAboutIt() {
        #expect(mode(reviews: 0, writingAfter: 1) == .multipleChoice)
        #expect(mode(reviews: 1, writingAfter: 1) == .defineAndUse)
    }

    @Test func aHighThresholdDelaysWritingAndKeepsCyclingLocalModes() {
        #expect(mode(reviews: 5, writingAfter: 99) != .defineAndUse)
        #expect(mode(reviews: 40, writingAfter: 99) != .defineAndUse)
    }

    @Test func noApiKeyOverridesEvenAZeroThreshold() {
        #expect(mode(reviews: 0, writingAfter: 0, ai: false) != .defineAndUse)
        #expect(mode(reviews: 9, writingAfter: 0, ai: false) != .defineAndUse)
    }

    @Test(arguments: 0...6)
    func belowTheThresholdEveryModeIsLocallyGraded(reviews: Int) {
        let mode = mode(reviews: reviews, writingAfter: 99)
        #expect(StudyMode.locallyGraded.contains(mode))
    }
}
```

Replace `ForcedModeTests.swift`:

```swift
import Foundation
import Testing
@testable import GRECore

/// A forced mode drills one skill for a whole session. It overrides the ladder,
/// but not the API key -- having no key is a hard constraint, not a preference.
@Suite struct ForcedModeTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(reviews: Int, state: FSRSState = .review) -> StudyCard {
        StudyCard(
            wordID: "abate",
            fsrs: FSRSCard(stability: 10, difficulty: 5, due: now.addingTimeInterval(-86_400),
                           lastReview: now.addingTimeInterval(-172_800), state: state, step: nil),
            reviewCount: reviews
        )
    }

    private func mode(forced: StudyMode?, reviews: Int, ai: Bool = true, writingAfter: Int = 3) -> StudyMode {
        SessionPlanner.mode(
            for: card(reviews: reviews),
            settings: SessionSettings(aiEnabled: ai, writingModeAfterReviews: writingAfter, forcedMode: forced)
        )
    }

    @Test func autoIsTheDefault() {
        #expect(SessionSettings().forcedMode == nil)
    }

    @Test(arguments: StudyMode.allCases)
    func forcingAModeAppliesItWhateverTheHistory(forced: StudyMode) {
        for reviews in [0, 1, 2, 3, 9] {
            #expect(mode(forced: forced, reviews: reviews) == forced)
        }
        #expect(SessionPlanner.mode(for: card(reviews: 4, state: .relearning),
                                    settings: SessionSettings(forcedMode: forced)) == forced)
    }

    @Test func forcingAModeAlsoAppliesToBrandNewWords() {
        let item = SessionPlanner.next(
            cards: [], catalog: Self.catalog, settings: SessionSettings(aiEnabled: false, forcedMode: .spelling),
            scheduler: FSRS(), recentAccuracy: nil, recentWordIDs: [], now: now
        )
        #expect(item?.mode == .spelling)
    }

    @Test func forcingWritingWithoutAKeyFallsBackToLocalModes() {
        for reviews in [0, 1, 2, 5] {
            let m = mode(forced: .defineAndUse, reviews: reviews, ai: false)
            #expect(m != .defineAndUse)
            #expect(StudyMode.locallyGraded.contains(m))
        }
    }

    @Test func forcingALocalModeWorksWithoutAKey() {
        #expect(mode(forced: .spelling, reviews: 0, ai: false) == .spelling)
        #expect(mode(forced: .spelling, reviews: 4, ai: false) == .spelling)
    }

    @Test func theWritingThresholdIsIgnoredWhileAModeIsForced() {
        #expect(mode(forced: .defineAndUse, reviews: 0, writingAfter: 99) == .defineAndUse)
    }
}
```

In `DifficultyTests.swift` delete the `NewWordOrderTests` and `AdaptiveDifficultyTests` suites entirely (keep `WordDifficultyTests`).

In `PublicSurfaceTests.swift`:
- line 17: `_ = SessionSettings(strictness: .standard, aiEnabled: false)`
- replace the "Scheduling round trip" block with:
```swift
        let card = StudyCard(wordID: word.id)
        let settings = SessionSettings(aiEnabled: false, currentDeckID: catalog.decks.first?.id)
        let item = SessionPlanner.next(
            cards: [card], catalog: catalog, settings: settings, scheduler: FSRS(),
            recentAccuracy: 72, recentWordIDs: [], allowEarly: false, now: .now
        )
        if let item { _ = (item.card, item.word, item.mode) }
        _ = SessionPlanner.nextDue(cards: [card], now: .now)
        _ = SessionPlanner.learningLoadCap(forAccuracy: 72)
        // Decks and mastery, as the Decks tab and Progress read them
        _ = catalog.decks.map { ($0.id, $0.title, $0.tier, $0.index, $0.wordIDs) }
        _ = catalog.decks(inTier: .core)
        _ = catalog.deck(id: "core-1")
        _ = catalog.deck(containing: word.id)
        _ = WordTier.core.label
        _ = Mastery(card: card).label
        _ = Mastery(stability: 5)
        _ = Mastery.allCases.map(\.rawValue)
        let progress = DeckProgress(deck: catalog.decks[0], cards: [word.id: card])
        _ = (progress.counts, progress.total, progress.fraction, progress.isComplete, progress.count(atLeast: .known))
```
- replace `_ = SessionSettings(aiEnabled: true, writingModeAfterReviews: 0, forcedMode: .spelling, newWordOrder: .easiestFirst)` with `_ = SessionSettings(aiEnabled: true, writingModeAfterReviews: 0, forcedMode: .spelling)`
- delete `_ = NewWordOrder.allCases.map(\.rawValue)` and `_ = SessionSettings.difficultyCeiling(forAccuracy: 80)`.

- [ ] **Step 3: Run to verify it fails** → `swift test` compile errors on `next`.

- [ ] **Step 4: Rewrite `SessionPlanner.swift`**

```swift
import Foundation

/// Picks the next thing to study. Called after every answer with fresh card
/// state, so a word rated Again a minute ago is back in the queue immediately.
public enum SessionPlanner {

    /// How far ahead a learning card counts as "in flight".
    static let loadWindow: TimeInterval = 15 * 60
    /// How many just-shown words to keep out of the way.
    public static let repeatWindow = 3

    /// The next item, or nil when nothing is due and there are no new words
    /// left (pass `allowEarly` to review the weakest memory ahead of time).
    ///
    /// - Parameters:
    ///   - recentAccuracy: mean score (0...100) over the learner's recent answers;
    ///     drives how many new words they can juggle at once. Nil means no history.
    ///   - recentWordIDs: words just shown, newest last. Avoided unless nothing else qualifies.
    public static func next(
        cards: [StudyCard], catalog: WordCatalog, settings: SessionSettings,
        scheduler: FSRS, recentAccuracy: Double?, recentWordIDs: [String],
        allowEarly: Bool = false, now: Date
    ) -> SessionItem? {
        let recent = Set(recentWordIDs.suffix(repeatWindow))
        let known = cards.filter { catalog[$0.wordID] != nil }
        let fresh = known.filter { !recent.contains($0.wordID) }

        func item(_ card: StudyCard) -> SessionItem? {
            catalog[card.wordID].map { SessionItem(card: card, word: $0, mode: mode(for: card, settings: settings)) }
        }

        // 1. Due now, most likely forgotten first.
        if let due = mostAtRisk(fresh.filter { $0.fsrs.due <= now }, scheduler: scheduler, now: now) {
            return item(due)
        }

        // 2. Too many words half-learned: serve the soonest of them early rather
        //    than piling on another. The cap follows how the learner is doing.
        let inFlight = fresh.filter {
            $0.fsrs.state != .review && $0.fsrs.due <= now.addingTimeInterval(loadWindow)
        }
        if inFlight.count >= learningLoadCap(forAccuracy: recentAccuracy),
           let soonest = inFlight.min(by: { $0.fsrs.due < $1.fsrs.due }) {
            return item(soonest)
        }

        // 3. A new word from the current deck, then the decks after it.
        let studied = Set(known.map(\.wordID))
        if let word = nextNewWord(catalog: catalog, from: settings.currentDeckID, excluding: studied) {
            return item(StudyCard(wordID: word.id))
        }

        // 4. Only the just-shown words are due: repeating beats stalling.
        if let due = mostAtRisk(known.filter { $0.fsrs.due <= now }, scheduler: scheduler, now: now) {
            return item(due)
        }

        // 5. Caught up. Early review only on request.
        guard allowEarly else { return nil }
        let pool = fresh.isEmpty ? known : fresh
        return mostAtRisk(pool, scheduler: scheduler, now: now).flatMap(item)
    }

    /// When the next card falls due, for the caught-up screen.
    public static func nextDue(cards: [StudyCard], now: Date) -> Date? {
        cards.map(\.fsrs.due).filter { $0 > now }.min()
    }

    /// How many learning/relearning cards may be in flight before new words pause.
    public static func learningLoadCap(forAccuracy accuracy: Double?) -> Int {
        switch accuracy {
        case .some(..<60): 4
        case .some(85...): 12
        default: 8
        }
    }

    /// Lowest retrievability first; relearning, then earlier due, break ties.
    private static func mostAtRisk(_ cards: [StudyCard], scheduler: FSRS, now: Date) -> StudyCard? {
        cards.min { a, b in
            let ra = scheduler.retrievability(a.fsrs, at: now)
            let rb = scheduler.retrievability(b.fsrs, at: now)
            if ra != rb { return ra < rb }
            if (a.fsrs.state == .relearning) != (b.fsrs.state == .relearning) {
                return a.fsrs.state == .relearning
            }
            return a.fsrs.due < b.fsrs.due
        }
    }

    /// First unstudied word from the chosen deck onward, wrapping round so a
    /// learner who jumped ahead still gets the decks they skipped.
    private static func nextNewWord(catalog: WordCatalog, from deckID: String?, excluding studied: Set<String>) -> Word? {
        let decks = catalog.decks
        guard !decks.isEmpty else { return nil }
        let start = decks.firstIndex { $0.id == deckID } ?? 0
        for offset in 0..<decks.count {
            let deck = decks[(start + offset) % decks.count]
            if let id = deck.wordIDs.first(where: { !studied.contains($0) }) {
                return catalog[id]
            }
        }
        return nil
    }

    /// Modes get harder as the memory gets stronger: recognise it, recall it,
    /// spell it, then actually use it.
    ///
    /// Writing is the exercise the app exists for, so how soon a word reaches it
    /// is a setting rather than a constant -- the default eases in, zero starts
    /// there. A lapsed word drops back to recognition whatever the setting.
    static func mode(for card: StudyCard, settings: SessionSettings) -> StudyMode {
        // A forced mode drills one skill and overrides the ladder entirely --
        // except that it cannot conjure an API key, so writing without one
        // still falls back rather than stranding the learner on a locked mode.
        if let forced = settings.forcedMode, !forced.needsAI || settings.aiEnabled {
            return forced
        }
        if card.fsrs.state == .relearning { return .multipleChoice }
        if settings.aiEnabled, card.reviewCount >= settings.writingModeAfterReviews {
            return .defineAndUse
        }
        if card.fsrs.state != .review || Mastery(card: card) <= .learning { return .multipleChoice }
        return card.reviewCount % 2 == 1 ? .reverseRecall : .spelling
    }
    // ponytail: FSRS parameters stay at the defaults. Fitting them to the
    // learner's own review log needs an optimiser and ~1000 reviews; add when
    // someone has that many.
}
```

- [ ] **Step 5: Run the full suite** → `. ./env.sh && swift test` all PASS. Fix anything the retrievability tie-breaking surprises (retrievability is whole-day granular; the tests above choose stabilities and ages far enough apart).

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat: self-paced planner with adaptive learning load and mastery-based modes"
```

---

### Task 4: QuizPlanner

**Files:**
- Create: `Sources/GRECore/Scheduler/QuizPlanner.swift`
- Test: `Tests/GRECoreTests/QuizPlannerTests.swift`
- Modify: `Tests/GRECoreTests/PublicSurfaceTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum QuizPlanner {
      public static let minimumWords = 5
      public static func deckTest(deck: Deck, cards: [StudyCard], catalog: WordCatalog, seed: UInt64) -> [SessionItem]
      public static func globalTest(cards: [StudyCard], catalog: WordCatalog, scheduler: FSRS,
                                    count: Int = 20, seed: UInt64, now: Date) -> [SessionItem]
  }
  public struct SeededGenerator: RandomNumberGenerator { public init(seed: UInt64) }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/GRECoreTests/QuizPlannerTests.swift
import Foundation
import Testing
@testable import GRECore

@Suite struct QuizPlannerTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let fsrs = FSRS(enableFuzzing: false)

    private func studied(_ id: String, stability: Double = 10, daysAgo: Double = 1) -> StudyCard {
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: stability, difficulty: 5, due: now.addingTimeInterval(5 * 86_400),
                           lastReview: now.addingTimeInterval(-daysAgo * 86_400), state: .review, step: nil),
            reviewCount: 2
        )
    }

    private var deck: Deck { Self.catalog.decks[0] }

    @Test func aDeckTestCoversEveryStudiedWordOnce() {
        let cards = deck.wordIDs.prefix(9).map { studied($0) }
        let items = QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 1)
        #expect(Set(items.map(\.card.wordID)) == Set(cards.map(\.wordID)))
        #expect(items.count == 9)
    }

    @Test func unstudiedAndForeignWordsAreLeftOut() {
        let cards = deck.wordIDs.prefix(6).map { studied($0) } + [studied("laconic")]
        let items = QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 1)
        #expect(items.count == 6)
        #expect(items.allSatisfy { deck.wordIDs.contains($0.card.wordID) })
    }

    @Test func fewerThanFiveStudiedWordsIsNoTest() {
        let cards = deck.wordIDs.prefix(4).map { studied($0) }
        #expect(QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 1).isEmpty)
        let five = deck.wordIDs.prefix(5).map { studied($0) }
        #expect(QuizPlanner.deckTest(deck: deck, cards: five, catalog: Self.catalog, seed: 1).count == 5)
    }

    @Test func onlyLocalModesAreUsedAndTheyAreMixed() {
        let cards = deck.wordIDs.map { studied($0) }
        let items = QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 3)
        #expect(items.allSatisfy { StudyMode.locallyGraded.contains($0.mode) })
        #expect(Set(items.map(\.mode)).count == 3)
    }

    @Test func theSameSeedGivesTheSameOrderAndADifferentSeedShufflesIt() {
        let cards = deck.wordIDs.map { studied($0) }
        let a = QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 7).map(\.card.wordID)
        let b = QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 7).map(\.card.wordID)
        let c = QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 8).map(\.card.wordID)
        #expect(a == b)
        #expect(a != c)
        #expect(a != deck.wordIDs, "should not come out in deck order")
    }

    @Test func aGlobalTestSamplesTheRequestedCountFromStudiedWords() {
        let cards = Self.catalog.words.prefix(60).map { studied($0.id) }
        let items = QuizPlanner.globalTest(cards: cards, catalog: Self.catalog, scheduler: fsrs, count: 20, seed: 1, now: now)
        #expect(items.count == 20)
        #expect(Set(items.map(\.card.wordID)).count == 20)
    }

    @Test func aGlobalTestFavoursTheWordsMostLikelyForgotten() {
        // 40 rock-solid words and 10 shaky ones; the shaky ones should dominate.
        let solid = Self.catalog.words.prefix(40).map { studied($0.id, stability: 400, daysAgo: 0) }
        let shaky = Self.catalog.words.dropFirst(40).prefix(10).map { studied($0.id, stability: 0.5, daysAgo: 10) }
        var hits = 0
        for seed in 0..<20 {
            let items = QuizPlanner.globalTest(cards: solid + shaky, catalog: Self.catalog, scheduler: fsrs,
                                               count: 10, seed: UInt64(seed), now: now)
            hits += items.filter { shaky.map(\.wordID).contains($0.card.wordID) }.count
        }
        // Uniform sampling would give ~2 of 10 per run (40 of 200); weighting must beat that clearly.
        #expect(hits > 120, "only \(hits)/200 picks were shaky words")
    }

    @Test func aGlobalTestWithTooFewWordsIsEmpty() {
        let cards = Self.catalog.words.prefix(4).map { studied($0.id) }
        #expect(QuizPlanner.globalTest(cards: cards, catalog: Self.catalog, scheduler: fsrs, seed: 1, now: now).isEmpty)
    }
}
```

- [ ] **Step 2: Run** → compile error.

- [ ] **Step 3: Implement**

```swift
// Sources/GRECore/Scheduler/QuizPlanner.swift
import Foundation

/// Builds a fixed test over words the learner has already studied. Answers
/// still go through the scheduler -- a test is evidence like any review.
public enum QuizPlanner {

    /// Fewer than this and a percentage is noise.
    public static let minimumWords = 5

    /// Every studied word in the deck, shuffled, local modes only.
    public static func deckTest(deck: Deck, cards: [StudyCard], catalog: WordCatalog, seed: UInt64) -> [SessionItem] {
        let inDeck = Set(deck.wordIDs)
        let studied = cards.filter { $0.reviewCount > 0 && inDeck.contains($0.wordID) }
        return items(from: studied, catalog: catalog, seed: seed)
    }

    /// `count` studied words, weighted toward the ones most likely forgotten.
    public static func globalTest(
        cards: [StudyCard], catalog: WordCatalog, scheduler: FSRS,
        count: Int = 20, seed: UInt64, now: Date
    ) -> [SessionItem] {
        var pool = cards.filter { $0.reviewCount > 0 && catalog[$0.wordID] != nil }
        guard pool.count >= minimumWords else { return [] }
        var rng = SeededGenerator(seed: seed)
        var chosen: [StudyCard] = []
        // Weighted sampling without replacement. ponytail: O(n·k) scan; fine for
        // a few thousand cards and k = 20.
        while chosen.count < count, !pool.isEmpty {
            let weights = pool.map { 1 - scheduler.retrievability($0.fsrs, at: now) + 0.05 }
            var pick = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
            var index = 0
            while index < weights.count - 1, pick >= weights[index] {
                pick -= weights[index]
                index += 1
            }
            chosen.append(pool.remove(at: index))
        }
        return items(from: chosen, catalog: catalog, seed: seed)
    }

    private static func items(from cards: [StudyCard], catalog: WordCatalog, seed: UInt64) -> [SessionItem] {
        guard cards.count >= minimumWords else { return [] }
        var rng = SeededGenerator(seed: seed)
        let local = StudyMode.locallyGraded
        return cards.shuffled(using: &rng).enumerated().compactMap { n, card in
            catalog[card.wordID].map { SessionItem(card: card, word: $0, mode: local[n % local.count]) }
        }
    }
}

/// SplitMix64: tiny, deterministic, good enough for shuffling a test.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
```

Add to `PublicSurfaceTests.everyPropertyTheAppReadsIsPubliclyReadable`:

```swift
        _ = QuizPlanner.deckTest(deck: catalog.decks[0], cards: [card], catalog: catalog, seed: 1)
        _ = QuizPlanner.globalTest(cards: [card], catalog: catalog, scheduler: FSRS(), seed: 1, now: .now)
        _ = QuizPlanner.minimumWords
```

- [ ] **Step 4: Run** → `swift test` PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GRECore/Scheduler/QuizPlanner.swift Tests/GRECoreTests/QuizPlannerTests.swift Tests/GRECoreTests/PublicSurfaceTests.swift
git commit -m "feat: deck and global quizzes over studied words"
```

---

### Task 5: App settings, records, container

**Files:**
- Modify: `App/GRE/Settings/AppSettings.swift`
- Modify: `App/GRE/Settings/SettingsView.swift:93-110,150-160`
- Modify: `App/GRE/Persistence/Records.swift`
- Modify: `App/GRE/GREApp.swift:11`
- Modify: `App/GRE/Persistence/ReviewRecorder.swift` (add `cardsByID`, `bestQuizScore`)

**Interfaces:**
- Produces: `AppSettings.currentDeckID: String?`; `QuizRecord(deckID:score:wordCount:takenAt:)`; `ReviewRecorder.cardsByID(in:) -> [String: StudyCard]`; `ReviewRecorder.bestQuizScore(deckID:in:) -> Int?`.

- [ ] **Step 1: AppSettings**

Delete keys `newWordOrder`, `dailyNewWordLimit`, `sessionLength` and their properties/init lines. Add key `static let currentDeckID = "currentDeckID"` and:

```swift
    /// Deck new words are drawn from. Nil means start at the first deck.
    var currentDeckID: String? {
        didSet { defaults.set(currentDeckID, forKey: Key.currentDeckID) }
    }
```
init: `currentDeckID = defaults.string(forKey: Key.currentDeckID)`.

`sessionSettings`:
```swift
    var sessionSettings: SessionSettings {
        SessionSettings(
            strictness: strictness,
            aiEnabled: hasAPIKey,
            writingModeAfterReviews: writingModeAfterReviews,
            forcedMode: forcedMode,
            currentDeckID: currentDeckID
        )
    }
```

- [ ] **Step 2: SettingsView**

Delete the whole `Section { Picker("New words" ...) } header: { Text("What to learn next") } footer: {...}` block, the two `Stepper` lines, and the `newWordOrderExplanation` computed property.

- [ ] **Step 3: QuizRecord**

Append to `Records.swift`:

```swift
/// One finished test, for the deck's best score.
@Model
final class QuizRecord {
    /// Nil for a test over everything studied.
    var deckID: String?
    var score: Int = 0
    var wordCount: Int = 0
    var takenAt: Date = Date.distantPast

    init(deckID: String?, score: Int, wordCount: Int, takenAt: Date) {
        self.deckID = deckID
        self.score = score
        self.wordCount = wordCount
        self.takenAt = takenAt
    }
}
```

`GREApp.swift`: `ModelContainer(for: CardRecord.self, ReviewRecord.self, DeepDiveRecord.self, QuizRecord.self)`.

- [ ] **Step 4: ReviewRecorder helpers**

```swift
    /// Every card keyed by word, which is how decks and the planner read them.
    static func cardsByID(in context: ModelContext) -> [String: StudyCard] {
        let records = (try? context.fetch(FetchDescriptor<CardRecord>())) ?? []
        return Dictionary(records.map { ($0.wordID, $0.studyCard) }, uniquingKeysWith: { a, _ in a })
    }

    static func bestQuizScore(deckID: String?, in context: ModelContext) -> Int? {
        let all = (try? context.fetch(FetchDescriptor<QuizRecord>())) ?? []
        return all.filter { $0.deckID == deckID }.map(\.score).max()
    }
```

- [ ] **Step 5: Commit**

```bash
git add App/GRE
git commit -m "feat: current deck setting, quiz records; drop daily cap and session length"
```

---

### Task 6: Endless session view model and view

**Files:**
- Modify: `App/GRE/Study/SessionViewModel.swift`
- Modify: `App/GRE/Study/SessionView.swift`

**Interfaces:**
- Consumes: `SessionPlanner.next/nextDue`, `QuizPlanner`, `ReviewRecorder.cardsByID`, `QuizRecord`.
- Produces: `enum QuizSpec { case deck(Deck), everything }`; `SessionViewModel(context:catalog:settings:quiz: QuizSpec? = nil)`; phases `.caughtUp(nextDue: Date?)`, `.finished(SessionSummary)`; `stop()`, `keepGoing()`; `SessionView(quiz: QuizSpec? = nil, deck: Deck? = nil)`.

- [ ] **Step 1: View model**

Replace the `items/index/progress/answeredCount/start/advance` machinery:

```swift
/// What kind of fixed test to run instead of the open-ended study queue.
enum QuizSpec: Equatable {
    case deck(Deck)
    case everything

    var deckID: String? {
        if case let .deck(deck) = self { return deck.id }
        return nil
    }
}

struct SessionSummary: Equatable {
    var answered: Int
    var meanScore: Int
    var isQuiz: Bool
}
```

Inside the class:

```swift
    enum Phase: Equatable {
        case loading
        case answering
        case grading
        case reviewing(AnswerFeedback)
        /// Study only: nothing due and no new words left.
        case caughtUp(nextDue: Date?)
        case finished(SessionSummary)
        case failed(String)
    }

    private(set) var current: SessionItem?
    private(set) var phase: Phase = .loading
    private(set) var recentAccuracy: Double?
    private(set) var sessionSpend: Double = 0
    private(set) var answeredCount = 0
    /// Scores this session, for the summary and the quiz record.
    private var scores: [Int] = []
    /// Newest last; the planner keeps these out of the way.
    private var recentWordIDs: [String] = []
    /// Quiz only: the fixed list and where we are in it.
    private var queue: [SessionItem] = []
    private var queueIndex = 0
    let quiz: QuizSpec?

    /// Quiz: fraction done. Study is open-ended, so nil hides the bar.
    var progress: Double? {
        guard quiz != nil, !queue.isEmpty else { return nil }
        return Double(queueIndex) / Double(queue.count)
    }

    init(context: ModelContext, catalog: WordCatalog, settings: AppSettings, quiz: QuizSpec? = nil) {
        self.context = context
        self.catalog = catalog
        self.settings = settings
        self.quiz = quiz
    }

    // MARK: - Lifecycle

    func start(now: Date = .now) {
        phase = .loading
        answeredCount = 0
        scores = []
        recentWordIDs = []
        sessionSpend = 0
        resetDrafts()
        if let quiz {
            let cards = Array(ReviewRecorder.cardsByID(in: context).values)
            let seed = UInt64(now.timeIntervalSince1970)
            queue = switch quiz {
            case let .deck(deck):
                QuizPlanner.deckTest(deck: deck, cards: cards, catalog: catalog, seed: seed)
            case .everything:
                QuizPlanner.globalTest(cards: cards, catalog: catalog, scheduler: settings.scheduler,
                                       seed: seed, now: now)
            }
            queueIndex = 0
            current = queue.first
            phase = current == nil ? .finished(summary()) : .answering
        } else {
            loadNext(now: now)
        }
    }

    /// Study: ask the planner for one more card against the freshest state.
    private func loadNext(allowEarly: Bool = false, now: Date = .now) {
        let cards = Array(ReviewRecorder.cardsByID(in: context).values)
        recentAccuracy = ReviewRecorder.recentAccuracy(in: context)
        let item = SessionPlanner.next(
            cards: cards, catalog: catalog, settings: settings.sessionSettings,
            scheduler: settings.scheduler, recentAccuracy: recentAccuracy,
            recentWordIDs: recentWordIDs, allowEarly: allowEarly, now: now
        )
        current = item
        guard let item else {
            phase = .caughtUp(nextDue: SessionPlanner.nextDue(cards: cards, now: now))
            return
        }
        // A new word moves the deck pointer, so the Decks tab and the next
        // launch pick up where this one left off.
        if item.card.reviewCount == 0, let deck = catalog.deck(containing: item.word.id) {
            settings.currentDeckID = deck.id
        }
        phase = .answering
    }

    func advance() {
        resetDrafts()
        if quiz != nil {
            queueIndex += 1
            current = queueIndex < queue.count ? queue[queueIndex] : nil
            if current == nil { finishQuiz() } else { phase = .answering }
        } else {
            loadNext()
        }
    }

    /// Study: wrap up with a summary.
    func stop() {
        current = nil
        phase = .finished(summary())
    }

    /// Caught up but not done: review the weakest memories ahead of time.
    func keepGoing() {
        loadNext(allowEarly: true)
    }

    private func summary() -> SessionSummary {
        let mean = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
        return SessionSummary(answered: answeredCount, meanScore: mean, isQuiz: quiz != nil)
    }

    private func finishQuiz() {
        let result = summary()
        if result.answered >= QuizPlanner.minimumWords {
            context.insert(QuizRecord(deckID: quiz?.deckID, score: result.meanScore,
                                      wordCount: result.answered, takenAt: .now))
            try? context.save()
        }
        phase = .finished(result)
    }
```

In `finish(grade:rating:cost:feedback:)` after `ReviewRecorder.record(...)` add:

```swift
        answeredCount += 1
        scores.append(grade.score)
        recentWordIDs.append(item.card.wordID)
```

Delete the old `items`, `index`, `progress`, `answeredCount` computed property. `current` is now stored. Keep everything else (`multipleChoiceOptions`, `submit*`, `admitNotKnowing`, `retryAfterFailure`, `headline`).

- [ ] **Step 2: View**

`SessionView`:
- add `var quiz: QuizSpec? = nil` and `var deck: Deck? = nil` (a deck to start from); in `.task`, before `created.start()`: `if let deck { settings.currentDeckID = deck.id }`; create the model with `quiz: quiz`.
- `.onChange(of: settings.forcedMode)` → only when `quiz == nil`: `{ _, _ in if quiz == nil { model?.start() } }`.
- toolbar: keep the mode picker only when `quiz == nil`; add a leading **Done** button for study:

```swift
        .toolbar {
            if quiz == nil {
                ToolbarItem(placement: .topBarLeading) {
                    if let model, model.answeredCount > 0, isAnswerable(model) {
                        Button("Done") { model.stop() }.font(Theme.label)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { modePicker }
            }
        }
```
with
```swift
    private func isAnswerable(_ model: SessionViewModel) -> Bool {
        switch model.phase {
        case .answering, .reviewing: true
        default: false
        }
    }
```
- `content`:
```swift
        case let .finished(summary):
            SessionCompleteView(summary: summary, again: { model.start() }, showTestEverything: quiz == nil)
        case let .caughtUp(nextDue):
            CaughtUpView(nextDue: nextDue, keepGoing: { model.keepGoing() })
```
- progress bar: `if let progress = model.progress { SessionProgressBar(progress: progress) }`.
- Replace `SessionCompleteView` and add `CaughtUpView`:

```swift
private struct SessionCompleteView: View {
    let summary: SessionSummary
    let again: () -> Void
    let showTestEverything: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: summary.isQuiz ? "rosette" : "checkmark.seal")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(summary.isQuiz ? "\(summary.meanScore)%" : "Nice work")
                .font(Theme.headword(summary.isQuiz ? 44 : 30))
                .foregroundStyle(summary.isQuiz ? Theme.tint(forScore: summary.meanScore) : Theme.primaryText)
            Text(summary.answered == 0
                 ? (summary.isQuiz ? "Study at least \(QuizPlanner.minimumWords) words first." : "Nothing answered yet.")
                 : "\(summary.answered) \(summary.answered == 1 ? "word" : "words") · \(summary.meanScore)% average")
                .font(Theme.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button(summary.isQuiz ? "Test again" : "Keep studying", action: again)
                .buttonStyle(.glassProminent)
                .padding(.top, 8)
            if showTestEverything {
                NavigationLink("Test everything I know") { SessionView(quiz: .everything).navigationTitle("Test") }
                    .buttonStyle(.glass)
            }
        }
        .padding(Theme.gutter * 1.5)
    }
}

private struct CaughtUpView: View {
    let nextDue: Date?
    let keepGoing: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "moon.stars")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("All caught up")
                .font(Theme.headword(30))
                .foregroundStyle(Theme.primaryText)
            Text(nextDue.map { "Next review \($0.formatted(.relative(presentation: .named)))." }
                 ?? "Every word in the list has been studied.")
                .font(Theme.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            // Reviewing early is a little wasteful and a lot better than stopping
            // someone who wants to keep going.
            Button("Keep going anyway", action: keepGoing)
                .buttonStyle(.glassProminent)
            NavigationLink("Test everything I know") { SessionView(quiz: .everything).navigationTitle("Test") }
                .buttonStyle(.glass)
        }
        .padding(Theme.gutter * 1.5)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add App/GRE/Study
git commit -m "feat: endless self-paced session, caught-up state, quiz runs"
```

---

### Task 7: Decks tab

**Files:**
- Create: `App/GRE/Decks/DecksView.swift`
- Create: `App/GRE/Decks/DeckDetailView.swift`
- Modify: `App/GRE/RootView.swift:9-11`
- Modify: `App/GRE/Study/WordListView.swift` (delete the `WordListView` struct; keep `DifficultyBadge`, `WordDetailView`, `SenseBlock`)

**Interfaces:**
- Consumes: `WordCatalog.decks/decks(inTier:)`, `DeckProgress`, `Mastery`, `ReviewRecorder.cardsByID/bestQuizScore`, `SessionView(quiz:)`, `WordDetailView`, `DifficultyBadge`.

- [ ] **Step 1: DecksView**

```swift
// App/GRE/Decks/DecksView.swift
import GRECore
import SwiftData
import SwiftUI

/// Tiers → decks of ~25, each with a mastery ring. Search flattens to words.
struct DecksView: View {
    @Environment(\.catalog) private var catalog
    @Environment(AppSettings.self) private var settings
    @Query private var records: [CardRecord]
    @State private var search = ""

    private var cards: [String: StudyCard] {
        Dictionary(records.map { ($0.wordID, $0.studyCard) }, uniquingKeysWith: { a, _ in a })
    }

    private var matches: [Word] {
        catalog.words
            .filter { $0.word.localizedCaseInsensitiveContains(search) }
            .sorted { $0.zipf != $1.zipf ? $0.zipf > $1.zipf : $0.id < $1.id }
    }

    var body: some View {
        Group {
            if search.isEmpty { deckGrid } else { searchResults }
        }
        .searchable(text: $search, prompt: "Search \(catalog.words.count) words")
        .screenBackground()
    }

    private var deckGrid: some View {
        let cards = cards
        return ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                ForEach(WordTier.allCases.sorted(), id: \.self) { tier in
                    TierSection(tier: tier, decks: catalog.decks(inTier: tier), cards: cards,
                                currentDeckID: settings.currentDeckID)
                }
            }
            .padding(Theme.gutter)
        }
    }

    private var searchResults: some View {
        List(matches) { word in
            NavigationLink {
                WordDetailView(word: word)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(word.word).font(Theme.headword(19)).foregroundStyle(Theme.primaryText)
                        DifficultyBadge(difficulty: word.difficulty)
                        MasteryDot(level: Mastery(card: cards[word.id]))
                    }
                    Text(word.primarySense.definition)
                        .font(.footnote).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct TierSection: View {
    let tier: WordTier
    let decks: [Deck]
    let cards: [String: StudyCard]
    let currentDeckID: String?

    private var progress: [DeckProgress] { decks.map { DeckProgress(deck: $0, cards: cards) } }
    private var fraction: Double {
        let p = progress
        return p.isEmpty ? 0 : p.map(\.fraction).reduce(0, +) / Double(p.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(tier.label).font(Theme.headword(24)).foregroundStyle(Theme.primaryText)
                Spacer()
                Text("\(progress.filter(\.isComplete).count)/\(decks.count) decks · \(Int(fraction * 100))%")
                    .font(Theme.label).foregroundStyle(Theme.tertiaryText).monospacedDigit()
            }
            Text(subtitle).font(.footnote).foregroundStyle(Theme.tertiaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                ForEach(Array(zip(decks, progress)), id: \.0.id) { deck, p in
                    NavigationLink {
                        DeckDetailView(deck: deck)
                    } label: {
                        DeckTile(deck: deck, progress: p, isCurrent: deck.id == currentDeckID)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var subtitle: String {
        switch tier {
        case .core: "On three or more prep lists — the words most worth knowing."
        case .common: "On two lists."
        case .extended: "On one list. Broad coverage once the rest is solid."
        }
    }
}

private struct DeckTile: View {
    let deck: Deck
    let progress: DeckProgress
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(progress.isComplete ? Theme.positive : Theme.accent,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress.fraction * 100))")
                    .font(Theme.label).foregroundStyle(Theme.secondaryText).monospacedDigit()
            }
            .frame(width: 52, height: 52)
            Text("\(deck.index)").font(Theme.headword(18)).foregroundStyle(Theme.primaryText)
            Text("\(progress.count(atLeast: .known))/\(progress.total) known")
                .font(.caption2).foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .cardSurface()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(isCurrent ? Theme.accent : .clear, lineWidth: 1.5)
        )
        .accessibilityLabel("\(deck.title), \(Int(progress.fraction * 100)) percent")
    }
}

/// One small dot per mastery level; the legend is in the deck header.
struct MasteryDot: View {
    let level: Mastery

    var body: some View {
        Circle().fill(MasteryDot.color(level)).frame(width: 8, height: 8)
            .accessibilityLabel(level.label)
    }

    static func color(_ level: Mastery) -> Color {
        switch level {
        case .new: Theme.hairline
        case .learning: Theme.negative
        case .familiar: Theme.accent.opacity(0.6)
        case .known: Theme.accent
        case .mastered: Theme.positive
        }
    }
}
```

- [ ] **Step 2: DeckDetailView**

```swift
// App/GRE/Decks/DeckDetailView.swift
import GRECore
import SwiftData
import SwiftUI

struct DeckDetailView: View {
    let deck: Deck

    @Environment(\.catalog) private var catalog
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query private var records: [CardRecord]
    @Query private var quizzes: [QuizRecord]

    private var cards: [String: StudyCard] {
        Dictionary(records.map { ($0.wordID, $0.studyCard) }, uniquingKeysWith: { a, _ in a })
    }
    private var progress: DeckProgress { DeckProgress(deck: deck, cards: cards) }
    private var bestScore: Int? { quizzes.filter { $0.deckID == deck.id }.map(\.score).max() }
    private var studiedCount: Int { deck.wordIDs.filter { (cards[$0]?.reviewCount ?? 0) > 0 }.count }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                ForEach(deck.wordIDs.compactMap { catalog[$0] }) { word in
                    NavigationLink {
                        WordDetailView(word: word)
                    } label: {
                        let level = Mastery(card: cards[word.id])
                        HStack(spacing: 10) {
                            MasteryDot(level: level)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(word.word).font(Theme.headword(18)).foregroundStyle(Theme.primaryText)
                                Text(word.primarySense.definition)
                                    .font(.footnote).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                            }
                            Spacer()
                            Text(level.label).font(.caption2).foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(deck.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            MasteryBar(counts: progress.counts, total: progress.total)
            HStack {
                Text("\(Int(progress.fraction * 100))% mastered")
                    .font(Theme.label).foregroundStyle(Theme.secondaryText)
                Spacer()
                if let bestScore {
                    Text("Best test \(bestScore)%")
                        .font(Theme.label).foregroundStyle(Theme.tint(forScore: bestScore))
                }
            }
            HStack(spacing: 12) {
                NavigationLink {
                    SessionView(deck: deck).navigationTitle("Study")
                } label: {
                    Label("Study this deck", systemImage: "brain.head.profile")
                }
                .buttonStyle(.glassProminent)

                NavigationLink {
                    SessionView(quiz: .deck(deck)).navigationTitle("Test \(deck.title)")
                } label: {
                    Label("Test", systemImage: "checkmark.seal")
                }
                .buttonStyle(.glass)
                .disabled(studiedCount < QuizPlanner.minimumWords)
            }
            .font(.headline)
            if studiedCount < QuizPlanner.minimumWords {
                Text("Study at least \(QuizPlanner.minimumWords) words here to unlock the test.")
                    .font(.footnote).foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(Theme.gutter)
        .cardSurface()
    }
}

/// Five segments, new → mastered, each sized by count. Shared with Progress.
struct MasteryBar: View {
    let counts: [Mastery: Int]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Mastery.allCases, id: \.self) { level in
                        let n = counts[level] ?? 0
                        if n > 0 {
                            MasteryDot.color(level)
                                .frame(width: max(2, geo.size.width * Double(n) / Double(max(total, 1))))
                        }
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            HStack(spacing: 12) {
                ForEach(Mastery.allCases, id: \.self) { level in
                    HStack(spacing: 4) {
                        MasteryDot(level: level)
                        Text("\(counts[level] ?? 0) \(level.label.lowercased())")
                            .font(.caption2).foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: RootView + WordListView**

`RootView.swift`: replace the Words tab with
```swift
            Tab("Decks", systemImage: "square.stack.3d.up") {
                NavigationStack { DecksView().navigationTitle("Decks") }
            }
```
`WordListView.swift`: delete the `WordListView` struct (lines 5–74), keep the rest.

- [ ] **Step 4: Commit**

```bash
git add App/GRE
git commit -m "feat: decks tab with mastery rings, deck detail, deck tests"
```

---

### Task 8: Progress screen

**Files:**
- Modify: `App/GRE/Progress/ProgressScreen.swift`

- [ ] **Step 1: Replace StatRow and LevelCard**

```swift
private struct StatRow: View {
    let cards: [CardRecord]
    let catalog: WordCatalog
    let reviews: [ReviewRecord]

    private var byID: [String: StudyCard] {
        Dictionary(cards.map { ($0.wordID, $0.studyCard) }, uniquingKeysWith: { a, _ in a })
    }
    private var due: Int { cards.filter { $0.due <= .now }.count }
    private var levels: [Mastery: Int] {
        Dictionary(catalog.words.map { (Mastery(card: byID[$0.id]), 1) }, uniquingKeysWith: +)
    }
    private var decksDone: Int {
        catalog.decks.filter { DeckProgress(deck: $0, cards: byID).isComplete }.count
    }

    var body: some View {
        let levels = levels
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mastery").font(Theme.label).foregroundStyle(Theme.tertiaryText).textCase(.uppercase)
                MasteryBar(counts: levels, total: catalog.words.count)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                Stat(value: "\(decksDone)", label: "Decks done", of: "of \(catalog.decks.count)")
                Stat(value: "\(due)", label: "Due now", of: due == 0 ? "all caught up" : "ready to review")
                Stat(value: "\((levels[.known] ?? 0) + (levels[.mastered] ?? 0))", label: "Known",
                     of: "3+ weeks' recall")
                Stat(value: "\(reviews.count)", label: "Reviews", of: "all time")
            }
        }
    }
}
```

`LevelCard`: delete `let order: NewWordOrder`, the `ceiling` line and `DifficultyBadge`, and simplify the text:
```swift
            if let accuracy {
                Text("\(Int(accuracy))%")
                    .font(Theme.headword(28))
                    .foregroundStyle(Theme.tint(forScore: Int(accuracy)))
                Text("Recent accuracy over your last \(min(reviews.count, 40)) answers. Above 85% and new words come faster; below 60% and reviews take priority.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Answer a few more and this will show your recent accuracy, which sets how many new words you juggle at once.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondaryText)
            }
```
Call site: `LevelCard(reviews: reviews)`. Update the doc comment to "Recent accuracy, which sets the learning load, and what grading has cost."

- [ ] **Step 2: Commit**

```bash
git add App/GRE/Progress/ProgressScreen.swift
git commit -m "feat: mastery bar and decks-done stat on progress"
```

---

### Task 9: App smoke tests and README

**Files:**
- Modify: `App/GRETests/AppSmokeTests.swift`
- Modify: `README.md`

- [ ] **Step 1: Smoke tests**

- `inMemoryContext`: add `QuizRecord.self` to the container.
- `aSessionPlansAndSchedulesTheFirstCard`: delete the two settings lines; replace `#expect(model.items.count == 3)` with `#expect(model.current != nil)`; keep the rest.
- `aWrongMultipleChoiceAnswerSchedulesTheCardToReturn`: delete `settings.dailyNewWordLimit = 2`.
- `multipleChoiceAlwaysOffersTheRightAnswerAmongFour`: delete the settings line; replace the loop with
  ```swift
        for _ in 0..<12 {
            let item = try #require(model.current)
            let options = model.multipleChoiceOptions(for: item)
            #expect(options.count == 4, "\(item.word.id) offered \(options.count) options")
            #expect(options.contains { $0.id == item.word.id })
            model.submitMultipleChoice(item.word)
            model.advance()
        }
  ```
- `writingModeIsReachableImmediatelyWhenTheThresholdIsZero`:
  ```swift
        let card = StudyCard(wordID: "abate")
        #expect(SessionPlanner.mode(for: card, settings: SessionSettings(aiEnabled: true, writingModeAfterReviews: 0)) == .defineAndUse)
        #expect(SessionPlanner.mode(for: card, settings: SessionSettings(aiEnabled: true, writingModeAfterReviews: 3)) == .multipleChoice)
  ```
  (`mode` is internal; the app test target uses `@testable import GRE`, not GRECore — so instead use the planner: `SessionPlanner.next(cards: [], catalog: catalog, settings: SessionSettings(aiEnabled: true, writingModeAfterReviews: 0), scheduler: FSRS(), recentAccuracy: nil, recentWordIDs: [], now: .now)?.mode == .defineAndUse`, and the same with `writingModeAfterReviews: 3` expecting `.multipleChoice`.)
- `forcingAModeRetestsEveryCardThatWay` / `autoRestoresTheLadder`: delete the `dailyNewWordLimit` lines; assert on `model.current?.mode` instead of `model.items`.
- Delete `newWordsStartFamiliarAndClimbWithAccuracy`.
- Add:
  ```swift
    @Test func aWrongAnswerComesBackWithinTheSession() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        let missed = try #require(model.current)
        model.admitNotKnowing()
        model.advance()
        // Rated Again → due in a minute. Advance the clock by answering a few
        // others and it must resurface before any more new words arrive.
        var seen: [String] = []
        for _ in 0..<6 {
            guard let item = model.current else { break }
            seen.append(item.word.id)
            model.submitMultipleChoice(item.word)
            model.advance()
        }
        #expect(seen.contains(missed.word.id) == false, "the same word should not repeat back-to-back")
        #expect(settings.currentDeckID == catalog.decks[0].id)
    }

    @Test func aDeckTestRecordsItsScore() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let deck = catalog.decks[0]
        for id in deck.wordIDs.prefix(5) {
            ReviewRecorder.record(wordID: id, mode: .multipleChoice, grade: Grade(score: 100),
                                  rating: .good, scheduler: FSRS(), in: context)
        }
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, quiz: .deck(deck))
        model.start()
        #expect(model.progress == 0)
        while let item = model.current {
            model.submitMultipleChoice(item.word)
            model.advance()
        }
        guard case let .finished(summary) = model.phase else { Issue.record("expected finished"); return }
        #expect(summary.answered == 5 && summary.meanScore == 100 && summary.isQuiz)
        #expect(ReviewRecorder.bestQuizScore(deckID: deck.id, in: context) == 100)
    }
  ```
  Note: the missed word's 1-minute step means within this synchronous test it is not yet due, so `seen` never contains it; the assertion documents anti-repeat rather than the return itself, which `SessionPlannerTests` covers with a controlled clock.

- [ ] **Step 2: README**

Replace the paragraph after the modes table ("Modes climb as a word becomes familiar…") with:

```markdown
Modes climb as a word's memory gets stronger: recognise it, recall it, spell it,
then write with it. **Without an API key the first three work fully** — only the
graded mode is locked.

## Pace and decks

There is no daily quota. A session runs until you stop: due reviews first (the
ones you are most likely to have forgotten), then new words from your current
deck. A word you miss comes back within minutes; the number of half-learned words
in flight follows your recent accuracy, so a bad day slows the intake instead of
burying you.

The 2,898 words are split into decks of ~25 — **Core** (on 3+ prep lists),
**Common** (2), **Extended** (1), easiest first inside each tier. Every word has a
mastery level read off its FSRS stability (new → learning → familiar → known →
mastered), decks show a ring of that, and each deck can be tested once you've
studied five of its words. "Test everything I know" samples the words you are
most likely to have forgotten.
```

Update the test count in `swift test # 94 tests` to whatever `swift test` reports.

- [ ] **Step 3: Run the Linux suite one last time**

Run: `. ./env.sh && swift test`
Expected: all PASS; note the count.

- [ ] **Step 4: Commit**

```bash
git add App/GRETests/AppSmokeTests.swift README.md
git commit -m "test: smoke tests for the endless session and deck tests; README"
```

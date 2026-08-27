# Self-paced study, decks, mastery, quizzes

Approved 2026-08-27.

## Goals

- No daily cap or fixed session length. Learner studies at their own pace.
- Scheduler maximises learning per minute and adapts to the learner's own history.
- Words grouped into categories → decks of ~25 so progress is visible.
- Learner can test themselves on words already studied.
- Honest scoring derived from memory strength, not points.

## 1. Decks (GRECore, computed from `words.json`)

- Category = `WordTier`: Core (3+ lists) → Common (2) → Extended (1).
- Within a tier, words sorted easiest first (`zipf` desc, `id` tiebreak), chunked
  into decks of 23–25 (`ceil(n / ceil(n / 25))`, no runt deck).
- `Deck { id: "core-1", tier, index, wordIDs }`. `WordCatalog.decks`,
  `WordCatalog.deck(containing wordID)`.
- Deterministic. Regenerating the dataset may move words between decks; progress
  lives on words so nothing is lost.

## 2. Scheduler — `SessionPlanner.next(...)`

Called after every answer with fresh card state. Returns one `SessionItem` or nil.

Inputs: cards, catalog, settings (`currentDeckID`, `forcedMode`, `aiEnabled`,
`writingModeAfterReviews`), `recentAccuracy`, `recentWordIDs` (last 3 shown), `now`,
`scheduler: FSRS` (for retrievability).

Order of preference:
1. **Due now** (`fsrs.due <= now`): lowest retrievability first; relearning state
   breaks ties first.
2. **Anti-repeat**: exclude `recentWordIDs` unless nothing else qualifies.
3. **Learning-load cap**: count cards in `.learning`/`.relearning` due within 15 min.
   Cap by `recentAccuracy`: <60 → 4, default 8, ≥85 → 12. At cap, serve the soonest
   of those early instead of introducing a new word.
4. **New word**: first word in the current deck with no card. Deck exhausted → next
   deck in tier, then next tier. Planner reports the deck it drew from so the app
   can persist `currentDeckID`.
5. **Nothing**: return nil. View shows "next review in X" + Keep going, which calls
   `next(..., allowEarly: true)` → lowest-retrievability card regardless of due.

Mode ladder keyed on `Mastery`:
- new / learning / relearning → `.multipleChoice`
- familiar → `.reverseRecall` / `.spelling` alternating on `reviewCount` parity
- known, mastered → `.defineAndUse` when `aiEnabled` and
  `reviewCount >= writingModeAfterReviews`; otherwise recall/spelling alternating
- `forcedMode` overrides (still cannot force writing without a key).

Skipped: fitting FSRS parameters to the learner's log. Marked `ponytail:` in code.

## 3. Mastery (GRECore)

`enum Mastery: new, learning, familiar, known, mastered`, from `FSRSCard.stability`:
nil/<3d learning, ≥3 familiar, ≥21 known, ≥90 mastered; no card → new.
`DeckProgress(counts per level, fraction = mean level index / 4)`.
Deck "complete" when every word ≥ known.

## 4. Quiz — `QuizPlanner`

- `deckTest(deck, cards, catalog)`: all studied words in the deck; needs ≥5.
- `globalTest(cards, catalog, scheduler, now, count: 20)`: studied words weighted
  toward low retrievability (weight = 1 − R + 0.05), seeded selection.
- Items use `StudyMode.locallyGraded`, rotated by stable hash of word id; order
  shuffled by seeded RNG (seed passed in, app uses time).
- Runs in the existing `SessionViewModel`/`SessionView` with a fixed item list.
  Answers recorded through `ReviewRecorder` as normal (they are evidence).
- `QuizRecord(deckID: String?, score: Int, takenAt: Date)` persisted. Deck detail
  shows best score.

## 5. App

- Tabs: Study, Decks (replaces Words; search kept), Progress, Settings.
- Decks: tier sections with progress → deck grid (ring, mastery %) → deck detail
  (word rows with mastery dot, best test, Study this deck, Test deck).
- Study: endless; Done button; caught-up state with next-due time and Keep going;
  "Test everything I know" button.
- Progress: mastery distribution bar, decks completed count. Level card stays.
- Settings: remove new-words-per-day, session length, new-word order.
- `AppSettings.currentDeckID` persisted; nil means first deck.
- Delete `NewWordOrder`, `dailyNewWordLimit`, `sessionLength`,
  `SessionSettings.difficultyCeiling` and their tests.

## 6. Tests (GRECore)

Deck chunking (sizes 23–25, covers every word once, deterministic, easy→hard);
mastery thresholds; planner: due-first by retrievability, anti-repeat, load cap per
accuracy band, new word from current deck, deck advance, nil when caught up,
`allowEarly`; mode from mastery; quiz sizes, ≥5 rule, weighting favours low R.

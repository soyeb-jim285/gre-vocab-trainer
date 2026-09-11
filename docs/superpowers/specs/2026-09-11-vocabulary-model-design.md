# A personal vocabulary model

## The thesis

The app stops being a flashcard deck with AI grading bolted on. It becomes a
model of one learner's vocabulary that continuously estimates, for every word:

> If this appeared in a GRE question right now, would they actually understand it?

Not `known: true/false`. Each word carries meaning recall, contextual
understanding, productive usage, synonym discrimination and confusion risk,
alongside FSRS stability and retrievability.

## Decisions taken

- **AI is required.** The core loop is a typed answer graded semantically. No key
  means no session. Cost is not the constraint: about $0.0003 per graded answer,
  roughly $1.20 across a ninety-day prep. Connectivity is the constraint.
- **Strip back to the loop.** Decks, the Library grid and quizzes go. The
  navigation becomes Learn, Daily Challenge, GRE Drill and Progress.
- **Generate and verify the grading data.** All 2,898 words gain the grounding a
  reliable grader needs.
- **First release** is pretest before teaching, confidence before reveal, graded
  hints, and the fast-known pathway.

## One correction to the proposal

The proposal lists five knowledge dimensions alongside FSRS stability,
difficulty and retrievability. FSRS schedules one thing. If each dimension
carries its own stability, there are five cards per word and five times the
review load across 3,000 words.

So: **one FSRS card per word.** The dimensions choose the exercise, never the
timing. That is already how the competence model works, and it is the difference
between a system that ships and one that buries the learner.

# What has to be pre-generated

Three kinds of work: things computable from data already held, things one model
pass can produce, and things needing their own pass and their own verifier.

## Computed, no model needed

These are pure functions over the existing dataset. No cost, no drift, no cache.

- **Priority.** `GREUtility × PersonalNeed × Learnability`. Utility comes from
  `listCount`, `tier` and `zipf`, all present. Need is runtime. Learnability
  comes from the hand-assigned `rating`. Nothing to store.
- **Confusion candidates.** Pairs sharing two or more synonyms, or within edit
  distance three of each other (`imminent`/`eminent`), or sharing a GRE synonym
  set (`laconic`/`taciturn`). Computing candidates first is what keeps the
  confusion pass affordable: annotating 1,500 real pairs beats asking 2,898
  open questions.
- **Hint level two.** Already in the dataset. `gre.cloze` is the example sentence
  with the word blanked, which is exactly the second hint.
- **Near words and contrast.** `gre.synonyms` and `gre.antonyms`, both present.

## Pass one: the grounding block

One call per word, producing five fields. This is the important one, because
every later phase reads it.

| Field | What it is | Why |
|---|---|---|
| `acceptedConcepts` | 4 to 8 short paraphrases that score full marks | Strict about meaning, tolerant about wording |
| `incorrectAssociations` | 2 to 4 wrong answers learners actually give, each labelled with the misconception it reveals | Makes confidently-wrong detectable and seeds the confusion model |
| `requiredNuance` | The one element a precise answer must contain | Decides the 2 versus 3 boundary |
| `mentalHook` | One short memorable hook | Replaces the runtime deep-dive call, so teaching is instant and free |
| `semanticHint` | Hint level one, never containing the word or its stem | The first rung of the hint ladder |

For `equivocal`, accepted concepts would include "ambiguous", "unclear", "open to
more than one reading"; incorrect associations would include "dishonest" labelled
as confusing evasiveness with lying; required nuance would be "deliberate
ambiguity", which is what separates a 2 from a 3.

Folding the hook and the hint into the same call matters. It is one pass, not
three, and it deletes a per-word network call from the running app.

Roughly $1.20 for the full 2,898.

## Pass two: confusion annotations

Takes the computed candidate pairs and writes one discriminating line each.
`trenchant` is sharp and effective, `acerbic` is bitter in tone, `vitriolic` is
hateful. Around $0.60, because the candidates were computed rather than asked
for.

## Pass three: GRE items, later

Text Completion stems and Sentence Equivalence sets. The hard part is not
generation, it is verification: the blank must have a unique best answer, and a
Sentence Equivalence set needs exactly two options that both fit *and* produce
equivalent meaning. That cannot be fully checked by machine, so it needs sampled
human review. Around $3. Deferred to the last phase for that reason.

## The verifier

Generation without a verifier is how a dataset rots. In the existing style, in
`build_dataset.py`, refusing to build if any of these fail:

- fewer than four accepted concepts, or one that contains the word itself
- fewer than two incorrect associations, or one with no misconception named
- an empty required nuance, or one over sixty characters
- a hook over 120 characters, or one that merely restates the definition
- a hint containing the word or its stem
- a concept appearing in both the accepted and incorrect lists
- a confusion pair that is not symmetric, or names a word not in the dataset

# The phases

Each is independently shippable and leaves the build green.

**Phase 0. The data contract.** Add the grounding fields to the model as
optional, so the app still compiles and runs against today's `words.json`.
Nothing generated, nothing rendered. Tests cover decoding with the block and
without it. This unblocks every other phase and risks nothing.

**Phase 1. Generate the grounding.** `tools/gen_grounding.py`, sharded like the
existing sense and option shards, plus the verifier above wired into
`build_dataset.py`. Run it, commit the shards and the regenerated dataset. Still
no app change. At the end of this phase the data is there and proven.

**Phase 2. The pretest.** The core of the whole thing. First contact with a word
is a typed answer, never a choice, and never after the answer has been shown.
The teaching card appears only when the answer was wrong or vague. This replaces
the introduce step and removes the batching workaround that exists only because
teaching currently precedes testing.

**Phase 3. Confidence, hints and the derived grade.** Confidence captured before
reveal. A hint ladder that lowers the ceiling at each rung. One function mapping
meaning score, confidence, hints used and latency onto an FSRS rating.
Confidently wrong is rated worse than never seen, because a wrong memory
competes with the right one. The current latency-only confidence type is
replaced rather than kept alongside: it is the same signal, measured worse.

**Phase 4. The fast-known pathway.** A precise, confident, unaided, fast first
answer means the learner already owns the word. It is rated Easy, skips teaching
entirely, and comes back once days later to confirm. No new machinery: FSRS
already gives an Easy first review a long initial stability. This is what stops
a strong learner grinding through 3,000 words they half know.

**Phase 5. Exercise rotation.** Not every review is a typed definition, because
150 of those a day is homework. The forms rotate across exposures: type the
meaning, pick it from context, type it again, write a sentence, distinguish it
from a neighbour. The curriculum already picks by weakest evidence; it gains the
new forms and a friction budget so the heavy ones stay spaced.

**Phase 6. The new navigation.** Learn, Daily Challenge, GRE Drill, Progress.
Decks, the Library grid and the quiz flow are deleted. Progress shows the
knowledge model: active vocabulary, fragile words, misconceptions, coverage by
frequency band. Streaks stop being the headline.

**Phase 7. The confusion model.** Pass two's data plus a per-learner store of
which wrong associations they actually make. Discrimination drills generated
from real confusions rather than hypothetical ones. Word neighbourhoods.

**Phase 8. GRE mode.** Pass three's content, its sampled review, and the drill
screen. Explicitly training material, not score prediction.

Phases 0 and 1 are prerequisites for everything. Phases 2 to 4 are the first
release. Phase 7 needs phase 1's data. Phase 8 needs its own content pass.

# The workflow, end to end

What happens on one encounter with one word, once all of this exists.

1. **Pick the word.** Due reviews first, ordered by forgetting risk. Then new
   words by priority, capped by what the day allows and by how many words are
   already half-learned.
2. **Pick the exercise.** From the competence dimensions, whichever has the
   weakest evidence, subject to the friction budget.
3. **Ask before teaching.** On first contact: the word, and "what does this
   mean?". A text field. No options.
4. **Capture confidence.** Guess, Unsure, or Confident, before anything is
   revealed.
5. **Offer hints, not answers.** Stuck means a semantic hint, then the blanked
   example, then the reveal. Each rung lowers the ceiling, because recalling
   after one hint beats being told.
6. **Grade against the data, not the model's memory.** The call carries the
   accepted concepts, the incorrect associations and the required nuance. It
   returns a 0 to 4 meaning score, a matched misconception or nothing, and one
   or two sentences of corrective feedback.
7. **Derive the rating.** Score, confidence, hints and latency become one FSRS
   rating. The model never touches the schedule.
8. **Correct, do not just mark.** "Parsimonious can involve being careful with
   money, but it usually carries a stronger sense of being excessively stingy"
   teaches. A red cross does not.
9. **Teach only if needed.** Score of 2 or less brings up the small card: core
   meaning, hook, one natural example, near words, one contrast. Ten seconds,
   not a dictionary page.
10. **Update the model.** FSRS card, the competence dimension that was exercised,
    and the misconception store if one was matched.

The learner sees a word, types what they think, says how sure they are, gets
told what they missed, and moves on. Everything above is invisible.

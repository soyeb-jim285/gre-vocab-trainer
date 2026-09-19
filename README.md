# GRE Vocabulary Trainer

An iOS vocabulary trainer built on one opinion: turning a flashcard over and
thinking *yeah, I knew that* is recognition, and recognition is not what the exam
asks for. So the app makes you produce. You write the definition and a sentence
using the word, a model grades both, and the grade drives an FSRS-6 scheduler.
Words you actually fail come back within minutes. Words you own get out of the way.

2,898 words, each with a hand-written definition of the sense the GRE tests, two
example sentences, synonyms, antonyms, three wrong definitions written to be hard
to rule out, and a difficulty rating I assigned by hand. None of it is scraped
from a prep book.

## Meeting a word

A word you have never seen is taught, not tested. You get the word, how it sounds,
the sense the exam actually uses, a sentence with it doing its job, and — if you
have an API key — a hook to hang it on. Nothing is graded and nothing is scheduled.
Then the very next card is a real question about the word you just read.

That last part matters more than it looks. FSRS sets a card's starting difficulty
from the first rating it ever gets, so an app that opens with a graded question
about an unseen word is not measuring your memory. It is measuring a coin flip,
and then building a schedule on the result.

## Study modes

| Mode | What you do | Graded by |
|---|---|---|
| Multiple choice | Meet a new word, pick its definition from four close ones | locally, free |
| In context | A sentence with the word blanked out; pick what fits | locally, free |
| Which meaning | A common word in its uncommon tested sense; pick the meaning | locally, free |
| Reverse recall | Definition shown, name the word | locally, free |
| Spelling | Hear it in your chosen accent, type it | locally, free |
| Define and use | Write a definition and a sentence | a model, via OpenRouter |
| Quick recall | See the word, think the meaning, reveal, say if you had it | self-rated, capped at Good |
| Positive or negative | Tap the charge of the tested sense | locally, capped at Hard |

All but the writing mode work with no API key and no network. Only writing needs
one, because grading a free-text answer is the one thing a phone cannot do alone.

While a word is still shaky you get recognition. Once it holds, the app asks
whichever question you have the least evidence for: a mode you have never been
asked wins outright, then the one you are worst at. It used to rotate the modes by
review count, which meant someone who nailed recall and failed spelling got
spelling one time in three — the opposite of what their own history was asking
for. How soon a word reaches the writing mode is still a setting; set it to zero
and every word goes there straight after being introduced.

Multiple choice, in context and which meaning score right or wrong and nothing in
between, so the scheduler cannot tell a word recalled instantly from one dredged
up after twenty seconds of staring. There is an optional setting that reads answer
speed and lets a slow correct answer count for less. It can only ever shorten an
interval, never lengthen one, and it ships switched off until there are real
answer times to calibrate it against.

## Trap words

The most interesting problem in the dataset turned out to be words like `august`,
`flag`, `pine`, `base`, `wax` and `plastic`.

Every one of those is a common English word. Measure difficulty by how often the
word appears in ordinary text, which is what I did at first, and they come out as
the easiest words in the entire list. They came out first in the running order. But the exam does
not test the month, the piece of cloth, or the tree. It tests *majestic*, *to
weaken*, *to yearn*, *contemptible*, *to increase*, *malleable*. Those are among
the hardest things on the paper.

Frequency measures the word form. The exam tests a meaning. For 401 of the 2,898
words the two come apart, and those are exactly the words that cost people points,
because you read the sentence, recognise the word, and never notice you got it wrong.

Two things follow from that. Difficulty is rated by hand on the tested sense, so
`august` is a 4 and `modest` is a 1, and the running order follows that rating
rather than frequency. And the 401 get their own drill: the sentence appears with the
word intact, and you pick which of four meanings applies. The wrong answers are
that word's own everyday senses, pulled from WordNet, so the bait is the meaning
you already believe.

> *Attention flagged in the third hour and nobody pretended otherwise.*
>
> to weaken or lose energy · an emblem of cloth · to signal with a flag · to provide with a flag

The drill fires on a trap word's second outing, early enough to correct the
assumption before it sets. It never fires for an ordinary word, since asking
which meaning of `laconic` is being used has only one answer.

## The day

Setup asks three things once: when the test is, how many new words a day you are
willing to meet, and optionally an API key. Those two numbers are what turn 2,898
words into today's work.

Learn is the home screen. It shows what is due, how many new words the day still
has room for, roughly how long that will take, your streak, and whether the test
date is still reachable. When it is not, it says so and tells you what the date
would actually need. Falling behind quietly is the one thing a deadline is
supposed to prevent, so the app will not do it politely.

The day rolls over at 4am rather than midnight. Finishing at half past midnight
should complete the day you think you are in, not start a new one and break a
streak you were in the middle of earning.

Within a session, due reviews come first, ordered by which ones you are most
likely to have forgotten rather than by which are most overdue. New words come
after, in exam-value order, up to what the day allows. On top of that the app
counts the words currently half-learned and stops introducing more past a cap:
four if your recent accuracy is under 60%, twelve if it is over 85%, eight
otherwise. A bad day slows the intake instead of burying you.

## What the research changed

A round of reading the memory literature and the prep market turned into these:

- **Three right answers on day one.** Rawson and Dunlosky's successive
  relearning: practise to a criterion of three correct recalls, then relearn in
  spaced sessions. FSRS already did the spacing, but its learning steps graduate
  a word after two passes, which can be one lucky tap. A word met today now comes
  back before any new word until it has been got right three times.
- **Look-alikes only against words you know.** Similar words learned together
  interfere with each other. The "tell apart" drill used to pair a word with any
  annotated neighbour, including ones never met; it now only uses neighbours
  already introduced.
- **The test date shapes the last weeks.** The final six days are review only
  (GregMat's forty-day plan ends the same way), and no interval is scheduled past
  the eve of the test, since a review booked for after the exam never happens.
  Today shows the plan as "day 12 of 40".
- **Word origins, guess first.** Every word carries its roots, what they
  literally say, how that became the tested meaning, and everyday words sharing
  the root. Where the roots genuinely point at the meaning, the teaching card
  shows only the parts and asks for a guess before revealing it. Where the
  meaning drifted, it says so instead of letting the roots mislead.
- **Quick rounds.** GregMat's pace on per-word scheduling: a self-rated gloss
  ("Quick recall", Good at best) and a positive/negative/neutral tap (Hard at
  best, since a third of guesses land). Both only for words already held, and
  neither introduces new ones.
- **Predict before the options.** On Text Completion the drill asks for your own
  word first and says whether it matched, meant the same, or at least pointed
  the right way.
- **Coverage, not word count.** Progress shows what share of core words is
  actually held, and how each of GregMat's 32 groups stands.
- **One anchor sentence, then variety,** and writing prompts that ask for a
  sentence about your own life.

## Order, mastery, and the other two screens

The words are ordered by exam value first, since a word on eight prep lists is
likelier to appear than one on a single list: Core (on three or more lists, 915
words), Common (two, 697), Extended (one, 1,286). Inside each tier the order is
easiest first by the hand-assigned rating, so the app opens with `subtle`,
`modest`, `elaborate`, `profound`. There is no deck grid. The schedule decides
what comes next, and numbered tiles only invited second-guessing it.

Each word carries a mastery level read off its FSRS stability: new, learning,
familiar at three days, known at three weeks, mastered at three months. A lapse
collapses stability, so the level drops on its own without any separate
bookkeeping.

Challenge is twenty questions over words you have already met, seeded from the
day so it is the same set however often you open it and a new one tomorrow. It
needs no API key.

Drill is the exam's own shapes: 324 hand-written Text Completion and Sentence
Equivalence questions over 408 words. Questions are chosen by the shakiest word
they contain rather than on a schedule of their own, because the same sentence
asked twice tests the sentence. Both screens feed the scheduler like any other
review, because they are evidence about your memory.

## Where the words come from

Eleven curated GRE lists (GregMat, Magoosh, Manhattan, Barron's, PrepScholar,
Powerscore, Greenlight, Vocabulary.com), deduplicated to 2,898 and tiered by how
many lists carry each word.

The lists are bare word lists. No definitions, which is the licensing problem
solved rather than a gap: prep-book definitions are copyrighted, so the meanings
had to come from somewhere else.

That somewhere else was [Open English WordNet](https://en-word.net/) (CC BY 4.0),
and for a while the app shipped its first sense for every word. This works badly.
WordNet orders senses for lexicographers, and it includes proper nouns. `court`
led with an Australian tennis player. `acumen` led with "a tapering point".
`zephyr` was a Greek god, `ravel` a French composer, `milk` a river in Montana.

So every word now carries a hand-written GRE sense instead: part of speech, a
plain-English definition under fifteen words, three or four synonyms at the right
register, antonyms where they exist, and two example sentences written to be
memorable rather than merely grammatical.

```json
"laconic": {
  "pos": "adjective",
  "definition": "using very few words",
  "synonyms": ["terse", "curt", "succinct"],
  "antonyms": ["verbose", "loquacious"],
  "sentences": [
    "Asked to describe the disaster, the laconic engineer said only: \"It fell.\"",
    "Sparta was so laconic that a threat of invasion drew a one-word reply: \"If.\""
  ]
}
```

The multiple-choice wrong answers are hand-written too, for the same reason the
definitions are. Filling the other three slots with other words' definitions
makes the question answerable without knowing the word: only one of the four is
about the right kind of thing at all, and the learner picks it by elimination.
So every word ships three near misses instead, wrong on the one point that
matters.

```json
"abate": ["to postpone deliberately", "to spread outward", "to grow steadily worse"]
```

Those 5,796 sentences do double duty. Blanking the word out of them generates the
fill-in-the-blank mode, which is why that mode needed no new data. The 125 that read as
etymology notes rather than uses of the word are skipped, leaving 5,671 usable
gaps and at least one for every word.

WordNet is still in there for the fuller entry: extra senses, its own examples,
lexical detail, and for trap words the everyday sense that makes the drill work.
Pronunciation is `AVSpeechSynthesizer` in four accents, with IPA derived from
CMUdict for the 2,586 words it covers.

As a check on all this, I diffed the hand-written parts of speech against two
Magoosh word lists, which between them cover 987 of these words. They agree
everywhere except `jingoist`, where Magoosh's own heading contradicts its example
sentence. WordNet's first sense disagrees on 28.

## Layout

| Path | What | Builds where |
|---|---|---|
| `Sources/GRECore` | FSRS-6, the day plan, the curriculum, the queue, graders, OpenRouter client. Foundation only. | Linux and macOS |
| `App/` | SwiftUI app. `project.yml` becomes an Xcode project via XcodeGen. | macOS only |
| `tools/build_dataset.py` | Word lists, WordNet, CMUdict and the hand-written data into `words.json` | Linux |
| `tools/gre_senses/` | The hand-written senses, merged into `gre_senses.json` | |
| `tools/gre_difficulty/` | The 1 to 5 ratings, merged into `gre_difficulty.json` | |
| `tools/gre_options/` | The near-miss wrong answers, merged into `gre_options.json` | |

The split is deliberate. This was written on Linux, where there is no Xcode, so
everything with logic in it lives in `GRECore` and is tested locally. Only views
need a Mac. CI builds and tests the app on `macos-26` and produces an unsigned
`.ipa` you can re-sign with your own Apple ID.

## Develop

```sh
tools/setup-linux-toolchain.sh   # Swift, plus the libraries Arch names differently
. ./env.sh && swift test         # 174 tests
python3 tools/build_dataset.py   # regenerate words.json
python3 tools/build_dataset.py --verify-only   # check the committed one
```

The app target needs Xcode 26 and iOS 26.

`build_dataset.py` is strict on purpose. It refuses to write a dataset where a
word has no cloze-able sentence, where a word has fewer than three distinct wrong
answers, where a rating and its band disagree, where IPA coverage drops below 80%, or where a trap word has lost the everyday sense its
drill depends on. Corrupt vocabulary data is not obvious when you read it, and a
learner would just quietly learn the wrong thing.

## Testing notes

FSRS is a port, not a reinterpretation. Every step of seven review sequences is
checked against golden vectors generated from `py-fsrs` (`tools/gen_fsrs_vectors.py`).

`PublicSurfaceTests` imports GRECore without `@testable`, so it sees exactly what
the app sees. The rest of the suite uses `@testable` and structurally cannot catch
a type whose memberwise init was never made public. Without that file, those break
on a macOS runner several minutes away.

The dataset has its own tests, and they have earned their place. They caught a
cloze that blanked only the first occurrence, so *"a king may abdicate a throne; a
parent cannot abdicate a child"* printed its own answer. They caught `hallmark`
listing itself as a synonym. They caught trap words losing the everyday sense that
makes their drill work.

The answer-speed adjustment has a guard of its own. If its thresholds ran loose,
every quick answer would rate Easy, intervals would stretch across every word,
and nobody would find out until a month before the exam. So a test simulates
ninety days of daily reviews and asserts two things: someone who answers quickly
schedules bit-identically to before the feature existed, and hesitation can only
ever shorten an interval. A second test walks every mode, rating and answer time
and asserts the rating is never raised.

A live suite exercises a real OpenRouter call, gated behind
`OPENROUTER_API_KEY=sk-… swift test`.

## Design

Typographic, one warm accent, and honest in both appearances. Surfaces and text
come from the system's semantic colours so they follow light, dark and the
contrast setting; only the four brand colours are stated by hand, and each states
both halves, because a colour defined once for dark is invisible in daylight.
Type is set in text styles rather than point sizes, so the whole app scales with
the reader's setting. Liquid Glass is confined to the floating action bar: Apple's
rule is that glass sits above content rather than becoming it, and glass cannot
sample glass, so the card under study is a solid surface.

## Privacy

The OpenRouter key lives in the Keychain as `WhenUnlockedThisDeviceOnly`. It is a
bearer credential that can spend money, so it should not ride along in a backup.
Your answers go to whichever model you pick. Nothing else leaves the device.

Every model call — grading, a mnemonic, a deep dive, the coach — is counted in one
ledger and checked against a spending limit *before* the call is made. Refusing
after the money is gone is not a limit. Settings shows what has been spent today
and in total.

Settings has a reset that deletes every studied word, review, test score and
cached lookup, and puts the preferences back to defaults. It leaves the API key
alone, on the grounds that wiping your progress should not also lock you out of
the graded mode.

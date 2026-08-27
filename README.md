# GRE Vocabulary Trainer

An iOS vocabulary trainer built on one opinion: turning a flashcard over and
thinking *yeah, I knew that* is recognition, and recognition is not what the exam
asks for. So the app makes you produce. You write the definition and a sentence
using the word, a model grades both, and the grade drives an FSRS-6 scheduler.
Words you actually fail come back within minutes. Words you own get out of the way.

2,898 words, each with a hand-written definition of the sense the GRE tests, two
example sentences, synonyms, antonyms, and a difficulty rating I assigned by hand.
None of it is scraped from a prep book.

## Study modes

| Mode | What you do | Graded by |
|---|---|---|
| Multiple choice | Meet a new word, pick its definition | locally, free |
| In context | A sentence with the word blanked out; pick what fits | locally, free |
| Which meaning | A common word in its uncommon tested sense; pick the meaning | locally, free |
| Reverse recall | Definition shown, name the word | locally, free |
| Spelling | Hear it in your chosen accent, type it | locally, free |
| Define and use | Write a definition and a sentence | a model, via OpenRouter |

Five of the six work with no API key and no network. Only the writing mode needs
one, because grading a free-text answer is the one thing a phone cannot do alone.

The modes climb as your memory of a word gets stronger: recognise it, use it in a
sentence, recall it cold, spell it, then write with it. How soon a word reaches
the writing mode is a setting. Set it to zero and every word starts there.

## Trap words

The most interesting problem in the dataset turned out to be words like `august`,
`flag`, `pine`, `base`, `wax` and `plastic`.

Every one of those is a common English word. Measure difficulty by how often the
word appears in ordinary text, which is what I did at first, and they come out as
the easiest words in the entire list. They landed in deck one. But the exam does
not test the month, the piece of cloth, or the tree. It tests *majestic*, *to
weaken*, *to yearn*, *contemptible*, *to increase*, *malleable*. Those are among
the hardest things on the paper.

Frequency measures the word form. The exam tests a meaning. For 401 of the 2,898
words the two come apart, and those are exactly the words that cost people points,
because you read the sentence, recognise the word, and never notice you got it wrong.

Two things follow from that. Difficulty is rated by hand on the tested sense, so
`august` is a 4 and `modest` is a 1, and decks are ordered by that rating rather
than by frequency. And the 401 get their own drill: the sentence appears with the
word intact, and you pick which of four meanings applies. The wrong answers are
that word's own everyday senses, pulled from WordNet, so the bait is the meaning
you already believe.

> *Attention flagged in the third hour and nobody pretended otherwise.*
>
> to weaken or lose energy · an emblem of cloth · to signal with a flag · to provide with a flag

The drill fires on a trap word's second outing, early enough to correct the
assumption before it sets. It never fires for an ordinary word, since asking
which meaning of `laconic` is being used has only one answer.

## Pace and decks

There is no daily quota and no fixed session length. A session runs until you
stop. It serves due reviews first, ordered by which ones you are most likely to
have forgotten rather than by which are most overdue, then introduces new words
from your current deck.

How many new words you get depends on how you are doing. The planner counts the
words currently half-learned and stops introducing new ones past a cap: four if
your recent accuracy is under 60%, twelve if it is over 85%, eight otherwise. A
bad day slows the intake instead of burying you.

The words are split into 117 decks of 23 to 25. Three tiers by exam value first,
since a word on eight prep lists is likelier to appear than one on a single list:
Core (on three or more lists, 915 words), Common (two, 697), Extended (one, 1,286).
Inside each tier the order is easiest first by the hand-assigned rating, so Core 1
opens with `subtle`, `modest`, `elaborate`, `profound`.

Each word carries a mastery level read off its FSRS stability: new, learning,
familiar at three days, known at three weeks, mastered at three months. A lapse
collapses stability, so the level drops on its own without any separate
bookkeeping. Decks show a ring of the average.

Once you have studied five words in a deck you can test it. There is also a test
over everything you know, which samples the words you are most likely to have
forgotten rather than sampling evenly. Test answers feed the scheduler like any
other review, because they are evidence about your memory.

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
| `Sources/GRECore` | FSRS-6, planners, graders, OpenRouter client. Foundation only. | Linux and macOS |
| `App/` | SwiftUI app. `project.yml` becomes an Xcode project via XcodeGen. | macOS only |
| `tools/build_dataset.py` | Word lists, WordNet, CMUdict and the hand-written data into `words.json` | Linux |
| `tools/gre_senses/` | The hand-written senses, merged into `gre_senses.json` | |
| `tools/gre_difficulty/` | The 1 to 5 ratings, merged into `gre_difficulty.json` | |

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
word has no cloze-able sentence, where a rating and its band disagree, where IPA
coverage drops below 80%, or where a trap word has lost the everyday sense its
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

A live suite exercises a real OpenRouter call, gated behind
`OPENROUTER_API_KEY=sk-… swift test`.

## Design

Dark, typographic, one warm accent. Liquid Glass is confined to the floating
action bar. Apple's rule is that glass sits above content rather than becoming it,
and glass cannot sample glass, so the card under study is a solid surface.

## Privacy

The OpenRouter key lives in the Keychain as `WhenUnlockedThisDeviceOnly`. It is a
bearer credential that can spend money, so it should not ride along in a backup.
Your answers go to whichever model you pick. Nothing else leaves the device.

Settings has a reset that deletes every studied word, review, test score and
cached lookup, and puts the preferences back to defaults. It leaves the API key
alone, on the grounds that wiping your progress should not also lock you out of
the graded mode.

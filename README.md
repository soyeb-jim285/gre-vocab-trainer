# GRE Vocabulary Trainer

An iOS vocabulary trainer that refuses to let you fool yourself.

Flipping a flashcard and thinking *yeah, I knew that* is recognition, not recall.
This app makes you produce instead: the word appears, you type a definition **and**
a sentence using it, and a model grades both against a reference definition.
That grade drives FSRS-6, so words you actually fail come back and words you own
stop wasting your time.

## Study modes

| Mode | What you do | Graded by |
|---|---|---|
| Multiple choice | Meet a new word, pick its definition | locally, free |
| Reverse recall | Definition shown, name the word | locally, free |
| Spelling | Hear it in your chosen accent, type it | locally, free |
| Define & use | Write a definition and a sentence | a model, via OpenRouter |

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

## The word list

2,898 words merged from eleven curated GRE lists (GregMat, Magoosh, Manhattan,
Barron's, PrepScholar, Powerscore, Greenlight, Vocabulary.com), deduplicated and
tiered by how many lists carry each word — words on three or more are taught first.

Definitions come from [Open English WordNet](https://en-word.net/) (CC BY 4.0),
never from the prep books the lists are named after. Pronunciation is
`AVSpeechSynthesizer` in four accents, with IPA derived from CMUdict.

## Layout

| Path | What | Builds where |
|---|---|---|
| `Sources/GRECore` | FSRS-6, graders, session planner, OpenRouter client. Foundation only. | Linux + macOS |
| `App/` | SwiftUI app. `project.yml` → Xcode project via XcodeGen. | macOS only |
| `tools/build_dataset.py` | Word lists + WordNet + CMUdict → `words.json` | Linux |

The split is deliberate: development happens on Linux, where there is no Xcode.
Everything with logic in it lives in `GRECore` and is tested locally; only views
need a Mac. CI builds the app on `macos-26`.

## Develop

```sh
tools/setup-linux-toolchain.sh   # Swift + the libraries Arch names differently
. ./env.sh && swift test         # 147 tests
python3 tools/build_dataset.py   # regenerate the word dataset
```

The app target needs Xcode 26 / iOS 26.

### Testing notes

- **FSRS is a port, not a reinterpretation.** Every step of seven review sequences
  is checked against golden vectors generated from `py-fsrs`
  (`tools/gen_fsrs_vectors.py`).
- **`PublicSurfaceTests` imports GRECore without `@testable`**, so it sees exactly
  what the app sees. The rest of the suite uses `@testable` and structurally
  cannot catch a type whose memberwise init was never made public — that would
  otherwise only surface on a macOS runner minutes away.
- **A live suite** exercises a real OpenRouter call, gated behind
  `OPENROUTER_API_KEY=sk-… swift test`.

## Design

Dark, typographic, one warm accent. Liquid Glass is confined to the floating
action bar: Apple's rule is that glass sits *above* content rather than becoming
it, and glass cannot sample glass. The flashcard itself is a solid surface.

## Privacy

The OpenRouter key lives in the Keychain as `WhenUnlockedThisDeviceOnly` — it is a
bearer credential that can spend money, so it does not ride along in a backup.
Answers are sent to whichever model you choose; nothing else leaves the device.

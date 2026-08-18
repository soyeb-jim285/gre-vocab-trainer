# GRE Vocabulary Trainer

iOS app for GRE vocabulary. Not recognition flashcards — you type the definition
and a sentence, an AI grades both, and FSRS-6 decides when you see the word again.

## Layout

| Path | What | Where it builds |
|---|---|---|
| `Sources/GRECore` | Scheduler, graders, OpenRouter client, models. Foundation only. | Linux + macOS |
| `App/` | SwiftUI app. `project.yml` → Xcode project via XcodeGen. | macOS / CI only |
| `tools/build_dataset.py` | Word list + WordNet + IPA → `words.json` | Linux |

## Develop

```sh
swift test                       # core logic
python3 tools/build_dataset.py   # regenerate word dataset
```

The app target needs Xcode 26 / iOS 26. CI builds it on `macos-26`.

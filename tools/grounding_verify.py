#!/usr/bin/env python3
"""Check the grounding shards before they reach the dataset.

Generated data without a verifier rots. These are the rules the grader depends
on, so a violation has to stop the build rather than quietly degrade grading:

  - an accepted concept that contains the word is not a paraphrase, it is a
    restatement, and it would let "abate means to abate" score full marks
  - a hint containing the word gives the answer away
  - a concept in both the accepted and incorrect lists makes grading undecidable
  - a required nuance that just repeats the definition cannot separate a
    precise answer from a vague one, which is the whole reason it exists

    python3 tools/grounding_verify.py
"""

from __future__ import annotations

import glob
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORDS = ROOT / "Sources" / "GRECore" / "Resources" / "words.json"
SHARDS = ROOT / "tools" / "gre_grounding"

MIN_ACCEPTED = 4
MIN_INCORRECT = 2
MAX_NUANCE = 70
MAX_HOOK = 140


def stem(word: str) -> str:
    """Crude but adequate: enough to catch a hint leaking its own answer."""
    for suffix in ("ously", "ately", "ing", "ed", "es", "ly", "e", "s"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 4:
            return word[: -len(suffix)]
    return word


def leaks(text: str, word: str) -> bool:
    root = stem(word.lower())
    return re.search(rf"\b{re.escape(root)}", text.lower()) is not None


def main() -> int:
    words = {w["id"]: w for w in json.loads(WORDS.read_text())}
    problems: list[str] = []
    seen: dict[str, str] = {}

    for path in sorted(glob.glob(str(SHARDS / "*.json"))):
        name = Path(path).name
        try:
            shard = json.loads(Path(path).read_text())
        except json.JSONDecodeError as error:
            problems.append(f"{name}: not valid JSON ({error})")
            continue

        for word, block in shard.items():
            where = f"{name}:{word}"
            if word not in words:
                problems.append(f"{where}: not in the dataset")
                continue
            if word in seen:
                problems.append(f"{where}: already grounded in {seen[word]}")
            seen[word] = name

            accepted = block.get("accepted_concepts", [])
            incorrect = block.get("incorrect_associations", [])
            nuance = (block.get("required_nuance") or "").strip()
            hook = (block.get("mental_hook") or "").strip()
            hint = (block.get("semantic_hint") or "").strip()

            if len(accepted) < MIN_ACCEPTED:
                problems.append(f"{where}: {len(accepted)} accepted concepts, need {MIN_ACCEPTED}")
            for concept in accepted:
                if leaks(concept, word):
                    problems.append(f"{where}: accepted concept restates the word ({concept!r})")
            if len(set(c.lower() for c in accepted)) != len(accepted):
                problems.append(f"{where}: duplicate accepted concepts")

            if len(incorrect) < MIN_INCORRECT:
                problems.append(f"{where}: {len(incorrect)} incorrect associations, need {MIN_INCORRECT}")
            for entry in incorrect:
                if not entry.get("answer", "").strip():
                    problems.append(f"{where}: an incorrect association has no answer")
                if not entry.get("misconception", "").strip():
                    problems.append(f"{where}: {entry.get('answer')!r} names no misconception")

            overlap = {c.lower() for c in accepted} & {
                e.get("answer", "").lower() for e in incorrect
            }
            if overlap:
                problems.append(f"{where}: {sorted(overlap)} is both accepted and incorrect")

            if not nuance:
                problems.append(f"{where}: no required nuance")
            elif len(nuance) > MAX_NUANCE:
                problems.append(f"{where}: required nuance is {len(nuance)} chars, max {MAX_NUANCE}")
            elif nuance.lower() == words[word]["gre"]["definition"].lower():
                problems.append(f"{where}: required nuance just repeats the definition")

            if not hook:
                problems.append(f"{where}: no mental hook")
            elif len(hook) > MAX_HOOK:
                problems.append(f"{where}: hook is {len(hook)} chars, max {MAX_HOOK}")

            if not hint:
                problems.append(f"{where}: no semantic hint")
            elif leaks(hint, word):
                problems.append(f"{where}: the hint gives the word away")

    if problems:
        for problem in problems[:60]:
            print(f"  {problem}")
        if len(problems) > 60:
            print(f"  ... and {len(problems) - 60} more")
        print(f"\n{len(problems)} problem(s) across {len(seen)} grounded words")
        return 1

    print(f"{len(seen)} grounded words, all clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())

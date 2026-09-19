#!/usr/bin/env python3
"""Check the word-origin shards before they reach the dataset.

The shards were drafted by a model and spot-checked by hand, so the machine
checks here are the floor, not the review:

  - every word in the dataset has exactly one entry, and no entry names a word
    the dataset does not carry
  - a "cousin" that is the word itself plus a suffix teaches nothing: the point
    is a word the learner already knows that shares a root
  - no em dashes, per the house style for learner-facing text
  - `path` stays short enough to read on a phone in one glance

    python3 tools/etymology_verify.py
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORDS = ROOT / "Sources" / "GRECore" / "Resources" / "words.json"
SHARDS = ROOT / "tools" / "gre_etymology"

MAX_PATH_WORDS = 90
CHARGES = {"positive", "negative", "neutral"}
CONFIDENCE = {"high", "medium", "low"}


# Endings that make a form of the same word rather than a different one.
SUFFIXES = {"", "s", "es", "d", "ed", "ing", "ly", "ion", "ions", "ation", "er", "ers",
            "ness", "ment", "ity", "al", "ally", "ive"}


def same_word(a: str, b: str) -> bool:
    """True when one is the other plus an inflection or a stock suffix:
    frustrate and frustration, venerate and venerated. Urban and urbane, or
    torpor and torpid, are different words sharing a root, which is the point."""
    a, b = a.lower(), b.lower()
    short, long = sorted((a, b), key=len)
    base = short[:-1] if short.endswith("e") else short
    return long.startswith(base) and long[len(base):] in SUFFIXES | {"e" + s for s in SUFFIXES if s}


def problems_for(word: str, e: dict) -> list[str]:
    out = []
    parts = e.get("parts") or []
    if not parts or not all(p.get("piece") and p.get("meaning") and p.get("origin") for p in parts):
        out.append("a part with no piece, meaning or origin")
    if not e.get("literal") or not e.get("path"):
        out.append("missing literal or path")
    if len(e.get("path", "").split()) > MAX_PATH_WORDS:
        out.append(f"path over {MAX_PATH_WORDS} words")
    if e.get("confidence") not in CONFIDENCE:
        out.append(f"confidence {e.get('confidence')!r}")
    if not isinstance(e.get("transparent"), bool):
        out.append("transparent is not a bool")
    if e.get("charge") not in CHARGES:
        out.append(f"charge {e.get('charge')!r}")
    for cousin in e.get("cousins", []):
        if same_word(word, cousin):
            out.append(f"cousin {cousin!r} is the word itself")
    for field in ("literal", "path"):
        if "—" in e.get(field, ""):
            out.append(f"em dash in {field}")
    return out


def main() -> int:
    known = {w["id"] for w in json.loads(WORDS.read_text(encoding="utf-8"))}
    seen: Counter[str] = Counter()
    failures: list[str] = []
    for path in sorted(SHARDS.glob("*.json")):
        shard = json.loads(path.read_text(encoding="utf-8"))
        for word, entry in shard.items():
            seen[word] += 1
            if word not in known:
                failures.append(f"{path.name}: {word}: not in the dataset")
            failures += [f"{path.name}: {word}: {p}" for p in problems_for(word, entry)]

    failures += [f"{w}: in {n} shards" for w, n in seen.items() if n > 1]
    missing = sorted(known - set(seen))
    if missing:
        failures.append(f"{len(missing)} words have no entry, e.g. {', '.join(missing[:8])}")

    for line in failures:
        print(line)
    if failures:
        print(f"\n{len(failures)} problems")
        return 1
    print(f"OK: {len(seen)} origins, every word covered")
    return 0


if __name__ == "__main__":
    sys.exit(main())

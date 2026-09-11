#!/usr/bin/env python3
"""Compute confusion-pair candidates from the dataset.

Pass two of the grounding work annotates pairs of words a learner is likely to
mix up. Asking a model to find those pairs across 2,898 words would be 2,898
open questions; computing the candidates first turns it into a few hundred
closed ones. That is the whole point of this file: it proposes, the annotator
disposes.

Three signals, each a different kind of confusion:

  synonym   the two words share two or more GRE synonyms, so a learner who
            knows one meaning has no way to tell which word carries it
            (laconic / taciturn)
  form      the two ids are within a small edit distance, so they look or
            sound alike whatever they mean (imminent / eminent)
  mutual    each word appears in the other's synonym list, the strongest
            evidence the dataset itself offers

Usage:
    python3 tools/confusion_candidates.py [--limit N] [--json PATH]
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from itertools import combinations
from pathlib import Path

DATASET = Path(__file__).resolve().parent.parent / "Sources/GRECore/Resources/words.json"

# A shared pair of synonyms is meaningful; one is coincidence. Two words of very
# different length are not confusable by form however few edits separate them,
# and an edit distance of one on short words catches rhymes rather than traps.
MIN_SHARED_SYNONYMS = 2
MAX_EDIT_DISTANCE = 2
MIN_FORM_LENGTH = 5


def edit_distance(a: str, b: str, cap: int) -> int:
    """Levenshtein distance, abandoned once it exceeds `cap`."""
    if abs(len(a) - len(b)) > cap:
        return cap + 1
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                previous[j] + 1,
                current[j - 1] + 1,
                previous[j - 1] + (ca != cb),
            ))
        if min(current) > cap:
            return cap + 1
        previous = current
    return previous[-1]


def inflections(a: str, b: str) -> bool:
    """True when two ids are forms of the same word rather than two words.

    `venerate` and `venerated` differ by one edit, but a learner who confuses
    them has not confused anything: they are the same word wearing a suffix.
    Filtering them out is what keeps the form signal pointing at real traps
    like `amend` and `emend`.
    """
    short, long = sorted((a, b), key=len)
    if not long.startswith(short):
        return False
    return long[len(short):] in {"d", "s", "ed", "es", "ing", "er"}


def load_words() -> list[dict]:
    return json.loads(DATASET.read_text())


def synonym_sets(words: list[dict]) -> dict[str, set[str]]:
    """Every synonym the dataset offers for a word, GRE sense and other senses."""
    out: dict[str, set[str]] = {}
    for w in words:
        syns = set(w.get("gre", {}).get("synonyms", []))
        for sense in w.get("senses", []):
            syns.update(sense.get("synonyms", []))
        out[w["id"]] = {s.lower() for s in syns}
    return out


def candidates(words: list[dict]) -> list[dict]:
    ids = [w["id"] for w in words]
    syns = synonym_sets(words)
    definitions = {w["id"]: w.get("gre", {}).get("definition", "") for w in words}
    found: dict[tuple[str, str], dict] = {}

    def record(a: str, b: str, signal: str, detail: str) -> None:
        key = (a, b) if a < b else (b, a)
        entry = found.setdefault(key, {
            "a": key[0],
            "b": key[1],
            "signals": [],
            "detail": {},
            "definitions": [definitions[key[0]], definitions[key[1]]],
        })
        if signal not in entry["signals"]:
            entry["signals"].append(signal)
            entry["detail"][signal] = detail

    # Synonym overlap. Inverting the synonym map first keeps this near linear
    # instead of comparing every word with every other.
    by_synonym: dict[str, list[str]] = defaultdict(list)
    for word_id, words_syns in syns.items():
        for s in words_syns:
            by_synonym[s].append(word_id)
    shared: dict[tuple[str, str], set[str]] = defaultdict(set)
    for synonym, holders in by_synonym.items():
        if len(holders) < 2 or len(holders) > 12:
            continue  # a synonym shared by a dozen words discriminates nothing
        for a, b in combinations(sorted(holders), 2):
            shared[(a, b)].add(synonym)
    for (a, b), common in shared.items():
        if len(common) >= MIN_SHARED_SYNONYMS:
            record(a, b, "synonym", ", ".join(sorted(common)))

    # Mutual synonymy: each names the other.
    for a in ids:
        for b in syns[a]:
            if b in syns and a in syns[b]:
                record(a, b, "mutual", "each lists the other")

    # Form similarity. Bucketing by length keeps the comparison tractable.
    by_length: dict[int, list[str]] = defaultdict(list)
    for word_id in ids:
        if len(word_id) >= MIN_FORM_LENGTH:
            by_length[len(word_id)].append(word_id)
    for length, bucket in by_length.items():
        neighbours = bucket + [w for d in range(1, MAX_EDIT_DISTANCE + 1)
                              for w in by_length.get(length + d, [])]
        for a, b in combinations(sorted(set(neighbours)), 2):
            if len(a) < MIN_FORM_LENGTH or len(b) < MIN_FORM_LENGTH:
                continue
            if inflections(a, b):
                continue
            d = edit_distance(a, b, MAX_EDIT_DISTANCE)
            if d <= MAX_EDIT_DISTANCE:
                record(a, b, "form", f"edit distance {d}")

    # A pair flagged by more than one signal is likelier to trip a learner, so
    # rank by signal count and let the annotation pass work down the list.
    ordered = sorted(found.values(), key=lambda e: (-len(e["signals"]), e["a"], e["b"]))
    return ordered


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="print only the first N")
    ap.add_argument("--json", type=Path, help="write the full list to a file")
    ap.add_argument("--worklist", action="store_true",
                    help="keep only the pairs worth annotating")
    args = ap.parse_args()

    words = load_words()
    pairs = candidates(words)
    if args.worklist:
        # Two kinds of pair repay a written discrimination: near-synonyms a
        # learner cannot tell apart by meaning, and lookalikes they cannot tell
        # apart by shape. A single weak signal is not enough for either.
        pairs = [p for p in pairs
                 if len(p["signals"]) > 1
                 or (p["signals"] == ["form"]
                     and p["detail"]["form"] == "edit distance 1")]

    by_signal: dict[str, int] = defaultdict(int)
    for p in pairs:
        for s in p["signals"]:
            by_signal[s] += 1
    print(f"{len(pairs)} candidate pairs from {len(words)} words")
    for signal in sorted(by_signal):
        print(f"  {signal}: {by_signal[signal]}")

    if args.json:
        args.json.write_text(json.dumps(pairs, indent=2, ensure_ascii=False) + "\n")
        print(f"wrote {args.json}")

    for p in pairs[:args.limit]:
        print(f"{p['a']} / {p['b']}  [{'+'.join(p['signals'])}]")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Pass two of the grounding work: annotate confusion pairs.

`confusion_candidates.py` computes which pairs of words a learner is likely to
mix up. This file manages the written discrimination for each one: which pairs
still need a line, merging a batch of written lines into the shards, and
checking that what was written actually discriminates.

The rule that matters is the opposite of the grounding verifier's. There a hint
must never name its own word; here a discrimination is useless unless it names
both, because the whole job is to set one against the other.

    python3 tools/confusion.py next [N]        pairs still needing a line
    python3 tools/confusion.py merge FILE      fold a written batch into shards
    python3 tools/confusion.py verify          check every line written so far
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SHARDS = ROOT / "gre_confusion"
WORKLIST = ROOT / "gre_confusion_pairs.json"
SHARD_SIZE = 100

MAX_DISTINCTION = 220
MIN_DISTINCTION = 40


def key_of(pair: dict) -> str:
    return f"{pair['a']}|{pair['b']}"


def load_worklist() -> list[dict]:
    if not WORKLIST.exists():
        sys.exit(f"missing {WORKLIST}; run confusion_candidates.py --worklist --json {WORKLIST}")
    return json.loads(WORKLIST.read_text())


def load_shards() -> dict[str, dict]:
    out: dict[str, dict] = {}
    for path in sorted(SHARDS.glob("*.json")):
        out.update(json.loads(path.read_text()))
    return out


def stem(word: str) -> str:
    """Loose stem, so a line may say `trenchancy` for `trenchant`."""
    for suffix in ("ously", "ately", "ing", "ed", "es", "ly", "e", "s"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 4:
            return word[: -len(suffix)]
    return word


def names(text: str, word: str) -> bool:
    return re.search(rf"\b{re.escape(stem(word))}", text, re.I) is not None


def cmd_next(limit: int) -> None:
    worklist = load_worklist()
    done = load_shards()
    pending = [p for p in worklist if key_of(p) not in done]
    print(f"annotated {len(worklist) - len(pending)}/{len(worklist)}  remaining {len(pending)}")
    if not pending:
        print("all pairs annotated")
        return
    print()
    for pair in pending[:limit]:
        print(json.dumps({
            "key": key_of(pair),
            "a": pair["a"],
            "a_definition": pair["definitions"][0],
            "b": pair["b"],
            "b_definition": pair["definitions"][1],
            "signals": pair["signals"],
        }, ensure_ascii=False))


def cmd_merge(path: Path) -> None:
    batch = json.loads(path.read_text())
    worklist = load_worklist()
    index = {key_of(p): i for i, p in enumerate(worklist)}
    SHARDS.mkdir(exist_ok=True)

    by_shard: dict[int, dict] = {}
    for key, entry in batch.items():
        if key not in index:
            sys.exit(f"{key} is not in the worklist")
        by_shard.setdefault(index[key] // SHARD_SIZE, {})[key] = entry

    for shard, entries in sorted(by_shard.items()):
        path_out = SHARDS / f"{shard:03d}.json"
        existing = json.loads(path_out.read_text()) if path_out.exists() else {}
        for key in entries:
            if key in existing:
                sys.exit(f"{key} already annotated in {path_out.name}")
        existing.update(entries)
        path_out.write_text(json.dumps(existing, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
        print(f"  {path_out.name}: {len(existing)} entries")


def cmd_verify() -> None:
    done = load_shards()
    problems: list[str] = []
    for key, entry in sorted(done.items()):
        a, b = key.split("|")
        line = entry.get("distinction", "").strip()
        if not line:
            problems.append(f"{key}: no distinction written")
            continue
        if len(line) > MAX_DISTINCTION:
            problems.append(f"{key}: distinction over {MAX_DISTINCTION} chars")
        if len(line) < MIN_DISTINCTION:
            problems.append(f"{key}: distinction too short to discriminate")
        for word in (a, b):
            if not names(line, word):
                problems.append(f"{key}: distinction never names '{word}'")
    for p in problems:
        print(p)
    if problems:
        sys.exit(f"\n{len(problems)} problem(s) across {len(done)} annotated pairs")
    print(f"{len(done)} annotated pairs, all clean")


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    command = sys.argv[1]
    if command == "next":
        cmd_next(int(sys.argv[2]) if len(sys.argv) > 2 else 20)
    elif command == "merge":
        cmd_merge(Path(sys.argv[2]))
    elif command == "verify":
        cmd_verify()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()

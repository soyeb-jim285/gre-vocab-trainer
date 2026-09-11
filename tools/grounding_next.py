#!/usr/bin/env python3
"""Show the next words still missing a grounding block, with the data needed
to write one.

The grounding blocks are written by hand (by a model in the loop, not by an API
call), so this is the other half of that: it says what is left and hands over
exactly the context each entry needs -- the GRE-tested sense, not WordNet's
first sense, because that is what the grader will be held to.

    python3 tools/grounding_next.py            # next 40 words
    python3 tools/grounding_next.py 60         # next 60
    python3 tools/grounding_next.py --progress # just the count
"""

from __future__ import annotations

import argparse
import glob
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORDS = ROOT / "Sources" / "GRECore" / "Resources" / "words.json"
SHARDS = ROOT / "tools" / "gre_grounding"

SHARD_SIZE = 100


def load_done() -> dict[str, dict]:
    done: dict[str, dict] = {}
    for path in sorted(glob.glob(str(SHARDS / "*.json"))):
        with open(path) as handle:
            done.update(json.load(handle))
    return done


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("count", nargs="?", type=int, default=40)
    parser.add_argument("--progress", action="store_true")
    args = parser.parse_args()

    words = json.loads(WORDS.read_text())
    done = load_done()
    todo = [w for w in words if w["id"] not in done]

    print(f"grounded {len(done)}/{len(words)}  remaining {len(todo)}")
    if args.progress or not todo:
        if not todo:
            print("all words grounded")
        return

    # Which shard the next batch belongs in, so entries land in index order.
    start = len(words) - len(todo)
    print(f"next shard: {SHARDS.name}/{start // SHARD_SIZE + 1:03d}.json "
          f"(covers words {start // SHARD_SIZE * SHARD_SIZE}.."
          f"{start // SHARD_SIZE * SHARD_SIZE + SHARD_SIZE - 1})")
    print()

    for word in todo[: args.count]:
        gre = word["gre"]
        print(json.dumps({
            "id": word["id"],
            "pos": gre["pos"],
            "definition": gre["definition"],
            "synonyms": gre["synonyms"],
            "antonyms": gre["antonyms"],
            "isTrap": word["isTrap"],
            # The everyday senses a trap word gets confused with.
            "otherSenses": [s["definition"] for s in word["senses"]][:3]
            if word["isTrap"] else [],
        }, ensure_ascii=False))


if __name__ == "__main__":
    main()

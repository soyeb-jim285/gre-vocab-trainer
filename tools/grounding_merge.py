#!/usr/bin/env python3
"""Merge a batch of grounding entries into the right shards.

Entries are written a batch at a time, but they have to land in the shard that
covers their index in the dataset, so the shards stay in the same order the
words are in. Refuses to overwrite an entry that is already grounded.

    python3 tools/grounding_merge.py batch.json
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORDS = ROOT / "Sources" / "GRECore" / "Resources" / "words.json"
SHARDS = ROOT / "tools" / "gre_grounding"
SHARD_SIZE = 100


def main() -> int:
    batch = json.loads(Path(sys.argv[1]).read_text())
    order = {w["id"]: i for i, w in enumerate(json.loads(WORDS.read_text()))}

    by_shard: dict[Path, dict] = {}
    for word, block in batch.items():
        if word not in order:
            print(f"  {word}: not in the dataset")
            return 1
        path = SHARDS / f"{order[word] // SHARD_SIZE + 1:03d}.json"
        if path not in by_shard:
            by_shard[path] = json.loads(path.read_text()) if path.exists() else {}
        if word in by_shard[path]:
            print(f"  {word}: already grounded")
            return 1
        by_shard[path][word] = block

    for path, shard in by_shard.items():
        ordered = dict(sorted(shard.items(), key=lambda kv: order[kv[0]]))
        path.write_text(json.dumps(ordered, indent=2, ensure_ascii=False) + "\n")
        print(f"  {path.name}: {len(ordered)} entries")
    return 0


if __name__ == "__main__":
    sys.exit(main())

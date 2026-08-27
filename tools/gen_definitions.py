#!/usr/bin/env python3
"""Ask a model for the GRE-tested sense of every word in the dataset.

WordNet is free and structured, which is why the app ships it, but its sense
order is not exam-aware ("court" leads with a tennis player) and its wording is
written for lexicographers. This fills that gap once, offline: one plain-English
definition and one example sentence per word, cached in tools/gre_senses.json so
the dataset build stays deterministic and needs no key.

    OPENROUTER_API_KEY=sk-... python3 tools/gen_definitions.py
    python3 tools/gen_definitions.py --limit 40      # try it on a few words first

The key may also live in tools/cache/.openrouter_key, which is gitignored.
Interrupt it any time: finished batches are already on disk and the next run
picks up the rest.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORDS = ROOT / "Sources" / "GRECore" / "Resources" / "words.json"
OUT = ROOT / "tools" / "gre_senses.json"
KEY_FILE = ROOT / "tools" / "cache" / ".openrouter_key"

ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"
MODEL = os.environ.get("GRE_DEF_MODEL", "google/gemini-3.7-flash")
BATCH = 20
WORKERS = 8
POS = {"noun", "verb", "adjective", "adverb"}

PROMPT = """You are compiling a GRE vocabulary reference.

For each word below, give the sense the GRE actually tests — the one a test\
 writer would use in a sentence-equivalence or text-completion question. Ignore\
 proper nouns, obsolete senses, and technical jargon senses.

For each word return:
- "word": the word, exactly as given
- "pos": one of noun, verb, adjective, adverb
- "definition": plain English, at most 15 words, no restating the word itself
- "sentence": one sentence of about 15-25 words using the word naturally at GRE\
 register, showing the meaning through context rather than defining it

Reply with a JSON array of objects, one per word, in the same order. No prose,\
 no markdown fence.

Words:
{words}"""


def load_key() -> str:
    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if not key and KEY_FILE.exists():
        key = KEY_FILE.read_text(encoding="utf-8").strip()
    if not key:
        sys.exit(
            "No API key. Set OPENROUTER_API_KEY, or write it to "
            f"{KEY_FILE.relative_to(ROOT)} (gitignored)."
        )
    return key


def ask(key: str, words: list[str]) -> list[dict]:
    """One batch, or an empty list if the reply cannot be trusted."""
    body = json.dumps({
        "model": MODEL,
        "temperature": 0.2,
        "messages": [{"role": "user", "content": PROMPT.format(words="\n".join(words))}],
    }).encode()
    request = urllib.request.Request(
        ENDPOINT, data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            payload = json.load(response)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        print(f"  ! {words[0]}…: {error}")
        return []

    text = payload["choices"][0]["message"]["content"].strip()
    text = re.sub(r"^```(?:json)?|```$", "", text, flags=re.MULTILINE).strip()
    try:
        items = json.loads(text)
    except json.JSONDecodeError:
        print(f"  ! {words[0]}…: reply was not JSON")
        return []
    return items if isinstance(items, list) else []


def clean(items: list[dict], expected: list[str]) -> dict[str, dict]:
    """Keep only well-formed entries for words we actually asked about."""
    wanted = set(expected)
    out = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        word = str(item.get("word", "")).strip().lower()
        pos = str(item.get("pos", "")).strip().lower()
        definition = " ".join(str(item.get("definition", "")).split())
        sentence = " ".join(str(item.get("sentence", "")).split())
        if word in wanted and pos in POS and definition and sentence:
            out[word] = {"pos": pos, "definition": definition, "sentence": sentence}
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, help="only do this many missing words")
    parser.add_argument("--redo", action="store_true", help="regenerate everything")
    args = parser.parse_args()

    words = [w["id"] for w in json.loads(WORDS.read_text(encoding="utf-8"))]
    done: dict[str, dict] = {}
    if OUT.exists() and not args.redo:
        done = json.loads(OUT.read_text(encoding="utf-8"))

    todo = [w for w in words if w not in done]
    if args.limit:
        todo = todo[: args.limit]
    if not todo:
        print(f"Nothing to do: all {len(words)} words are in {OUT.relative_to(ROOT)}")
        return 0

    key = load_key()
    batches = [todo[i:i + BATCH] for i in range(0, len(todo), BATCH)]
    print(f"{len(todo)} words, {len(batches)} batches, model {MODEL}")

    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for n, (batch, items) in enumerate(
            zip(batches, pool.map(lambda b: ask(key, b), batches)), start=1
        ):
            done.update(clean(items, batch))
            # Written every batch so an interrupt costs at most one batch.
            OUT.write_text(json.dumps(done, indent=1, sort_keys=True) + "\n", encoding="utf-8")
            print(f"  {n}/{len(batches)} · {len(done)} words held")

    missed = [w for w in todo if w not in done]
    print(f"Wrote {len(done)} to {OUT.relative_to(ROOT)}")
    if missed:
        print(f"{len(missed)} still missing (rerun to retry): {', '.join(missed[:10])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

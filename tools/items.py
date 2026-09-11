#!/usr/bin/env python3
"""Pass three: Text Completion and Sentence Equivalence questions.

These are the exam's own shapes rather than questions about a word, and they
are the one part of the dataset a machine cannot fully check. A blank has to
have a single best answer, and a Sentence Equivalence pair has to leave the
sentence meaning the same thing. Both are reading judgements. What this tool
does is the half that can be checked -- shape, vocabulary, and the two ways a
stem gives itself away -- so the human review has only the real question left
to answer.

Writing rules, learned the hard way:

  * Options are word ids, so the stem must read correctly with the dictionary
    form dropped in. "had _____ into a chain" needs a past participle and no id
    will supply one; "let the stall _____ into a chain" works.
  * Every option shares the answer's part of speech, or the wrong ones are
    eliminated on grammar without reading the sentence.
  * The stem must contain the clue that settles the answer, and must not use
    any option or a form of it -- the answer because it would give itself away,
    a distractor because naming it eliminates it.
  * No "a _____" or "an _____" in front of a mixed option list. The article
    settles which options can fit before the sentence is read.
  * The explanation says what in the sentence settles it, and names the answer.

    python3 tools/items.py targets [N]     words worth writing a question for
    python3 tools/items.py next [N]        targets still without one, with material
    python3 tools/items.py check FILE      validate a batch without merging it
    python3 tools/items.py merge FILE      fold a written batch into shards
    python3 tools/items.py verify          check every question written so far
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WORDS = ROOT.parent / "Sources" / "GRECore" / "Resources" / "words.json"
SHARDS = ROOT / "gre_items"
SHARD_SIZE = 50

BLANK = "_____"
MIN_EXPLANATION = 60
MAX_EXPLANATION = 320
MIN_STEM_WORDS = 8

KINDS = {"textCompletion": (5, 1), "sentenceEquivalence": (6, 2)}


def load_words() -> dict[str, dict]:
    return {w["id"]: w for w in json.loads(WORDS.read_text())}


def load_shards() -> dict[str, dict]:
    out: dict[str, dict] = {}
    for path in sorted(SHARDS.glob("*.json")):
        out.update(json.loads(path.read_text()))
    return out


def stem_of(word: str) -> str:
    """Loose stem, so a stem using `abated` still counts as naming `abate`."""
    for suffix in ("ously", "ately", "ing", "ed", "es", "ly", "e", "s"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 4:
            return word[: -len(suffix)]
    return word


def names(text: str, word: str) -> bool:
    return re.search(rf"\b{re.escape(stem_of(word))}", text, re.I) is not None


def priority(word: dict) -> tuple:
    """Worth a question in proportion to how likely the exam is to use it."""
    return (-word.get("listCount", 0), -word.get("rating", 0), word["id"])


def targets(words: dict[str, dict], limit: int) -> list[dict]:
    """Words with the material a question needs: a GRE sense and synonyms to
    build honest distractors from."""
    pool = [
        w for w in words.values()
        if w.get("gre") and w.get("grounding") and len(w["gre"].get("synonyms", [])) >= 2
    ]
    return sorted(pool, key=priority)[:limit]


def material(word: dict, words: dict[str, dict]) -> dict:
    """Everything a question writer needs in one line, so the work is writing
    the sentence rather than looking things up."""
    gre = word["gre"]
    near = [
        words[p["with"]] for p in (word.get("confusion") or []) if p["with"] in words
    ]
    return {
        "id": word["id"],
        "pos": gre.get("pos", ""),
        "definition": gre["definition"],
        "synonyms": gre.get("synonyms", [])[:6],
        "antonyms": gre.get("antonyms", [])[:4],
        "confusable_with": [
            {"id": n["id"], "definition": n["gre"]["definition"] if n.get("gre") else ""}
            for n in near[:4]
        ],
        "example": (gre.get("sentences") or [""])[0],
    }


def cmd_targets(limit: int) -> None:
    words = load_words()
    for word in targets(words, limit):
        print(word["id"])


def cmd_next(limit: int) -> None:
    words = load_words()
    done = load_shards()
    covered = {a for item in done.values() for a in item["answers"]}
    pool = targets(words, 4000)
    pending = [w for w in pool if w["id"] not in covered]
    print(f"questions {len(done)}  words covered {len(covered)}/{len(pool)}  remaining {len(pending)}")
    if not pending:
        print("every target word has a question")
        return
    print()
    for word in pending[:limit]:
        print(json.dumps(material(word, words), ensure_ascii=False))


def check(item_id: str, item: dict, words: dict[str, dict]) -> list[str]:
    """Everything a machine can say about one question."""
    problems: list[str] = []
    kind = item.get("kind")
    if kind not in KINDS:
        return [f"{item_id}: unknown kind {kind!r}"]
    option_count, answer_count = KINDS[kind]

    stem = item.get("stem", "").strip()
    options = item.get("options", [])
    answers = item.get("answers", [])
    explanation = item.get("explanation", "").strip()

    if stem.count(BLANK) != 1:
        problems.append(f"{item_id}: the stem needs exactly one {BLANK}")
    if len(stem.split()) < MIN_STEM_WORDS:
        problems.append(f"{item_id}: the stem is too short to contain a clue")
    if len(options) != option_count:
        problems.append(f"{item_id}: {len(options)} options, expected {option_count}")
    if len(set(options)) != len(options):
        problems.append(f"{item_id}: a repeated option")
    if len(answers) != answer_count:
        problems.append(f"{item_id}: {len(answers)} answers, expected {answer_count}")
    if not set(answers) <= set(options):
        problems.append(f"{item_id}: an answer that is not among the options")
    for option in options:
        if option not in words:
            problems.append(f"{item_id}: option '{option}' is not in the dataset")

    # A stem that uses any option, or a form of it, decides that option for the
    # reader: the answer if it is the answer, and an easy elimination if not.
    for option in options:
        if names(stem, option):
            problems.append(f"{item_id}: the stem uses '{option}'")

    # "a _____" and "an _____" eliminate half the options on grammar. Either
    # every option starts with a vowel or none does, or the stem has to be
    # reworded around the article.
    article = re.search(rf"\b(an?)\s+{re.escape(BLANK)}", stem, re.I)
    if article:
        vowels = {o[:1].lower() in "aeiou" for o in options}
        if len(vowels) > 1:
            problems.append(f"{item_id}: '{article.group(1)} {BLANK}' picks the options "
                            "that start with a vowel")

    # Options that are not the same part of speech do not fit the blank
    # grammatically, so they are eliminated without reading the sentence.
    parts = {
        words[o]["gre"].get("pos", "") for o in options
        if o in words and words[o].get("gre")
    }
    if len(parts) > 1:
        problems.append(f"{item_id}: options mix parts of speech: {sorted(parts)}")

    if not (MIN_EXPLANATION <= len(explanation) <= MAX_EXPLANATION):
        problems.append(f"{item_id}: the explanation is {len(explanation)} chars, "
                        f"wanted {MIN_EXPLANATION}-{MAX_EXPLANATION}")
    # An explanation that only restates the definition is not an explanation:
    # the point is the clue in the sentence that settles the choice.
    if explanation and not any(names(explanation, a) for a in answers):
        problems.append(f"{item_id}: the explanation never names the answer")

    if kind == "sentenceEquivalence":
        problems += check_equivalence(item_id, answers, words)
    return problems


def check_equivalence(item_id: str, answers: list[str], words: dict[str, dict]) -> list[str]:
    """The two answers have to be near enough to leave the sentence saying the
    same thing. Checked against the dataset's own synonym sets rather than by
    reading, which is what the sampled human review is for."""
    if len(answers) != 2:
        return []
    a, b = (words.get(x) for x in answers)
    if not a or not b or not a.get("gre") or not b.get("gre"):
        return [f"{item_id}: an answer is missing its GRE sense"]
    syn_a = {s.lower() for s in a["gre"].get("synonyms", [])}
    syn_b = {s.lower() for s in b["gre"].get("synonyms", [])}
    if (b["word"].lower() in syn_a or a["word"].lower() in syn_b
            or syn_a & syn_b):
        return []
    return [f"{item_id}: '{answers[0]}' and '{answers[1]}' share no synonym, "
            "so the pair probably does not preserve the meaning"]


def cmd_check(path: Path) -> None:
    """Same checks as merge, without writing anything. What a batch writer runs
    before handing the file over."""
    batch = json.loads(path.read_text())
    words = load_words()
    problems: list[str] = []
    for item_id, item in sorted(batch.items()):
        problems += check(item_id, item, words)
    for p in problems:
        print(p)
    if problems:
        sys.exit(f"\n{len(problems)} problem(s) across {len(batch)} questions")
    print(f"{len(batch)} questions, all clean")


def cmd_merge(path: Path) -> None:
    batch = json.loads(path.read_text())
    words = load_words()
    done = load_shards()
    SHARDS.mkdir(exist_ok=True)

    problems: list[str] = []
    for item_id, item in batch.items():
        if item_id in done:
            problems.append(f"{item_id}: already written")
        problems += check(item_id, item, words)
    if problems:
        for p in problems:
            print(p)
        sys.exit(f"\n{len(problems)} problem(s); nothing merged")

    start = len(done)
    by_shard: dict[int, dict] = {}
    for offset, (item_id, item) in enumerate(sorted(batch.items())):
        by_shard.setdefault((start + offset) // SHARD_SIZE, {})[item_id] = item

    for shard, entries in sorted(by_shard.items()):
        out = SHARDS / f"{shard:03d}.json"
        existing = json.loads(out.read_text()) if out.exists() else {}
        existing.update(entries)
        out.write_text(json.dumps(existing, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
        print(f"  {out.name}: {len(existing)} questions")


def cmd_verify() -> None:
    words = load_words()
    done = load_shards()
    problems: list[str] = []
    for item_id, item in sorted(done.items()):
        problems += check(item_id, item, words)
    for p in problems:
        print(p)
    if problems:
        sys.exit(f"\n{len(problems)} problem(s) across {len(done)} questions")
    kinds = {k: sum(1 for i in done.values() if i["kind"] == k) for k in KINDS}
    print(f"{len(done)} questions, all clean "
          f"({kinds['textCompletion']} completion, {kinds['sentenceEquivalence']} equivalence)")


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    command = sys.argv[1]
    if command == "targets":
        cmd_targets(int(sys.argv[2]) if len(sys.argv) > 2 else 50)
    elif command == "next":
        cmd_next(int(sys.argv[2]) if len(sys.argv) > 2 else 10)
    elif command == "check":
        cmd_check(Path(sys.argv[2]))
    elif command == "merge":
        cmd_merge(Path(sys.argv[2]))
    elif command == "verify":
        cmd_verify()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()

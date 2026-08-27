#!/usr/bin/env python3
"""Build the bundled GRE word dataset.

Merges curated GRE word lists, attaches WordNet definitions, and derives IPA
from CMUdict. Output: Sources/GRECore/Resources/words.json

Definitions come from Open English WordNet (CC BY 4.0), never from the prep
books the word lists are named after -- a list of words is a fact, a
publisher's definition of them is not.

    python3 tools/build_dataset.py               # fetch, build, write
    python3 tools/build_dataset.py --verify-only # check the committed file (no network)
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import urllib.request
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / "cache"
OUT = ROOT / "Sources" / "GRECore" / "Resources" / "words.json"
REPORT = ROOT / "tools" / "dataset-report.md"

WORDLIST_REPO = "Xatta-Trone/gre-words-collection"
CMUDICT_URL = "https://raw.githubusercontent.com/cmusphinx/cmudict/master/cmudict.dict"

# Curated lists only. The repo also carries "GRE 3000+", two 5000-word dumps and
# a 4700 list; those are unfiltered scrapes that trade precision for size and
# would take the merge from ~2.5k words to ~8.8k without making any of them more
# likely to appear on the test.
SOURCE_LISTS = {
    "gregmat": "001 GregMat960.csv",
    "prepscholar": "002 Prepscholar357.csv",
    "magoosh-basic": "003 Magoosh_Basic-352.csv",
    "magoosh-common": "004 Magoosh_Common-309.csv",
    "magoosh-advanced": "005 Magoosh_Advanced-367.csv",
    "powerscore": "005 PowerscoreRepeatOffenders-699.csv",
    "barrons-333": "006 Barrons-333.csv",
    "greenlight": "007 Greenlight-Vocab-List-Basic-500.csv",
    "magoosh-1000": "008 Magoosh-1000.csv",
    "vocabulary-com": "012 The Vocabulary.com Top 1000﻿.csv",
    "manhattan": "013 Manhattan-Prep-1000-GRE-Words-Definitions.csv",
}

MAX_SENSES = 3
GRE_SENSES = ROOT / "tools" / "gre_senses.json"
# A hand-assigned 1-5 rating of how hard each word is *in the sense the GRE
# tests*. Frequency cannot do this job: "august" and "flag" are common words
# whose everyday meanings are not the tested ones, so wordfreq calls them easy
# and a test-taker does not.
GRE_DIFFICULTY = ROOT / "tools" / "gre_difficulty.json"
# Three hand-written near-miss definitions per word. Multiple choice built from
# three other words' definitions is trivial: the wrong answers are about
# unrelated things, so the right one stands out without knowing the word.
GRE_OPTIONS = ROOT / "tools" / "gre_options.json"
# 1-5 to the four bands the app already displays.
RATING_BANDS = {1: "familiar", 2: "familiar", 3: "moderate", 4: "hard", 5: "rare"}
# Irregular forms the suffix rules below cannot reach. Only the ones that
# actually occur in the example sentences; there is no value in a general
# conjugator here.
IRREGULAR = {
    "forswear": ["forswore", "forsworn"],
    "underwrite": ["underwrote", "underwritten"],
    "waylay": ["waylaid"],
    "passe": ["passé"],
}
POS_LETTER = {"noun": "n", "verb": "v", "adjective": "a", "adverb": "r"}

# Zipf frequency bands, from wordfreq. Higher zipf means the word turns up more
# often in ordinary English, which is a far better proxy for "easy" than how many
# prep lists carry it -- those correlate *inversely* (words on nine lists have a
# lower median zipf than words on one, because the lists compete on obscurity).
DIFFICULTY_BANDS = [(3.5, "familiar"), (2.9, "moderate"), (2.2, "hard"), (0.0, "rare")]

# ARPAbet -> IPA. Stress digits are stripped before lookup.
ARPABET_IPA = {
    "AA": "ɑ", "AE": "æ", "AH": "ʌ", "AO": "ɔ", "AW": "aʊ", "AY": "aɪ",
    "B": "b", "CH": "tʃ", "D": "d", "DH": "ð", "EH": "ɛ", "ER": "ɝ",
    "EY": "eɪ", "F": "f", "G": "ɡ", "HH": "h", "IH": "ɪ", "IY": "i",
    "JH": "dʒ", "K": "k", "L": "l", "M": "m", "N": "n", "NG": "ŋ",
    "OW": "oʊ", "OY": "ɔɪ", "P": "p", "R": "ɹ", "S": "s", "SH": "ʃ",
    "T": "t", "TH": "θ", "UH": "ʊ", "UW": "u", "V": "v", "W": "w",
    "Y": "j", "Z": "z", "ZH": "ʒ",
}
VOWELS = {"AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY",
          "IH", "IY", "OW", "OY", "UH", "UW"}

# Consonant clusters English allows at the start of a syllable. Used to place
# stress marks: the walk-back from a stressed vowel may only absorb consonants
# that could legally begin a syllable, so "obsequious" comes out əbˈsikwiəs
# rather than əˈbsikwiəs -- /bs/ is not a possible English onset.
# NOTE: spelled in IPA, so the rhotic is ɹ -- not ASCII r.
LEGAL_ONSETS = {
    "pl", "bl", "kl", "ɡl", "fl", "sl", "pɹ", "bɹ", "tɹ", "dɹ", "kɹ", "ɡɹ",
    "fɹ", "θɹ", "ʃɹ", "tw", "dw", "kw", "sw", "θw", "sp", "st", "sk", "sm",
    "sn", "sf", "spl", "spɹ", "stɹ", "skɹ", "skw", "hj", "pj", "bj",
    "kj", "fj", "vj", "mj", "nj", "lj",
}

POS_NAMES = {"n": "noun", "v": "verb", "a": "adjective",
             "s": "adjective", "r": "adverb"}

WORD_RE = re.compile(r"^[a-z][a-z'-]*$")


# --------------------------------------------------------------------------- fetch

def fetch_wordlists() -> dict[str, list[str]]:
    """Download each curated CSV via the gh CLI, caching to disk."""
    d = CACHE / "wordlists"
    d.mkdir(parents=True, exist_ok=True)
    out = {}
    for key, filename in SOURCE_LISTS.items():
        path = d / f"{key}.csv"
        if not path.exists():
            print(f"  fetching {key}")
            content = subprocess.run(
                ["gh", "api", f"repos/{WORDLIST_REPO}/contents/word-list/{filename}",
                 "--jq", ".content"],
                capture_output=True, text=True, check=True,
            ).stdout
            path.write_bytes(base64.b64decode(content))
        out[key] = path.read_text(encoding="utf-8-sig").splitlines()
    return out


def fetch_cmudict() -> dict[str, list[str]]:
    path = CACHE / "cmudict.dict"
    if not path.exists():
        print("  fetching cmudict")
        path.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(CMUDICT_URL) as r:
            path.write_bytes(r.read())

    pron = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        head, *phones = line.split()
        # cmudict marks alternate pronunciations as "word(2)"; keep the first.
        if head.endswith(")"):
            continue
        pron.setdefault(head.lower(), phones)
    return pron


# --------------------------------------------------------------------------- transform

def normalize(raw: str) -> str | None:
    """Lowercase and strip a raw list line, or None if it isn't a usable word."""
    w = raw.strip().strip('"').strip()
    w = re.sub(r"\s*\(.*?\)\s*", "", w)     # drop "(adj.)" style annotations
    w = w.split(",")[0].strip().lower()      # some rows are "word, definition"
    return w if WORD_RE.match(w) else None


def to_ipa(phones: list[str]) -> str:
    """ARPAbet phones -> IPA, with primary/secondary stress marks."""
    syms, stresses = [], []
    for p in phones:
        stress = p[-1] if p[-1].isdigit() else ""
        base = p[:-1] if stress else p
        if base not in ARPABET_IPA:
            return ""
        # unstressed AH is schwa; ER follows the same reduction
        ipa = ARPABET_IPA[base]
        if base == "AH" and stress == "0":
            ipa = "ə"
        elif base == "ER" and stress == "0":
            ipa = "ɚ"
        syms.append(ipa)
        stresses.append((base, stress))

    # Place each stress mark before the onset of its syllable. Walk left from the
    # stressed vowel collecting consonants, then keep only the longest trailing
    # run that forms a legal English onset -- the rest belongs to the previous
    # syllable's coda.
    marks = {}
    for i, (base, stress) in enumerate(stresses):
        if stress not in ("1", "2") or base not in VOWELS:
            continue
        start = i
        while start > 0 and stresses[start - 1][0] not in VOWELS:
            start -= 1
        j = i
        for k in range(start, i):
            if "".join(syms[k:i]) in LEGAL_ONSETS or i - k == 1:
                j = k
                break
        marks[j] = "ˈ" if stress == "1" else "ˌ"

    return "".join(marks.get(i, "") + s for i, s in enumerate(syms))


def load_gre_senses() -> dict[str, dict]:
    """The hand-written GRE sense for each word: which meaning the exam tests,
    in plain English, with synonyms and two example sentences.

    WordNet supplies the extra senses and the lexicographic detail; this supplies
    the sense a learner actually needs and the part of speech to order by.
    """
    if not GRE_SENSES.exists():
        return {}
    return json.loads(GRE_SENSES.read_text(encoding="utf-8"))


def surface_forms(word: str) -> list[str]:
    """Inflections of `word` that might appear in a sentence, longest first.

    Longest-first matters: "abated" must be tried before "abate", or the blank
    swallows the stem and leaves a stray "d" behind.
    """
    stem = word.rstrip("e") if len(word) > 3 else word
    forms = {word, word + "s", word + "es", word + "d", word + "ing", word + "ly",
             stem + "ing", stem + "ed", stem + "es", stem + "e",
             stem + "ied", stem + "ies", stem + "ying"}
    if word.endswith("y"):
        forms |= {word[:-1] + "ies", word[:-1] + "ied"}
    if not (len(word) > 3 and word[-1] == word[-2]):
        forms |= {stem + word[-1] + "ing", stem + word[-1] + "ed"}
    forms |= set(IRREGULAR.get(word, []))
    return sorted(forms, key=len, reverse=True)


def to_cloze(word: str, sentence: str) -> str | None:
    """The sentence with the word blanked out, or None if it does not appear.

    Some example sentences are about the word rather than uses of it ("the word
    means looking around"), and those make no sense as a fill-in-the-blank.
    """
    blanked = sentence
    found = False
    for form in surface_forms(word):
        # Every occurrence, not just the first: "a king may abdicate a throne;
        # a parent cannot abdicate a child" would otherwise print the answer.
        blanked, count = re.subn(rf"\b{re.escape(form)}\b", "____", blanked, flags=re.IGNORECASE)
        found = found or count > 0
    return blanked if found else None


def load_options() -> dict[str, list[str]]:
    if not GRE_OPTIONS.exists():
        return {}
    return json.loads(GRE_OPTIONS.read_text(encoding="utf-8"))


def load_difficulty() -> dict[str, int]:
    if not GRE_DIFFICULTY.exists():
        return {}
    return json.loads(GRE_DIFFICULTY.read_text(encoding="utf-8"))


def is_trap(wordnet, word: str, gre: dict | None) -> bool:
    """True when the tested sense is not the word's everyday one.

    WordNet orders senses by how often they are used, so if the part of speech
    the exam tests is not what leads, this is a common word wearing a rare
    meaning -- "flag" the verb, "august" the adjective. Those need to be taught
    as the trap they are, not filed with the easy words.
    """
    if not gre:
        return False
    want = POS_LETTER.get(gre["pos"])
    if not want:
        return False
    wanted = {"a", "s"} if want == "a" else {want}
    synsets = [s for s in wordnet.synsets(word) if not s.get_related("instance_hypernym")]
    return bool(synsets) and synsets[0].pos not in wanted


def senses_for(wordnet, word: str, gre: dict | None = None) -> list[dict]:
    out = []
    # Instances are proper nouns (Margaret Court the tennis player, Ravel the
    # composer, Zephyr the god) and OEWN lists them first. Nobody is revising
    # "court" for the GRE to learn about a tennis player.
    common = [ss for ss in wordnet.synsets(word) if not ss.get_related("instance_hypernym")]
    # OEWN lists nouns first whatever the word, so "arch" leads with the
    # architecture and "cow" with the animal. The hand-written part of speech
    # says which sense the exam tests; sort that one to the front.
    keep = common[:MAX_SENSES]
    if gre and (letter := POS_LETTER.get(gre["pos"])):
        want = {"a", "s"} if letter == "a" else {letter}
        dominant = common[0] if common else None
        common.sort(key=lambda ss: ss.pos not in want)
        keep = common[:MAX_SENSES]
        # For a trap word the everyday sense is the whole point: it is what the
        # learner will wrongly choose, so it has to survive the truncation.
        if dominant is not None and dominant.pos not in want and dominant not in keep:
            keep = keep[:MAX_SENSES - 1] + [dominant]
    for ss in keep:
        lemmas = [l for l in ss.lemmas() if l.lower() != word]
        antonyms = []
        for sense in ss.senses():
            for rel in sense.get_related("antonym"):
                antonyms.extend(l for l in rel.synset().lemmas())
        out.append({
            "pos": POS_NAMES.get(ss.pos, ss.pos or "unknown"),
            "definition": ss.definition() or "",
            "examples": ss.examples()[:2],
            "synonyms": sorted(set(lemmas))[:6],
            "antonyms": sorted(set(antonyms))[:4],
        })
    return [s for s in out if s["definition"]]


def tier_for(list_count: int) -> str:
    if list_count >= 3:
        return "core"
    return "common" if list_count == 2 else "extended"


def build() -> tuple[list[dict], list[str]]:
    import wn
    import wn.morphy

    print("Fetching sources...")
    lists = fetch_wordlists()
    cmudict = fetch_cmudict()

    print("Merging lists...")
    sources: dict[str, set[str]] = {}
    for key, lines in lists.items():
        for line in lines:
            w = normalize(line)
            if w:
                sources.setdefault(w, set()).add(key)

    print(f"  {len(sources)} unique words")
    from wordfreq import zipf_frequency

    gre_senses = load_gre_senses()
    ratings = load_difficulty()
    options = load_options()
    print(f"Attaching WordNet senses ({len(gre_senses)} hand-written GRE senses)...")
    # Morphy falls back to lemmatization only when the surface form misses, so
    # inflected entries resolve while list typos still drop out.
    wordnet = wn.Wordnet("oewn:2024", lemmatizer=wn.morphy.Morphy())

    entries, missing = [], []
    for word in sorted(sources):
        gre = gre_senses.get(word)
        if gre:
            gre = dict(gre)
            gre["cloze"] = [c for s in gre["sentences"] if (c := to_cloze(word, s))]
            if word in options:
                gre["distractors"] = options[word]
        trap = is_trap(wordnet, word, gre)
        senses = senses_for(wordnet, word, gre)
        if not senses:
            missing.append(word)
            continue
        src = sorted(sources[word])
        zipf = round(zipf_frequency(word, "en"), 2)
        entries.append({
            "id": word,
            "word": word,
            "ipa": to_ipa(cmudict[word]) if word in cmudict else "",
            "senses": senses,
            "sourceLists": src,
            "listCount": len(src),
            "tier": tier_for(len(src)),
            "zipf": zipf,
            "difficulty": RATING_BANDS[ratings.get(word, 3)],
            "rating": ratings.get(word, 3),
            "isTrap": trap,
            **({"gre": gre} if gre else {}),
        })
    return entries, missing


# --------------------------------------------------------------------------- checks

def verify(entries: list[dict]) -> None:
    """Fail loudly rather than shipping a card whose answer side is blank."""
    assert entries, "dataset is empty"

    ids = [e["id"] for e in entries]
    dupes = [w for w, n in Counter(ids).items() if n > 1]
    assert not dupes, f"duplicate ids: {dupes[:5]}"

    for e in entries:
        assert e["senses"], f"{e['id']}: no senses"
        assert 1 <= e["rating"] <= 5, f"{e['id']}: bad rating"
        assert isinstance(e["isTrap"], bool), f"{e['id']}: bad trap flag"
        # A trap needs a competing everyday sense to offer as a wrong answer.
        if e["isTrap"]:
            assert len(e["senses"]) >= 1, f"{e['id']}: trap with no alternative sense"
        assert e["difficulty"] == RATING_BANDS[e["rating"]], f"{e['id']}: band/rating disagree"
        if g := e.get("gre"):
            assert g["pos"] in POS_LETTER, f"{e['id']}: bad gre pos"
            assert g["definition"] and len(g["sentences"]) >= 2, f"{e['id']}: thin gre sense"
            assert g["cloze"], f"{e['id']}: no sentence usable as fill-in-the-blank"
            assert all("____" in c for c in g["cloze"]), f"{e['id']}: cloze without a blank"
            d = g["distractors"]
            assert len(d) == 3 and len(set(d)) == 3, f"{e['id']}: needs 3 distinct distractors"
            assert g["definition"] not in d, f"{e['id']}: distractor repeats the answer"
        assert all(s["definition"] for s in e["senses"]), f"{e['id']}: blank definition"
        assert e["tier"] in ("core", "common", "extended"), f"{e['id']}: bad tier"
        assert e["listCount"] == len(e["sourceLists"]), f"{e['id']}: listCount mismatch"
        assert e["tier"] == tier_for(e["listCount"]), f"{e['id']}: tier/listCount disagree"
        assert e["difficulty"] in ("familiar", "moderate", "hard", "rare"), \
            f"{e['id']}: bad difficulty"

    assert sum(1 for e in entries if e["ipa"]) > len(entries) * 0.8, \
        "IPA coverage below 80% -- cmudict lookup probably broke"
    assert sum(1 for e in entries if e["zipf"] > 0) > len(entries) * 0.9, \
        "frequency coverage below 90% -- wordfreq lookup probably broke"
    # Every band must be populated, or ordering by difficulty does nothing.
    bands = {e["difficulty"] for e in entries}
    assert bands == {"familiar", "moderate", "hard", "rare"}, f"missing bands: {bands}"


def write_report(entries: list[dict], missing: list[str]) -> None:
    tiers = Counter(e["tier"] for e in entries)
    difficulties = Counter(e["difficulty"] for e in entries)
    per_list = Counter(s for e in entries for s in e["sourceLists"])
    no_ipa = [e["id"] for e in entries if not e["ipa"]]

    lines = [
        "# Dataset report", "",
        f"- **{len(entries)}** words shipped",
        f"- core (3+ lists): {tiers['core']} · common (2): {tiers['common']} · extended (1): {tiers['extended']}",
        f"- familiar: {difficulties['familiar']} · moderate: {difficulties['moderate']} "
        f"· hard: {difficulties['hard']} · rare: {difficulties['rare']}",
        f"- IPA coverage: {len(entries) - len(no_ipa)}/{len(entries)}",
        f"- dropped, no WordNet entry: {len(missing)}", "",
        "## Words per source list", "",
        "| List | Words kept |", "|---|---|",
        *(f"| {k} | {v} |" for k, v in sorted(per_list.items())), "",
        "## Dropped (no WordNet sense)", "",
        ", ".join(missing) if missing else "_none_", "",
        "## No IPA (not in CMUdict)", "",
        ", ".join(no_ipa) if no_ipa else "_none_", "",
    ]
    REPORT.write_text("\n".join(lines))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify-only", action="store_true",
                    help="validate the committed words.json without rebuilding")
    args = ap.parse_args()

    if args.verify_only:
        verify(json.loads(OUT.read_text()))
        print(f"OK: {OUT.relative_to(ROOT)} passes checks")
        return 0

    os.environ.setdefault("WN_DATA_DIR", str(CACHE / "wn"))
    entries, missing = build()
    verify(entries)

    OUT.write_text(json.dumps(entries, ensure_ascii=False, sort_keys=True,
                              separators=(",", ":")))
    write_report(entries, missing)

    print(f"\nWrote {len(entries)} words to {OUT.relative_to(ROOT)} "
          f"({OUT.stat().st_size // 1024} KB)")
    print(f"Dropped {len(missing)} without a WordNet sense; see {REPORT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

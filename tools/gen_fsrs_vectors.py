#!/usr/bin/env python3
"""Emit golden FSRS-6 vectors from py-fsrs for the Swift port to test against.

Run after bumping the pinned py-fsrs version:
    ./.venv/bin/python tools/gen_fsrs_vectors.py
"""
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fsrs import Card, Rating, Scheduler

OUT = Path(__file__).resolve().parent.parent / "Tests/GRECoreTests/Fixtures/fsrs_vectors.json"
START = datetime(2026, 1, 1, tzinfo=timezone.utc)

# Fuzzing randomises intervals by design; it must be off for reproducible vectors.
SCHEDULER = Scheduler(enable_fuzzing=False)

# Each case is a rating sequence paired with the gap (in minutes) before each review.
CASES = {
    "all_good":        [(Rating.Good, 0), (Rating.Good, 10), (Rating.Good, 1440), (Rating.Good, 5760)],
    "all_again":       [(Rating.Again, 0), (Rating.Again, 1), (Rating.Again, 1), (Rating.Again, 1)],
    "easy_graduates":  [(Rating.Easy, 0), (Rating.Easy, 20160), (Rating.Easy, 60480)],
    "hard_path":       [(Rating.Hard, 0), (Rating.Hard, 10), (Rating.Hard, 1440), (Rating.Hard, 2880)],
    "lapse_recovery":  [(Rating.Good, 0), (Rating.Good, 10), (Rating.Good, 1440),
                        (Rating.Again, 5760), (Rating.Good, 10), (Rating.Good, 1440)],
    "mixed":           [(Rating.Good, 0), (Rating.Hard, 10), (Rating.Easy, 1440),
                        (Rating.Again, 10080), (Rating.Good, 10), (Rating.Easy, 2880)],
    "long_gap":        [(Rating.Good, 0), (Rating.Good, 10), (Rating.Good, 1440), (Rating.Good, 525600)],
}


def run(sequence):
    card, now, steps = Card(), START, []
    for rating, gap in sequence:
        now = now + timedelta(minutes=gap)
        card, _ = SCHEDULER.review_card(card, rating, review_datetime=now)
        steps.append({
            "rating": int(rating),
            "reviewedAt": now.isoformat().replace("+00:00", "Z"),
            "stability": card.stability,
            "difficulty": card.difficulty,
            "due": card.due.isoformat().replace("+00:00", "Z"),
            "state": int(card.state),
            "step": card.step,
        })
    return steps


def main():
    payload = {
        "parameters": list(SCHEDULER.parameters),
        "desiredRetention": SCHEDULER.desired_retention,
        "learningStepsMinutes": [s.total_seconds() / 60 for s in SCHEDULER.learning_steps],
        "relearningStepsMinutes": [s.total_seconds() / 60 for s in SCHEDULER.relearning_steps],
        "maximumIntervalDays": SCHEDULER.maximum_interval,
        "startedAt": START.isoformat().replace("+00:00", "Z"),
        "cases": {name: run(seq) for name, seq in CASES.items()},
    }
    OUT.write_text(json.dumps(payload, indent=1))
    total = sum(len(v) for v in payload["cases"].values())
    print(f"Wrote {len(CASES)} cases / {total} steps to {OUT.name}")


if __name__ == "__main__":
    main()

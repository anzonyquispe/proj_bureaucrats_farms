#!/usr/bin/env python3
"""Flag the ACLED events that count as protest2 from the Gemini rounds.

Gemini (gemini-3.1-flash-lite, Batch Mode) classified each ACLED event in the
farm-law protest window ten times into farmer_led, solidarity,
against_farmers, not_farmer or insufficient_information. protest2 = 1 when the
farmer_led and solidarity votes add up to at least --min-votes (7 of 10), so an
event split between the two treated categories still counts. The output also
reports the single-category majority used in the original comparison
(``no_majority`` when no category reaches --min-votes).
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

import pandas as pd


TREATED_CATEGORIES = ("farmer_led", "solidarity")


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument("--rounds", type=Path, required=True,
                        help="gemini_rounds.csv: one row per event and round.")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--rounds-per-event", type=int, default=10)
    parser.add_argument("--min-votes", type=int, default=7)
    return parser.parse_args(argv)


def build_events(
    rounds: pd.DataFrame, rounds_per_event: int, min_votes: int
) -> pd.DataFrame:
    rounds_seen = rounds.groupby("event_id_cnty")["round"].nunique()
    incomplete = rounds_seen[rounds_seen != rounds_per_event]
    if len(incomplete):
        raise ValueError(
            f"{len(incomplete)} events do not have {rounds_per_event} rounds, "
            f"e.g. {incomplete.index[0]}"
        )

    votes = (
        rounds.dropna(subset=["category"])
        .groupby(["event_id_cnty", "category"])
        .size()
        .unstack(fill_value=0)
    )
    votes = votes.reindex(rounds_seen.index, fill_value=0)
    events = pd.DataFrame(index=votes.index)
    events["valid_votes"] = votes.sum(axis=1)
    events["treated_votes"] = votes.reindex(
        columns=list(TREATED_CATEGORIES), fill_value=0
    ).sum(axis=1)
    top = votes.idxmax(axis=1)
    events["gemini_category"] = top.where(votes.max(axis=1) >= min_votes, "no_majority")
    events["protest2"] = (events["treated_votes"] >= min_votes).astype(int)
    return events.reset_index()[
        ["event_id_cnty", "gemini_category", "treated_votes", "valid_votes", "protest2"]
    ]


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    rounds = pd.read_csv(args.rounds, usecols=["event_id_cnty", "round", "category"])
    events = build_events(rounds, args.rounds_per_event, args.min_votes)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    events.to_csv(args.output, index=False)
    print(f"{len(events):,} events | protest2 = 1: {int(events['protest2'].sum()):,}")
    print(events["gemini_category"].value_counts().to_string())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

from __future__ import annotations

import sys
import unittest
from pathlib import Path

import pandas as pd


DATA_GENERATION = Path(__file__).resolve().parents[1]
if str(DATA_GENERATION) not in sys.path:
    sys.path.insert(0, str(DATA_GENERATION))

from build_protest2_events import build_events  # noqa: E402


def rounds(votes: dict[str, list[str]]) -> pd.DataFrame:
    return pd.DataFrame(
        [
            {"event_id_cnty": event, "round": i + 1, "category": category}
            for event, categories in votes.items()
            for i, category in enumerate(categories)
        ]
    )


class Protest2EventTests(unittest.TestCase):
    def test_treated_votes_are_pooled(self) -> None:
        events = build_events(
            rounds(
                {
                    "farmer": ["farmer_led"] * 10,
                    "split": ["farmer_led"] * 5 + ["solidarity"] * 5,
                    "unsure": ["farmer_led"] * 6 + ["not_farmer"] * 4,
                    "support": ["solidarity"] * 7 + ["not_farmer"] * 3,
                    "against": ["against_farmers"] * 10,
                }
            ),
            rounds_per_event=10,
            min_votes=7,
        ).set_index("event_id_cnty")
        self.assertEqual(
            events.loc[:, ["gemini_category", "treated_votes", "protest2"]].to_dict("index"),
            {
                "against": {"gemini_category": "against_farmers", "treated_votes": 0, "protest2": 0},
                "farmer": {"gemini_category": "farmer_led", "treated_votes": 10, "protest2": 1},
                "split": {"gemini_category": "no_majority", "treated_votes": 10, "protest2": 1},
                "support": {"gemini_category": "solidarity", "treated_votes": 7, "protest2": 1},
                "unsure": {"gemini_category": "no_majority", "treated_votes": 6, "protest2": 0},
            },
        )

    def test_incomplete_rounds_fail(self) -> None:
        with self.assertRaisesRegex(ValueError, "do not have 10 rounds"):
            build_events(rounds({"short": ["farmer_led"] * 9}), 10, 7)


if __name__ == "__main__":
    unittest.main()

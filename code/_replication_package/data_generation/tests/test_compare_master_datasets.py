from __future__ import annotations

import io
import shutil
import sys
import unittest
import uuid
from contextlib import redirect_stdout
from pathlib import Path

import pandas as pd


DATA_GENERATION = Path(__file__).resolve().parents[1]
if str(DATA_GENERATION) not in sys.path:
    sys.path.insert(0, str(DATA_GENERATION))

import compare_master_datasets as compare  # noqa: E402


def master(protest: list[int], count: list[int]) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "unique_small_grid_id": [1, 1, 2, 2],
            "year": [2020, 2020, 2020, 2020],
            "month": [6, 7, 6, 7],
            "count": count,
            "protest5km": protest,
            "ac_area_tr": [1, 1, 2, 2],
        }
    )


class CompareMasterTests(unittest.TestCase):
    def run_compare(self, candidate: pd.DataFrame) -> tuple[int, str]:
        work = DATA_GENERATION / f".compare_master_test_{uuid.uuid4().hex}"
        work.mkdir()
        try:
            master([0, 1, 0, 0], [3, 4, 5, 6]).to_parquet(work / "ref.parquet")
            candidate.to_parquet(work / "cand.parquet")
            output = io.StringIO()
            with redirect_stdout(output):
                status = compare.main(
                    ["--reference", str(work / "ref.parquet"),
                     "--candidate", str(work / "cand.parquet"),
                     "--threads", "1", "--memory-limit", "1GB"]
                )
            return status, output.getvalue()
        finally:
            shutil.rmtree(work)

    def test_protest_only_differences_pass(self) -> None:
        status, report = self.run_compare(master([0, 0, 0, 1], [3, 4, 5, 6]))
        self.assertEqual(status, 0)
        self.assertIn("ONLY PROTEST COLUMNS DIFFER", report)
        self.assertIn("Grids whose protest5km history changes: 2", report)

    def test_added_columns_pass_but_missing_columns_fail(self) -> None:
        status, report = self.run_compare(
            master([0, 1, 0, 0], [3, 4, 5, 6]).assign(total_pop_ac=1.0)
        )
        self.assertEqual(status, 0)
        self.assertIn("Columns only in the candidate (not compared): total_pop_ac", report)
        status, report = self.run_compare(
            master([0, 1, 0, 0], [3, 4, 5, 6]).drop(columns="count")
        )
        self.assertEqual(status, 1)
        self.assertIn("Columns missing from the candidate: count", report)

    def test_other_differences_fail(self) -> None:
        status, report = self.run_compare(master([0, 1, 0, 0], [3, 4, 5, 9]))
        self.assertEqual(status, 1)
        self.assertIn("count (1 rows)", report)


if __name__ == "__main__":
    unittest.main()

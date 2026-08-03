from __future__ import annotations

import sys
import shutil
import unittest
import uuid
from pathlib import Path


DATA_GENERATION = Path(__file__).resolve().parents[1]
if str(DATA_GENERATION) not in sys.path:
    sys.path.insert(0, str(DATA_GENERATION))

import build_0_master_dataset as master  # noqa: E402


class MasterMergeDiagnosticsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.connection = master.duckdb.connect()
        self.connection.execute("CREATE TABLE left_panel(id INTEGER)")
        self.connection.execute("INSERT INTO left_panel VALUES (1), (2)")
        self.connection.execute("CREATE TABLE right_panel(id INTEGER)")
        self.connection.execute("INSERT INTO right_panel VALUES (2), (3)")

    def tearDown(self) -> None:
        self.connection.close()

    def test_reports_left_only_right_only_and_both(self) -> None:
        result = master.check_merge(
            self.connection,
            name="test merge",
            left_query="SELECT id FROM left_panel",
            right_query="SELECT id FROM right_panel",
            using_columns=("id",),
        )
        self.assertEqual(result, master.MergeDiagnostics(1, 1, 1))

    def test_strict_coverage_rejects_nonmatches(self) -> None:
        with self.assertRaisesRegex(
            ValueError,
            r"left_only=1, right_only=1",
        ):
            master.check_merge(
                self.connection,
                name="strict test merge",
                left_query="SELECT id FROM left_panel",
                right_query="SELECT id FROM right_panel",
                using_columns=("id",),
                require_all_left=True,
                require_all_right=True,
            )


class ElectionParquetTests(unittest.TestCase):
    def test_normalizes_parquet_and_keeps_yeargov(self) -> None:
        work = DATA_GENERATION / f".election_parquet_test_{uuid.uuid4().hex}"
        work.mkdir()
        try:
            path = work / "panel_data_election_year.parquet"
            master.pd.DataFrame(
                {
                    "ac_uq_id": [101],
                    "year": [2022],
                    "month": [1],
                    "yeargov": [1.0],
                    "unique_id": ["politician-1"],
                    "state": ["Punjab"],
                    "acpost08ID": [101.0],
                    "ASSEMBLY": [1.0],
                    "ASSEMBLY_1": ["Assembly"],
                    "DISTRICT": ["District"],
                    "PARLIAMENT": [1.0],
                    "P_NAME": ["Parliament"],
                    "STATE_UT": ["Punjab"],
                    "state_clean": ["Punjab"],
                    "STATE_UT_clean": ["Punjab"],
                }
            ).to_parquet(path, index=False)

            result = master.normalize_elections(path)

            self.assertEqual(len(result), 1)
            self.assertEqual(result.loc[0, "yeargov"], 1.0)
        finally:
            shutil.rmtree(work)


if __name__ == "__main__":
    unittest.main()

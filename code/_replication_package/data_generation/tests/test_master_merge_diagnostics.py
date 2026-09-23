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


class PopulationBaseTests(unittest.TestCase):
    def test_drops_entire_grid_when_any_wind_direction_is_missing(self) -> None:
        connection = master.duckdb.connect()
        try:
            connection.execute(
                """
                CREATE TABLE population_source(
                    unique_small_grid_id INTEGER,
                    year INTEGER,
                    month INTEGER,
                    wind_direction_av_cellid_month DOUBLE,
                    calculation_wind_direction DOUBLE
                )
                """
            )
            connection.execute(
                """
                INSERT INTO population_source VALUES
                    (1, 2020, 1, 10.0, 10.0),
                    (1, 2020, 2, 20.0, 20.0),
                    (2, 2020, 1, NULL, 30.0),
                    (2, 2020, 2, 40.0, 40.0),
                    (3, 2020, 1, 50.0, NULL),
                    (3, 2020, 2, 60.0, 60.0)
                """
            )

            result = master.create_population_base(
                connection,
                "population_source",
            )

            self.assertEqual(
                result,
                master.PopulationBaseDiagnostics(6, 2, 4, 2),
            )
            retained_grids = connection.execute(
                "SELECT DISTINCT unique_small_grid_id FROM population_base"
            ).fetchall()
            self.assertEqual(retained_grids, [(1,)])
        finally:
            connection.close()


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
                    "self_profession": [None],
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
            self.assertEqual(result.loc[0, "self_profession_nomiss"], 0)
        finally:
            shutil.rmtree(work)


class RiceParquetTests(unittest.TestCase):
    def test_normalizes_current_parquet_schema(self) -> None:
        work = DATA_GENERATION / f".rice_parquet_test_{uuid.uuid4().hex}"
        work.mkdir()
        try:
            path = work / "9_rice_info_ac_lvl.parquet"
            master.pd.DataFrame(
                {
                    "ac_uq_id": [101, 102],
                    "rice_area_aclvl_ahigh": [0, 1],
                    "rice_harvarea_aclvl_ahigh": [0, 1],
                    "rice_prod_aclvl_ahigh": [0, 1],
                    "rice_prod_mt": [10.0, 30.0],
                }
            ).to_parquet(path, index=False)

            result, production_median = master.normalize_rice(path)

            self.assertEqual(len(result), 2)
            self.assertEqual(result["ac_uq_id"].nunique(), 2)
            self.assertEqual(production_median, 20.0)
            self.assertEqual(
                list(result.columns),
                [
                    "ac_uq_id",
                    "rice_area_aclvl_ahigh",
                    "rice_harvarea_aclvl_ahigh",
                    "rice_prod_aclvl_ahigh",
                    "rice_prod_mt",
                ],
            )
        finally:
            shutil.rmtree(work)


if __name__ == "__main__":
    unittest.main()

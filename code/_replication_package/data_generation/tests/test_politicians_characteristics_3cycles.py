from __future__ import annotations

import shutil
import sys
import unittest
import uuid
from pathlib import Path


DATA_GENERATION = Path(__file__).resolve().parents[1]
if str(DATA_GENERATION) not in sys.path:
    sys.path.insert(0, str(DATA_GENERATION))

import build_politicians_characteristics_2cycles as twocycles  # noqa: E402
import build_politicians_characteristics_3cycles as threecycles  # noqa: E402
import build_politicians_characteristics_byprov as byprov  # noqa: E402
import duckdb  # noqa: E402

# The synthetic electoral history is shared with the two-cycle tests on purpose:
# the two builders must disagree on exactly one thing, the profession of the
# prior term, and a divergent fixture would hide that.
from test_politicians_characteristics_2cycles import (  # noqa: E402
    SECOND_TERM_START,
    SHARED_COHORT,
    UNITS,
    make_rows,
    read_csv,
    write_csv,
)


# Every unit survives here, including the two the two-cycle rule drops.
ALL_UNITS = set(UNITS)
TWO_CYCLE_UNITS = {"pb_treat_keep", "pb_ctrl_keep", "hr_treat_keep", "hr_ctrl_keep"}
# These two have an agricultural prior term, so the engine cut those months out
# of the source stack and this builder has to recover them from the master.
PRIOR_AGRICULTURAL_UNITS = {"pb_treat_drop", "pb_ctrl_drop"}
CONTROL_TERM_START = 2017 * 12 + 4


class ThreeElectoralTermsTests(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.work = DATA_GENERATION / f".threecycles_test_{uuid.uuid4().hex}"
        cls.work.mkdir()
        try:
            cls.master = cls.work / "0_master_dataset.csv"
            write_csv(cls.master, make_rows())
            source_status = byprov.main(
                [
                    "--intermediate", str(cls.work),
                    "--input", str(cls.master),
                    "--threads", "1",
                    "--memory-limit", "1GB",
                    "--last-cohort-year", "2022",
                    "--last-cohort-month", "12",
                    "--expected-cohorts", "3",
                    "--overwrite",
                ]
            )
            assert source_status == 0
            cls.source_rows = read_csv(cls.work / byprov.OUTPUT_NAME)
            assert (
                threecycles.main(
                    [
                        "--intermediate", str(cls.work),
                        "--input", str(cls.master),
                        "--source", "byprov",
                        "--threads", "1",
                        "--memory-limit", "1GB",
                        "--expected-cohorts", "2",
                        "--allow-stale-source",
                        "--overwrite",
                    ]
                )
                == 0
            )
            # The two-cycle stack is built alongside so the two can be compared.
            assert (
                twocycles.main(
                    [
                        "--intermediate", str(cls.work),
                        "--input", str(cls.master),
                        "--source", "byprov",
                        "--threads", "1",
                        "--memory-limit", "1GB",
                        "--expected-cohorts", "2",
                        "--allow-stale-source",
                        "--overwrite",
                    ]
                )
                == 0
            )
        except Exception:
            shutil.rmtree(cls.work, ignore_errors=True)
            raise
        cls.source = threecycles.SOURCES["byprov"]
        cls.rows = read_csv(cls.work / cls.source.output_csv)
        cls.manifest = read_csv(cls.work / cls.source.manifest)
        cls.two_cycle_rows = read_csv(
            cls.work / twocycles.SOURCES["byprov"].output_csv
        )

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.work, ignore_errors=True)

    def rows_for(self, grid_id: str) -> list[dict[str, str]]:
        return [row for row in self.rows if row["unique_small_grid_id"] == grid_id]

    def test_shared_cluster_pipelines_include_three_cycle_stack(self) -> None:
        expected_command = "build_politicians_characteristics_3cycles.py"
        for filename in (
            "build_stacked_datasets.sbatch",
            "build_master_and_stacked_datasets.sh",
        ):
            contents = (DATA_GENERATION / filename).read_text(encoding="utf-8")
            self.assertIn(expected_command, contents, filename)

    def test_source_columns_are_preserved_in_order(self) -> None:
        source_columns = list(self.source_rows[0])
        self.assertEqual(list(self.rows[0])[: len(source_columns)], source_columns)
        self.assertEqual(
            list(self.rows[0])[len(source_columns) :],
            list(threecycles.DIAGNOSTIC_COLUMNS),
        )

    def test_units_with_an_agricultural_prior_term_are_retained(self) -> None:
        self.assertEqual(
            {row["unique_small_grid_id"] for row in self.rows}, ALL_UNITS
        )
        # The contrast that defines this builder.
        self.assertEqual(
            {row["unique_small_grid_id"] for row in self.two_cycle_rows},
            TWO_CYCLE_UNITS,
        )
        self.assertEqual({int(row["treat"]) for row in self.rows}, {0, 1})

    def test_prior_term_agricultural_flag_matches_the_fixture(self) -> None:
        for grid_id in ALL_UNITS:
            flags = {int(row["prev_term_agricultural"]) for row in self.rows_for(grid_id)}
            expected = 1 if grid_id in PRIOR_AGRICULTURAL_UNITS else 0
            self.assertEqual(flags, {expected}, grid_id)

    def test_prior_term_months_are_recovered_from_the_master(self) -> None:
        for grid_id in PRIOR_AGRICULTURAL_UNITS:
            months = [int(row["monthyear"]) for row in self.rows_for(grid_id)]
            source_months = [
                int(row["monthyear"])
                for row in self.source_rows
                if row["unique_small_grid_id"] == grid_id
                and int(row["cohort"]) == SHARED_COHORT
            ]
            # The engine had cut the whole agricultural prior term away.
            self.assertEqual(min(source_months), CONTROL_TERM_START, grid_id)
            self.assertEqual(min(months), SECOND_TERM_START, grid_id)

            recovered = {
                int(row["monthyear"])
                for row in self.rows_for(grid_id)
                if row["row_source"] == "master_backfill"
            }
            self.assertEqual(
                recovered,
                set(range(SECOND_TERM_START, CONTROL_TERM_START)),
                grid_id,
            )

    def test_units_without_an_agricultural_prior_term_are_only_trimmed(self) -> None:
        for grid_id in ALL_UNITS - PRIOR_AGRICULTURAL_UNITS:
            sources = {row["row_source"] for row in self.rows_for(grid_id)}
            self.assertEqual(sources, {"stack"}, grid_id)
            months = [int(row["monthyear"]) for row in self.rows_for(grid_id)]
            self.assertEqual(min(months), SECOND_TERM_START, grid_id)

    def test_recovered_rows_are_pre_treatment_and_arithmetically_sound(self) -> None:
        recovered = [row for row in self.rows if row["row_source"] == "master_backfill"]
        self.assertTrue(recovered)
        for row in recovered:
            self.assertEqual(int(row["post"]), 0)
            self.assertLess(int(row["relative_monthyear"]), 0)
        for row in self.rows:
            self.assertEqual(
                int(row["relative_monthyear"]),
                int(row["monthyear"]) - int(row["cohort"]),
            )

    def test_every_unit_reaches_the_prior_term(self) -> None:
        for grid_id in ALL_UNITS:
            terms = {int(row["relative_term"]) for row in self.rows_for(grid_id)}
            self.assertEqual(min(terms), -2, grid_id)
            self.assertIn(0, terms, grid_id)

    def test_cohort_without_a_prior_term_disappears(self) -> None:
        self.assertEqual({int(row["cohort"]) for row in self.rows}, {SHARED_COHORT})
        self.assertGreater(len({int(row["cohort"]) for row in self.source_rows}), 1)

    def test_provinces_sharing_a_switch_month_stay_separate(self) -> None:
        self.assertEqual(len({int(row["cohort_id"]) for row in self.rows}), 2)
        self.assertEqual(
            {row["province"] for row in self.rows}, {"Punjab", "Haryana"}
        )

    def test_post_period_is_untouched(self) -> None:
        for grid_id in ALL_UNITS:
            extended = [
                row
                for row in self.rows_for(grid_id)
                if int(row["relative_monthyear"]) >= 0
            ]
            original = [
                row
                for row in self.source_rows
                if row["unique_small_grid_id"] == grid_id
                and int(row["cohort"]) == SHARED_COHORT
                and int(row["relative_monthyear"]) >= 0
            ]
            self.assertEqual(len(extended), len(original), grid_id)

    def test_manifest_accounts_for_the_recovered_rows(self) -> None:
        self.assertEqual(len(self.manifest), 2)
        self.assertEqual(
            sum(int(entry["rows_kept"]) for entry in self.manifest), len(self.rows)
        )
        self.assertEqual(
            sum(int(entry["rows_added"]) for entry in self.manifest),
            len([row for row in self.rows if row["row_source"] == "master_backfill"]),
        )
        self.assertGreater(
            sum(int(entry["grids_with_prior_agricultural"]) for entry in self.manifest),
            0,
        )
        for entry in self.manifest:
            # rows_dropped counts source rows trimmed away, net of what was added.
            self.assertEqual(
                int(entry["source_rows"])
                - (int(entry["rows_kept"]) - int(entry["rows_added"])),
                int(entry["rows_dropped"]),
                entry,
            )
            self.assertEqual(int(entry["relative_term_min"]), -2, entry)

    def test_extended_stack_is_larger_than_the_two_cycle_stack(self) -> None:
        self.assertGreater(len(self.rows), len(self.two_cycle_rows))

    def test_shared_units_match_the_two_cycle_stack_from_the_control_term_on(
        self,
    ) -> None:
        def keyed(rows: list[dict[str, str]]) -> set[tuple[str, int, int]]:
            return {
                (row["unique_small_grid_id"], int(row["monthyear"]), int(row["cohort"]))
                for row in rows
                if row["unique_small_grid_id"] in TWO_CYCLE_UNITS
                and int(row["relative_term"]) >= -1
            }

        self.assertEqual(keyed(self.rows), keyed(self.two_cycle_rows))

    def test_database_carries_table_view_and_attrition(self) -> None:
        connection = duckdb.connect(
            str(self.work / self.source.database), read_only=True
        )
        try:
            table_rows = connection.execute(
                f'SELECT count(*) FROM "{self.source.table}"'
            ).fetchone()[0]
            view_rows = connection.execute(
                "SELECT count(*) FROM final_stack"
            ).fetchone()[0]
            statuses = {
                row[0]
                for row in connection.execute(
                    f'SELECT DISTINCT status FROM "{self.source.table}_attrition"'
                ).fetchall()
            }
        finally:
            connection.close()
        self.assertEqual(table_rows, len(self.rows))
        self.assertEqual(view_rows, len(self.rows))
        self.assertIn("kept", statuses)
        self.assertIn("prior_term_unobserved", statuses)
        # The status the two-cycle builder uses to drop units no longer exists.
        self.assertNotIn("prior_term_agricultural", statuses)


if __name__ == "__main__":
    unittest.main()

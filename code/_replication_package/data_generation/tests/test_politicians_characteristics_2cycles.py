from __future__ import annotations

import csv
import shutil
import sys
import unittest
import uuid
from pathlib import Path


DATA_GENERATION = Path(__file__).resolve().parents[1]
if str(DATA_GENERATION) not in sys.path:
    sys.path.insert(0, str(DATA_GENERATION))

import build_all_stacked_datasets_duckdb as stacks  # noqa: E402
import build_politicians_characteristics_2cycles as twocycles  # noqa: E402
import build_politicians_characteristics_byprov as byprov  # noqa: E402
import duckdb  # noqa: E402


# One province with four electoral terms. The 2007 term is only partially
# observed, so the 2012-04 cohort has no second prior term and must vanish.
TERMS = (
    (2007, 4, 2007),
    (2012, 4, 2012),
    (2017, 4, 2017),
    (2022, 4, 2022),
)
PANEL_START = 2010 * 12 + 1
PANEL_END = 2023 * 12 + 3
SECOND_TERM_START = 2012 * 12 + 4

# province and profession by term: (2007, 2012, 2017, 2022).
# Punjab and Haryana share the 2022-04 switch month, so their cohorts differ
# only by cohort_id: that is what separates a per-province cohort key from a
# bare cohort month.
UNITS = {
    "pb_treat_keep": ("Punjab", (0, 0, 0, 1)),
    "pb_treat_drop": ("Punjab", (0, 1, 0, 1)),
    "pb_ctrl_keep": ("Punjab", (0, 0, 0, 0)),
    "pb_ctrl_drop": ("Punjab", (0, 1, 0, 0)),
    "hr_treat_keep": ("Haryana", (0, 0, 0, 1)),
    "hr_ctrl_keep": ("Haryana", (0, 0, 0, 0)),
}
KEPT_UNITS = {"pb_treat_keep", "pb_ctrl_keep", "hr_treat_keep", "hr_ctrl_keep"}
SHARED_COHORT = 2022 * 12 + 4


def term_for(monthyear: int) -> int:
    index = 0
    for position, (year, month, _) in enumerate(TERMS):
        if monthyear >= year * 12 + month:
            index = position
    return index


def make_rows() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for grid_index, (grid_id, (province, professions)) in enumerate(
        UNITS.items(), start=1
    ):
        for monthyear in range(PANEL_START, PANEL_END + 1):
            term_index = term_for(monthyear)
            year_take, month_take, election_year = TERMS[term_index]
            term_start = year_take * 12 + month_take
            year, month = divmod(monthyear - 1, 12)
            rows.append(
                {
                    "unique_small_grid_id": grid_id,
                    "province": province,
                    "distr_id": 11 if province == "Punjab" else 22,
                    "ac_uq_id": 100 + grid_index,
                    "count": 1,
                    "mean_brightness": 300.0,
                    "month": month + 1,
                    "year": year,
                    "monthyear": monthyear,
                    "downup_ac": 0,
                    "downup_ac_pop": 0,
                    "av_wind_speed": 2.5,
                    "wind_direction": 90.0,
                    "rice_prod_aclvl_ahigh": 1,
                    "election_year": election_year,
                    "year_take": year_take,
                    "month_take": month_take,
                    "ym_take": term_start,
                    "yeargov": (monthyear - term_start) // 12 + 1,
                    "self_profession": professions[term_index],
                    "self_profession_nomiss": professions[term_index],
                }
            )
    return rows


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


class TwoElectoralCyclesTests(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.work = DATA_GENERATION / f".twocycles_test_{uuid.uuid4().hex}"
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
            status = twocycles.main(
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
            assert status == 0
        except Exception:
            shutil.rmtree(cls.work, ignore_errors=True)
            raise
        cls.source = twocycles.SOURCES["byprov"]
        cls.rows = read_csv(cls.work / cls.source.output_csv)
        cls.manifest = read_csv(cls.work / cls.source.manifest)

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.work, ignore_errors=True)

    def test_shared_cluster_pipelines_include_two_cycle_stack(self) -> None:
        expected_command = "build_politicians_characteristics_2cycles.py"
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
            list(twocycles.DIAGNOSTIC_COLUMNS),
        )

    def test_only_units_with_two_clean_terms_survive(self) -> None:
        self.assertEqual(
            {row["unique_small_grid_id"] for row in self.rows}, KEPT_UNITS
        )
        self.assertEqual({int(row["treat"]) for row in self.rows}, {0, 1})

    def test_cohort_without_second_prior_term_disappears(self) -> None:
        # The 2012-04 cohort has no observable term before its control term.
        self.assertEqual({int(row["cohort"]) for row in self.rows}, {SHARED_COHORT})
        self.assertGreater(len({int(row["cohort"]) for row in self.source_rows}), 1)

    def test_provinces_sharing_a_switch_month_stay_separate(self) -> None:
        # Punjab and Haryana share cohort 2022-04, so counting distinct cohort
        # months would merge them into one surviving cohort.
        self.assertEqual(len({int(row["cohort_id"]) for row in self.rows}), 2)
        self.assertEqual(
            {row["province"] for row in self.rows}, {"Punjab", "Haryana"}
        )

    def test_manifest_counts_each_province_cohort_separately(self) -> None:
        for entry in self.manifest:
            cohort_id = int(entry["cohort_id"])
            source_rows = len(
                [
                    row
                    for row in self.source_rows
                    if int(row["cohort_id"]) == cohort_id
                ]
            )
            kept_rows = len(
                [row for row in self.rows if int(row["cohort_id"]) == cohort_id]
            )
            self.assertEqual(int(entry["source_rows"]), source_rows, entry)
            self.assertEqual(int(entry["rows_kept"]), kept_rows, entry)

    def test_pre_period_starts_at_the_second_prior_term(self) -> None:
        for grid_id in KEPT_UNITS:
            months = [
                int(row["monthyear"])
                for row in self.rows
                if row["unique_small_grid_id"] == grid_id
            ]
            source_months = [
                int(row["monthyear"])
                for row in self.source_rows
                if row["unique_small_grid_id"] == grid_id
                and int(row["cohort"]) == 2022 * 12 + 4
            ]
            self.assertEqual(min(months), SECOND_TERM_START, grid_id)
            self.assertLess(min(source_months), SECOND_TERM_START, grid_id)

    def test_relative_term_reaches_minus_two(self) -> None:
        for grid_id in KEPT_UNITS:
            terms = {
                int(row["relative_term"])
                for row in self.rows
                if row["unique_small_grid_id"] == grid_id
            }
            self.assertEqual(min(terms), -2, grid_id)
            self.assertIn(0, terms, grid_id)

    def test_post_period_is_untouched(self) -> None:
        for grid_id in KEPT_UNITS:
            restricted = [
                row
                for row in self.rows
                if row["unique_small_grid_id"] == grid_id
                and int(row["relative_monthyear"]) >= 0
            ]
            original = [
                row
                for row in self.source_rows
                if row["unique_small_grid_id"] == grid_id
                and int(row["cohort"]) == 2022 * 12 + 4
                and int(row["relative_monthyear"]) >= 0
            ]
            self.assertEqual(len(restricted), len(original), grid_id)

    def test_manifest_accounts_for_every_source_row(self) -> None:
        self.assertEqual(len(self.manifest), 2)
        self.assertEqual(
            sum(int(entry["rows_kept"]) for entry in self.manifest), len(self.rows)
        )
        for entry in self.manifest:
            self.assertEqual(
                int(entry["source_rows"]) - int(entry["rows_kept"]),
                int(entry["rows_dropped"]),
                entry,
            )
        self.assertGreater(
            sum(
                int(entry["grids_dropped_prior_agricultural"])
                for entry in self.manifest
            ),
            0,
        )

    def test_pooled_stack_without_cohort_id_is_supported(self) -> None:
        # The pooled stack has neither cohort_id nor cohort_province, so the
        # manifest groups on cohort alone.
        self.assertEqual(
            stacks.main(
                [
                    "--intermediate", str(self.work),
                    "--input", str(self.master),
                    "--spec", "self_profession_nomiss",
                    "--threads", "1",
                    "--memory-limit", "1GB",
                    "--overwrite",
                ]
            ),
            0,
        )
        pooled = twocycles.SOURCES["pooled"]
        self.assertEqual(
            twocycles.main(
                [
                    "--intermediate", str(self.work),
                    "--input", str(self.master),
                    "--source", "pooled",
                    "--threads", "1",
                    "--memory-limit", "1GB",
                    "--expected-cohorts", "1",
                    "--allow-stale-source",
                    "--overwrite",
                ]
            ),
            0,
        )
        rows = read_csv(self.work / pooled.output_csv)
        self.assertEqual(
            {row["unique_small_grid_id"] for row in rows}, KEPT_UNITS
        )
        self.assertEqual(min(int(row["relative_term"]) for row in rows), -2)
        manifest = read_csv(self.work / pooled.manifest)
        self.assertEqual(len(manifest), 1)
        self.assertNotIn("cohort_id", manifest[0])

    def test_database_carries_table_view_and_attrition(self) -> None:
        connection = duckdb.connect(str(self.work / self.source.database), read_only=True)
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
        self.assertIn("prior_term_agricultural", statuses)
        self.assertIn("prior_term_unobserved", statuses)


if __name__ == "__main__":
    unittest.main()

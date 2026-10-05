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

import build_polischar_t2_baseline as baseline  # noqa: E402
import build_politicians_characteristics_byprov as byprov  # noqa: E402

from test_politicians_characteristics_2cycles import (  # noqa: E402
    UNITS,
    make_rows,
    read_csv,
    write_csv,
)


# The synthetic MODIS grid spans well beyond the master so that even the oldest
# cohort's baseline window is covered.
MODIS_FIRST = 24000
MODIS_LAST = 24300

# Each emitted grid-month carries count == calendar month, so a baseline cell
# whose five months are all present must equal the calendar month exactly.
#
# Two grids are mutilated on purpose, to pin down the zero-filling:
#   pb_ctrl_keep  loses every October, so its October baseline must be 0.
#   hr_ctrl_keep  loses two of the five Octobers in the 2012-2017 window, so
#                 its October baseline must be 3 * 10 / 5 = 6.
NO_OCTOBER_GRID = "pb_ctrl_keep"
PARTIAL_OCTOBER_GRID = "hr_ctrl_keep"
PARTIAL_DROPPED_YEARS = (2013, 2015)


def modis_rows() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for grid_id in UNITS:
        for monthyear in range(MODIS_FIRST, MODIS_LAST + 1):
            year, month = divmod(monthyear - 1, 12)
            month += 1
            if month == 10 and grid_id == NO_OCTOBER_GRID:
                continue
            if (
                month == 10
                and grid_id == PARTIAL_OCTOBER_GRID
                and year in PARTIAL_DROPPED_YEARS
            ):
                continue
            rows.append(
                {
                    "unique_small_grid_id": grid_id,
                    "year": year,
                    "month": month,
                    "count": month,
                    "mean_brightness": 300.0,
                }
            )
    return rows


class T2BaselineTests(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.work = DATA_GENERATION / f".t2baseline_test_{uuid.uuid4().hex}"
        cls.work.mkdir()
        try:
            cls.master = cls.work / "0_master_dataset.csv"
            write_csv(cls.master, make_rows())
            cls.modis = cls.work / "_3_fire_grid_MODIS_only.csv"
            write_csv(cls.modis, modis_rows())

            assert (
                byprov.main(
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
                == 0
            )
            cls.source_rows = read_csv(cls.work / byprov.OUTPUT_NAME)

            assert (
                baseline.main(
                    [
                        "--intermediate", str(cls.work),
                        "--input", str(cls.master),
                        "--modis-grid", str(cls.modis),
                        "--threads", "1",
                        "--memory-limit", "1GB",
                        "--allow-stale-source",
                        "--overwrite",
                    ]
                )
                == 0
            )
        except Exception:
            shutil.rmtree(cls.work, ignore_errors=True)
            raise
        cls.rows = read_csv(cls.work / f"{baseline.OUTPUT_STEM}.csv")

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.work, ignore_errors=True)

    def cells(self, grid_id: str) -> list[dict[str, str]]:
        return [row for row in self.rows if row["unique_small_grid_id"] == grid_id]

    def test_every_source_unit_cohort_has_a_baseline(self) -> None:
        source_keys = {
            (row["unique_small_grid_id"], row["cohort_id"]) for row in self.source_rows
        }
        baseline_keys = {
            (row["unique_small_grid_id"], row["cohort_id"]) for row in self.rows
        }
        self.assertEqual(baseline_keys, source_keys)

    def test_units_the_two_cycle_rule_drops_are_kept(self) -> None:
        # pb_treat_drop and pb_ctrl_drop have an agricultural prior term, which
        # is exactly what the two-cycle stack discards. Not restricting the
        # sample is the whole purpose of this table.
        kept = {row["unique_small_grid_id"] for row in self.rows}
        self.assertIn("pb_treat_drop", kept)
        self.assertIn("pb_ctrl_drop", kept)

    def test_twelve_calendar_months_per_unit_cohort(self) -> None:
        seen: dict[tuple[str, str], set[int]] = {}
        for row in self.rows:
            key = (row["unique_small_grid_id"], row["cohort_id"])
            seen.setdefault(key, set()).add(int(row["month"]))
        for key, months in seen.items():
            self.assertEqual(months, set(range(1, 13)), key)

    def test_window_is_sixty_months_before_the_control_term(self) -> None:
        for row in self.rows:
            start = int(row["t2_window_start"])
            end = int(row["t2_window_end"])
            # Five occurrences of one calendar month, 12 months apart.
            self.assertEqual(end - start, 48, row)

    def test_fully_observed_cells_equal_the_calendar_month(self) -> None:
        intact = set(UNITS) - {NO_OCTOBER_GRID, PARTIAL_OCTOBER_GRID}
        for grid_id in intact:
            for row in self.cells(grid_id):
                self.assertAlmostEqual(
                    float(row["t2_count_modis"]), float(row["month"]), places=9
                )

    def test_months_without_detections_are_zero_filled(self) -> None:
        october = [row for row in self.cells(NO_OCTOBER_GRID) if int(row["month"]) == 10]
        self.assertTrue(october)
        for row in october:
            self.assertEqual(float(row["t2_count_modis"]), 0.0)
        # The other months of the same grid are untouched.
        for row in self.cells(NO_OCTOBER_GRID):
            if int(row["month"]) != 10:
                self.assertAlmostEqual(
                    float(row["t2_count_modis"]), float(row["month"]), places=9
                )

    def test_partially_observed_cells_average_over_the_full_window(self) -> None:
        # Three of five Octobers survive, each worth 10, so the mean is 6 and
        # not 10: the missing months enter the denominator.
        for row in self.cells(PARTIAL_OCTOBER_GRID):
            if int(row["month"]) != 10:
                continue
            window_years = range(
                (int(row["t2_window_start"]) - 1) // 12,
                (int(row["t2_window_end"]) - 1) // 12 + 1,
            )
            dropped = sum(1 for year in window_years if year in PARTIAL_DROPPED_YEARS)
            expected = 10.0 * (5 - dropped) / 5.0
            self.assertAlmostEqual(float(row["t2_count_modis"]), expected, places=9)

    def test_stata_file_is_written(self) -> None:
        path = self.work / f"{baseline.OUTPUT_STEM}.dta"
        self.assertTrue(path.is_file())
        self.assertGreater(path.stat().st_size, 0)

    def test_modis_estimation_panel_covers_the_stack_window(self) -> None:
        self.assertTrue((self.work / f"{baseline.PANEL_STEM}.dta").is_file())
        panel = read_csv(self.work / f"{baseline.PANEL_STEM}.csv")
        self.assertTrue(panel)

        # The fixture emits count == calendar month, so the panel must carry it
        # through unchanged for the grids that were not mutilated.
        for row in panel:
            if row["unique_small_grid_id"] in {NO_OCTOBER_GRID, PARTIAL_OCTOBER_GRID}:
                continue
            self.assertEqual(int(row["count_modis"]), int(row["month"]), row)

        # It is bounded by the stack's own window, not by the whole MODIS file.
        stack_months = {
            int(row["year"]) * 12 + int(row["month"]) for row in self.source_rows
        }
        panel_months = {
            int(row["year"]) * 12 + int(row["month"]) for row in panel
        }
        self.assertLessEqual(min(panel_months), max(stack_months))
        self.assertGreaterEqual(min(panel_months), min(stack_months))
        self.assertLessEqual(max(panel_months), max(stack_months))

        # And only grids the stack actually contains.
        self.assertEqual(
            {row["unique_small_grid_id"] for row in panel} - set(UNITS), set()
        )


if __name__ == "__main__":
    unittest.main()

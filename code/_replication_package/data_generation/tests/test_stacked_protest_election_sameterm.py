from __future__ import annotations

import csv
import gc
import shutil
import sys
import unittest
import uuid
from contextlib import contextmanager
from pathlib import Path

import duckdb


DATA_GENERATION = Path(__file__).resolve().parents[1]
if str(DATA_GENERATION) not in sys.path:
    sys.path.insert(0, str(DATA_GENERATION))

import _stacked_duckdb_core as core  # noqa: E402
import build_stacked_protest_election_sameterm as builder  # noqa: E402
import compare_protest_sameterm_stacks as comparison  # noqa: E402


def ym(year: int, month: int) -> int:
    return year * 12 + month


START, END = ym(2019, 6), ym(2022, 12)

# grid -> (province, first treated month or None)
GRIDS = {
    1: ("Punjab", ym(2020, 6)),
    2: ("Punjab", ym(2021, 1)),
    3: ("Punjab", None),
    4: ("Uttar Pradesh", None),
    5: ("Punjab", ym(2022, 5)),
    6: ("Haryana", ym(2020, 6)),
    7: ("Haryana", None),
}


def election_year(province: str, monthyear: int) -> int:
    if province == "Haryana":
        return 2019 if monthyear >= ym(2019, 11) else 2014
    return 2022 if monthyear >= ym(2022, 4) else 2017


def panel_rows() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for grid, (province, switch) in GRIDS.items():
        for monthyear in range(START, END + 1):
            year, month = divmod(monthyear - 1, 12)
            rows.append(
                {
                    "unique_small_grid_id": grid,
                    "province": province,
                    "distr_id": 1,
                    "ac_uq_id": grid,
                    "count": monthyear % 7,
                    "mean_brightness": 300.0,
                    "month": month + 1,
                    "year": year,
                    "monthyear": monthyear,
                    "downup_ac": 0,
                    "downup_ac_pop": 0,
                    "av_wind_speed": 2.5,
                    "wind_direction": 90.0,
                    "rice_prod_aclvl_ahigh": 1,
                    "election_year": election_year(province, monthyear),
                    "yeargov": 1,
                    "protest5km": int(switch is not None and monthyear >= switch),
                }
            )
    return rows


@contextmanager
def temporary_workspace():
    work = DATA_GENERATION / f".protest_sameterm_test_{uuid.uuid4().hex}"
    work.mkdir()
    try:
        yield work
    finally:
        # Release closed DuckDB instances first; they recreate their temp
        # directory when destroyed after the workspace is gone.
        gc.collect()
        shutil.rmtree(work)


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def build(work: Path, source: Path) -> duckdb.DuckDBPyConnection:
    result = builder.main(
        [
            "--intermediate", str(work),
            "--input", str(source),
            "--output-stem", "stack",
            "--no-csv",
            "--threads", "1",
            "--memory-limit", "1GB",
            "--log-level", "WARNING",
        ]
    )
    if result != 0:
        raise AssertionError(f"builder returned {result}")
    con = duckdb.connect()
    con.execute(f"CREATE TABLE s AS SELECT * FROM read_parquet('{work / 'stack.parquet'}')")
    return con


class ProtestElectionSametermTests(unittest.TestCase):
    def test_cohorts_terms_and_controls(self) -> None:
        with temporary_workspace() as work:
            source = work / "panel.csv"
            write_csv(source, panel_rows())
            con = build(work, source)

            cohorts = con.execute(
                """
                SELECT DISTINCT cohort_id, cohort, cohort_election_year,
                       cohort_term_start, cohort_analysis_max
                FROM s ORDER BY cohort_id
                """
            ).fetchall()
            self.assertEqual(
                cohorts,
                [
                    (1, ym(2020, 6), 2017, START, ym(2022, 3)),
                    (2, ym(2020, 6), 2019, ym(2019, 11), END),
                    (3, ym(2021, 1), 2017, START, ym(2022, 3)),
                    (4, ym(2022, 5), 2022, ym(2022, 4), END),
                ],
            )

            def members(cohort_id: int) -> dict[int, tuple]:
                return {
                    grid: (treat, control_type, first, last, rows)
                    for grid, treat, control_type, first, last, rows in con.execute(
                        """
                        SELECT unique_small_grid_id, any_value(treat),
                               any_value(control_type), min(monthyear),
                               max(monthyear), count(*)
                        FROM s WHERE cohort_id = ? GROUP BY 1
                        """,
                        [cohort_id],
                    ).fetchall()
                }

            term = ym(2022, 3) - START + 1
            # Punjab and Uttar Pradesh share the 2017 cohort; Haryana is excluded.
            self.assertEqual(
                members(1),
                {
                    1: (1, 0, START, ym(2022, 3), term),
                    2: (0, 2, START, ym(2020, 12), ym(2020, 12) - START + 1),
                    3: (0, 1, START, ym(2022, 3), term),
                    4: (0, 1, START, ym(2022, 3), term),
                    5: (0, 1, START, ym(2022, 3), term),
                },
            )
            self.assertEqual(set(members(2)), {6, 7})
            # Grid 5 switches in the 2022 term, so it is treated there with
            # 2022-term controls only.
            self.assertEqual(set(members(4)), {3, 4, 5})

            bad_rows = con.execute(
                """
                SELECT count_if(election_year <> cohort_election_year)
                     + count_if(treat = 0 AND protest5km = 1)
                     + count_if(post <> (monthyear >= cohort)::INTEGER)
                     + count_if(relative_year <> floor((monthyear - cohort) / 12.0))
                FROM s
                """
            ).fetchone()[0]
            self.assertEqual(bad_rows, 0)

    def test_matches_standard_engine_split_by_election_term(self) -> None:
        with temporary_workspace() as work:
            source = work / "panel.csv"
            write_csv(source, panel_rows())
            con = build(work, source)

            engine_csv = work / "engine.csv"
            core.main(
                [
                    "--input", str(source),
                    "--output", str(engine_csv),
                    "--database", str(work / "engine.db"),
                    "--temp-directory", str(work / "engine_tmp"),
                    "--treatment-col", "protest5km",
                    "--keep-cols", "unique_small_grid_id", "year", "month",
                    "monthyear", "election_year", "protest5km",
                    "--threads", "1",
                    "--memory-limit", "1GB",
                    "--year-level-controls",
                    "--overwrite",
                ]
            )
            # Standard stack, then keep each grid's rows in the election term in
            # force at the cohort month and drop groups without treated grids.
            con.execute(
                f"""
                CREATE TABLE engine AS
                WITH e AS (SELECT * FROM read_csv_auto('{engine_csv}')),
                at_cohort AS (
                    SELECT cohort, unique_small_grid_id, election_year AS term
                    FROM e WHERE monthyear = cohort
                ),
                split AS (
                    SELECT e.*, a.term
                    FROM e JOIN at_cohort a USING (cohort, unique_small_grid_id)
                    WHERE e.election_year = a.term
                )
                SELECT * FROM split
                WHERE (cohort, term) IN (
                    SELECT (cohort, term) FROM split WHERE treat = 1
                )
                """
            )
            differences = con.execute(
                """
                SELECT count(*) FROM (
                    (SELECT cohort, election_year, unique_small_grid_id, monthyear, treat
                     FROM engine
                     EXCEPT
                     SELECT cohort, cohort_election_year, unique_small_grid_id,
                            monthyear, treat
                     FROM s)
                    UNION ALL
                    (SELECT cohort, cohort_election_year, unique_small_grid_id,
                            monthyear, treat
                     FROM s
                     EXCEPT
                     SELECT cohort, election_year, unique_small_grid_id, monthyear, treat
                     FROM engine)
                )
                """
            ).fetchone()[0]
            self.assertEqual(differences, 0)

    def test_comparison_detects_identical_and_different_stacks(self) -> None:
        with temporary_workspace() as work:
            source = work / "panel.csv"
            write_csv(source, panel_rows())
            build(work, source).close()
            candidate = work / "stack.parquet"
            reference = work / "reference.csv"

            def compare(name: str) -> str:
                output = work / name
                comparison.main(
                    [
                        "--intermediate", str(work),
                        "--reference", str(reference),
                        "--candidate", str(candidate),
                        "--output-directory", str(output),
                        "--database", str(work / f"{name}.db"),
                        "--threads", "1",
                        "--memory-limit", "1GB",
                    ]
                )
                return (output / "report.txt").read_text(encoding="utf-8")

            con = duckdb.connect()
            con.execute(
                f"COPY (SELECT * FROM read_parquet('{candidate}')) "
                f"TO '{reference}' (FORMAT CSV, HEADER true)"
            )
            self.assertIn("VERDICT: STRUCTURE IDENTICAL", compare("same"))

            # Drop one control grid from the first cohort of the reference.
            con.execute(
                f"""
                COPY (SELECT * FROM read_parquet('{candidate}')
                      WHERE NOT (cohort_id = 1 AND unique_small_grid_id = 3))
                TO '{reference}' (FORMAT CSV, HEADER true)
                """
            )
            con.close()
            report = compare("different")
            self.assertIn("VERDICT: DIFFERENT", report)
            term = ym(2022, 3) - START + 1
            self.assertIn(f"Rows only in candidate: {term:,}", report)

    def test_reference_file_is_protected(self) -> None:
        with self.assertRaisesRegex(ValueError, "reference file"):
            builder.main(["--output-stem", builder.REFERENCE_STEM])


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Build the same-election-term protest stack from the master dataset.

The rules reproduce the RA's ``stacked_data_protest5km_election_sameterm.csv``
as documented by the August 2026 cohort audit
(``tables/exploratory_analysis/protest_cohort_audit``):

* A cohort is a (switching month, election year) pair: the grids that first
  switch from 0 to 1 in that month, grouped by the election year in force at
  the switch. Provinces that share an election year (Punjab and Uttar Pradesh
  in 2017) share a cohort.
* Controls are all grids with the same election year in force at the cohort
  month whose treatment is still 0 in that month, from any province. They are
  kept only while untreated, so not-yet-treated controls stop the month before
  their own switch, as in the standard stacking engine.
* Every row lies in the cohort's election term (``election_year`` equals
  ``cohort_election_year``). ``cohort_term_start`` and ``cohort_analysis_max``
  are the first and last panel months of that term.
* No pre/post balance or August 2022 cutoff is imposed; the analysis dofiles
  apply those restrictions.

``--treatment-col`` selects the binary, absorbing treatment: ``protest5km`` for
the keyword-rule protests, or another column built the same way.
"""

from __future__ import annotations

import argparse
import logging
import os
import shutil
from pathlib import Path
from typing import Sequence

import duckdb

from build_all_stacked_datasets_duckdb import COMMON_KEEP_COLUMNS, default_intermediate


# The RA's file is the reference for the replication check; never overwrite it.
REFERENCE_STEM = "stacked_data_protest5km_election_sameterm"

GENERATED_COLUMNS = (
    "treat",
    "post",
    "cohort",
    "relative_monthyear",
    "relative_year",
    "control_type",
    "cohort_id",
    "cohort_election_year",
    "cohort_term_start",
    "cohort_analysis_max",
)

# The dofiles assert cohort_analysis_max - cohort_term_start <= 59.
MAX_TERM_MONTHS = 60


def qid(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def qstr(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def source_sql(path: Path) -> str:
    suffixes = [suffix.lower() for suffix in path.suffixes]
    if ".parquet" in suffixes:
        return f"read_parquet({qstr(path.resolve())})"
    if ".csv" in suffixes:
        return f"read_csv_auto({qstr(path.resolve())}, header=true, sample_size=100000)"
    raise ValueError(f"Input must be Parquet or CSV: {path}")


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument("--intermediate", type=Path, default=default_intermediate())
    parser.add_argument("--input", type=Path, default=None)
    parser.add_argument("--treatment-col", default="protest5km")
    parser.add_argument(
        "--output-stem",
        default=None,
        help="Defaults to stacked_data_<treatment-col>_election_sameterm.",
    )
    parser.add_argument("--no-csv", action="store_true", help="Write Parquet only.")
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument("--memory-limit", default="60GB")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument(
        "--log-level", choices=("DEBUG", "INFO", "WARNING"), default="INFO"
    )
    return parser.parse_args(argv)


def resolve_paths(args: argparse.Namespace) -> None:
    args.intermediate = args.intermediate.resolve()
    args.input = (args.input or args.intermediate / "0_master_dataset.parquet").resolve()
    stem = args.output_stem or f"stacked_data_{args.treatment_col}_election_sameterm"
    if stem == REFERENCE_STEM:
        raise ValueError(
            f"{REFERENCE_STEM} is the RA's reference file; pass another --output-stem."
        )
    args.output_csv = args.intermediate / f"{stem}.csv"
    args.output_parquet = args.intermediate / f"{stem}.parquet"
    args.manifest = args.intermediate / f"{stem}_manifest.csv"
    args.database = args.intermediate / f"{stem}.db"
    args.temp_directory = args.intermediate / f"{stem}_duckdb_tmp"


def outputs(args: argparse.Namespace) -> list[Path]:
    paths = [args.output_parquet, args.manifest, args.database]
    if not args.no_csv:
        paths.append(args.output_csv)
    return paths


def remove_existing_outputs(args: argparse.Namespace) -> None:
    existing = [path for path in outputs(args) if path.exists()]
    if existing and not args.overwrite:
        raise FileExistsError(
            "Outputs already exist; pass --overwrite: "
            + ", ".join(str(path) for path in existing)
        )
    for path in existing:
        path.unlink()


def configure(con: duckdb.DuckDBPyConnection, args: argparse.Namespace) -> None:
    args.temp_directory.mkdir(parents=True, exist_ok=True)
    con.execute(f"SET threads={int(args.threads)}")
    con.execute(f"SET memory_limit={qstr(args.memory_limit)}")
    con.execute(f"SET temp_directory={qstr(args.temp_directory)}")
    con.execute("SET preserve_insertion_order=false")


def fail_if_positive(label: str, value: int) -> None:
    if int(value):
        raise ValueError(f"{label}: {int(value):,}")


def source_columns(treatment_col: str) -> list[str]:
    return list(dict.fromkeys([*COMMON_KEEP_COLUMNS, treatment_col]))


def build_panel(
    con: duckdb.DuckDBPyConnection, source: str, treatment_col: str
) -> None:
    available = {
        row[0] for row in con.execute(f"DESCRIBE SELECT * FROM {source}").fetchall()
    }
    missing = [c for c in source_columns(treatment_col) if c not in available]
    if missing:
        raise ValueError("Master input is missing: " + ", ".join(missing))

    select_columns = ",\n            ".join(qid(c) for c in source_columns(treatment_col))
    con.execute(
        f"""
        CREATE TABLE panel AS
        SELECT
            {select_columns},
            TRY_CAST(election_year AS INTEGER) AS _election_year,
            TRY_CAST({qid(treatment_col)} AS INTEGER) AS _treated
        FROM {source}
        """
    )
    rows, grids = con.execute(
        "SELECT count(*), count(DISTINCT unique_small_grid_id) FROM panel"
    ).fetchone()
    logging.info("Panel rows: %s | grids: %s", f"{rows:,}", f"{grids:,}")

    duplicates, bad_treatment, bad_election, bad_monthyear, gaps = con.execute(
        """
        SELECT
            (SELECT count(*) FROM (
                SELECT unique_small_grid_id, monthyear FROM panel
                GROUP BY 1, 2 HAVING count(*) > 1
            )),
            count_if(_treated IS NULL OR _treated NOT IN (0, 1)),
            count_if(_election_year IS NULL),
            count_if(monthyear <> year * 12 + month),
            (SELECT count(*) FROM (
                SELECT unique_small_grid_id FROM panel GROUP BY 1
                HAVING count(*) <> max(monthyear) - min(monthyear) + 1
            ))
        FROM panel
        """
    ).fetchone()
    fail_if_positive("Duplicated grid-month keys", duplicates)
    fail_if_positive(f"Missing or non-binary {treatment_col} rows", bad_treatment)
    fail_if_positive("Rows without an election year", bad_election)
    fail_if_positive("Rows where monthyear != year * 12 + month", bad_monthyear)
    fail_if_positive("Grid histories with missing months", gaps)


def build_switches_and_cohorts(con: duckdb.DuckDBPyConnection) -> None:
    con.execute(
        """
        CREATE TABLE histories AS
        SELECT
            unique_small_grid_id,
            monthyear,
            _election_year,
            _treated,
            lag(_treated) OVER (
                PARTITION BY unique_small_grid_id ORDER BY monthyear
            ) AS _lag
        FROM panel
        """
    )
    reversals, multiple_switches = con.execute(
        """
        SELECT count_if(reversals > 0), count_if(switches > 1)
        FROM (
            SELECT
                count_if(_lag = 1 AND _treated = 0) AS reversals,
                count_if(_lag = 0 AND _treated = 1) AS switches
            FROM histories GROUP BY unique_small_grid_id
        )
        """
    ).fetchone()
    fail_if_positive("Grid histories with 1-to-0 reversals", reversals)
    fail_if_positive("Grid histories with more than one 0-to-1 switch", multiple_switches)

    con.execute(
        """
        CREATE TABLE switches AS
        SELECT
            unique_small_grid_id,
            monthyear AS cohort,
            _election_year AS cohort_election_year
        FROM histories
        WHERE _lag = 0 AND _treated = 1
        """
    )
    con.execute("DROP TABLE histories")

    con.execute(
        """
        CREATE TABLE terms AS
        SELECT
            _election_year AS cohort_election_year,
            min(monthyear) AS cohort_term_start,
            max(monthyear) AS cohort_analysis_max
        FROM panel
        GROUP BY 1
        """
    )
    con.execute(
        """
        CREATE TABLE cohorts AS
        SELECT
            row_number() OVER (ORDER BY s.cohort, s.cohort_election_year)::INTEGER
                AS cohort_id,
            s.cohort,
            s.cohort_election_year,
            t.cohort_term_start,
            t.cohort_analysis_max,
            count(*)::BIGINT AS treated_grids
        FROM switches s
        JOIN terms t USING (cohort_election_year)
        GROUP BY s.cohort, s.cohort_election_year,
                 t.cohort_term_start, t.cohort_analysis_max
        """
    )
    long_terms = con.execute(
        f"""
        SELECT count_if(cohort_analysis_max - cohort_term_start >= {MAX_TERM_MONTHS})
        FROM cohorts
        """
    ).fetchone()[0]
    fail_if_positive(f"Cohort terms longer than {MAX_TERM_MONTHS} months", long_terms)


def build_stack(con: duckdb.DuckDBPyConnection, treatment_col: str) -> None:
    columns = ",\n            ".join(f"p.{qid(c)}" for c in source_columns(treatment_col))
    con.execute(
        f"""
        CREATE TABLE members AS
        SELECT c.cohort_id, s.unique_small_grid_id, 1::TINYINT AS treat
        FROM cohorts c
        JOIN switches s USING (cohort, cohort_election_year)
        UNION ALL
        -- Controls: same election year in force and still untreated at the cohort.
        SELECT c.cohort_id, p.unique_small_grid_id, 0::TINYINT AS treat
        FROM cohorts c
        JOIN panel p
          ON p.monthyear = c.cohort
         AND p._election_year = c.cohort_election_year
         AND p._treated = 0
        """
    )
    con.execute(
        f"""
        CREATE TABLE stack_rows AS
        SELECT
            {columns},
            m.treat,
            (p.monthyear >= c.cohort)::TINYINT AS post,
            c.cohort,
            (p.monthyear - c.cohort)::INTEGER AS relative_monthyear,
            floor((p.monthyear - c.cohort) / 12.0)::INTEGER AS relative_year,
            c.cohort_id,
            c.cohort_election_year,
            c.cohort_term_start,
            c.cohort_analysis_max
        FROM members m
        JOIN cohorts c USING (cohort_id)
        JOIN panel p
          ON p.unique_small_grid_id = m.unique_small_grid_id
         AND p._election_year = c.cohort_election_year
        -- Treated grids keep the whole term; controls stop before their own switch.
        WHERE m.treat = 1 OR p._treated = 0
        """
    )
    # control_type: 0 treated, 1 untreated over the whole term, 2 not yet treated.
    control_type = """CASE
                WHEN treat = 1 THEN 0
                WHEN count(*) OVER (PARTITION BY cohort_id, unique_small_grid_id)
                     = cohort_analysis_max - cohort_term_start + 1 THEN 1
                ELSE 2
            END::TINYINT AS control_type"""
    output_columns = ",\n            ".join(
        control_type if c == "control_type" else qid(c)
        for c in [*source_columns(treatment_col), *GENERATED_COLUMNS]
    )
    con.execute(
        f"""
        CREATE TABLE final_stack AS
        SELECT
            {output_columns}
        FROM stack_rows
        """
    )
    con.execute("DROP TABLE stack_rows")
    con.execute("DROP TABLE members")


def validate_final(con: duckdb.DuckDBPyConnection, treatment_col: str) -> None:
    treatment = qid(treatment_col)
    (
        duplicates,
        wrong_term,
        outside_term,
        treated_path,
        control_path,
        missing_control_type,
    ) = con.execute(
        f"""
        SELECT
            (SELECT count(*) FROM (
                SELECT cohort_id, unique_small_grid_id, monthyear
                FROM final_stack GROUP BY 1, 2, 3 HAVING count(*) > 1
            )),
            count_if(TRY_CAST(election_year AS INTEGER) <> cohort_election_year),
            count_if(monthyear < cohort_term_start OR monthyear > cohort_analysis_max),
            count_if(treat = 1 AND (
                (monthyear < cohort AND {treatment} <> 0)
                OR (monthyear >= cohort AND {treatment} <> 1)
            )),
            count_if(treat = 0 AND {treatment} <> 0),
            count_if(control_type IS NULL)
        FROM final_stack
        """
    ).fetchone()
    for label, value in (
        ("Duplicated cohort-grid-month keys", duplicates),
        ("Rows outside the cohort election year", wrong_term),
        ("Rows outside the cohort term", outside_term),
        ("Treated rows that do not switch at the cohort month", treated_path),
        ("Control rows observed after their own switch", control_path),
        ("Rows without control_type", missing_control_type),
    ):
        fail_if_positive(label, value)


def create_manifest(con: duckdb.DuckDBPyConnection) -> None:
    con.execute(
        """
        CREATE TABLE cohort_manifest AS
        SELECT
            cohort_id,
            any_value(cohort) AS cohort,
            any_value(cohort_election_year) AS cohort_election_year,
            any_value(cohort_term_start) AS cohort_term_start,
            any_value(cohort_analysis_max) AS cohort_analysis_max,
            count(DISTINCT province) AS provinces,
            count(DISTINCT unique_small_grid_id) FILTER (WHERE treat = 1)
                AS treated_grids,
            count(DISTINCT unique_small_grid_id) FILTER (WHERE treat = 0)
                AS control_grids,
            count(DISTINCT unique_small_grid_id) FILTER (WHERE control_type = 2)
                AS notyet_treated_controls,
            count_if(treat = 1) AS treated_rows,
            count_if(treat = 0) AS control_rows,
            count(*) AS rows
        FROM final_stack
        GROUP BY cohort_id
        ORDER BY cohort_id
        """
    )


def export_outputs(con: duckdb.DuckDBPyConnection, args: argparse.Namespace) -> None:
    order = "ORDER BY cohort_id, unique_small_grid_id, monthyear"
    logging.info("Exporting Parquet: %s", args.output_parquet)
    con.execute(
        f"COPY (SELECT * FROM final_stack {order}) TO {qstr(args.output_parquet)} "
        "(FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 250000)"
    )
    if not args.no_csv:
        logging.info("Exporting CSV: %s", args.output_csv)
        con.execute(
            f"COPY (SELECT * FROM final_stack {order}) TO {qstr(args.output_csv)} "
            "(FORMAT CSV, HEADER true)"
        )
    con.execute(
        f"COPY cohort_manifest TO {qstr(args.manifest)} (FORMAT CSV, HEADER true)"
    )


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s | %(levelname)s | %(message)s",
    )
    resolve_paths(args)
    if not args.input.is_file():
        raise FileNotFoundError(args.input)
    logging.info("Input: %s", args.input)
    logging.info("Treatment: %s", args.treatment_col)
    logging.info("Cohort key: switching month x election year")

    remove_existing_outputs(args)
    con = duckdb.connect(str(args.database))
    try:
        configure(con, args)
        build_panel(con, source_sql(args.input), args.treatment_col)
        build_switches_and_cohorts(con)
        cohorts, treated = con.execute(
            "SELECT count(*), sum(treated_grids) FROM cohorts"
        ).fetchone()
        logging.info("Cohorts: %s | treated grids: %s", cohorts, f"{int(treated or 0):,}")
        build_stack(con, args.treatment_col)
        validate_final(con, args.treatment_col)
        create_manifest(con)
        rows, grids, treated_rows = con.execute(
            """
            SELECT count(*), count(DISTINCT unique_small_grid_id), count_if(treat = 1)
            FROM final_stack
            """
        ).fetchone()
        logging.info(
            "Final rows: %s | grids: %s | treated rows: %s",
            f"{rows:,}",
            f"{grids:,}",
            f"{treated_rows:,}",
        )
        export_outputs(con, args)
        con.execute("CHECKPOINT")
    finally:
        con.close()
        shutil.rmtree(args.temp_directory, ignore_errors=True)
    logging.info("Completed %s", args.output_parquet.name)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        logging.error("Interrupted")
        raise SystemExit(130)
    except Exception as exc:
        logging.exception("Protest stack construction failed: %s", exc)
        raise SystemExit(1)

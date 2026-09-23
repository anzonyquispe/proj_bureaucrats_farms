#!/usr/bin/env python3
"""Build protest stacks by province, election term, and switching month.

Each cohort is uniquely defined by ``province x election_year x cohort`` where
``cohort`` is a calendar month in which one or more grids first switch from
``protest5km = 0`` to ``protest5km = 1``. Treated grids in a cohort therefore
switch on exactly the same date. Eligible controls:

* belong to the same province and election term;
* are untreated at the cohort month;
* are either never treated during that term (``control_type = 1``), or switch
  later in the term (``control_type = 2``).

Not-yet-treated controls are censored in the month before their own switch.
Never-treated controls and treated grids are retained through the earlier of
the same government term's end and August 2022. Every retained grid-cohort has
both pre- and post-cohort observations and an uninterrupted sequence of monthly
observations. The script writes CSV and Parquet analysis files, a DuckDB with
all construction tables, and a cohort-level manifest.
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path
from typing import Sequence

import duckdb


CLUSTER_INTERMEDIATE = Path(
    "/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate"
)
LOCAL_INTERMEDIATE = Path(
    r"C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms"
    r"\data_output\intermediate"
)
OUTPUT_STEM = "stacked_data_protest5km_province_election_switch"
LAST_ANALYSIS_YEAR = 2022
LAST_ANALYSIS_MONTH = 8

SOURCE_COLUMNS = (
    "unique_small_grid_id",
    "ac_uq_id",
    "province",
    "distr_id",
    "district",
    "month",
    "year",
    "monthyear",
    "count",
    "mean_brightness",
    "av_wind_speed",
    "wind_direction",
    "downup_ac",
    "downup_ac_pop",
    "rice_area_aclvl_ahigh",
    "rice_harvarea_aclvl_ahigh",
    "rice_prod_aclvl_ahigh",
    "protest5km",
    "protest_id",
    "protest_place",
    "election_year",
    "yeargov",
    "year_take",
    "month_take",
    "year_end",
    "month_end",
    "ym_take",
)


def default_intermediate() -> Path:
    return LOCAL_INTERMEDIATE if LOCAL_INTERMEDIATE.exists() else CLUSTER_INTERMEDIATE


def qid(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def qstr(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def source_sql(path: Path) -> str:
    suffixes = [suffix.lower() for suffix in path.suffixes]
    if ".parquet" in suffixes:
        return f"read_parquet({qstr(path.resolve())})"
    if ".csv" in suffixes:
        compression = ", compression='gzip'" if path.suffix.lower() == ".gz" else ""
        return (
            f"read_csv_auto({qstr(path.resolve())}, header=true, "
            f"sample_size=100000{compression})"
        )
    raise ValueError(f"Input must be Parquet or CSV: {path}")


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument("--intermediate", type=Path, default=default_intermediate())
    parser.add_argument("--input", type=Path, default=None)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--output-parquet", type=Path, default=None)
    parser.add_argument("--database", type=Path, default=None)
    parser.add_argument("--manifest", type=Path, default=None)
    parser.add_argument("--temp-directory", type=Path, default=None)
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument("--memory-limit", default="110GB")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--log-level", choices=("DEBUG", "INFO", "WARNING"), default="INFO"
    )
    return parser.parse_args(argv)


def resolve_paths(args: argparse.Namespace) -> None:
    intermediate = args.intermediate.resolve()
    args.intermediate = intermediate
    args.input = (args.input or intermediate / "0_master_dataset.parquet").resolve()
    args.output_csv = (
        args.output_csv or intermediate / f"{OUTPUT_STEM}.csv"
    ).resolve()
    args.output_parquet = (
        args.output_parquet or intermediate / f"{OUTPUT_STEM}.parquet"
    ).resolve()
    args.database = (args.database or intermediate / f"{OUTPUT_STEM}.db").resolve()
    args.manifest = (
        args.manifest or intermediate / f"{OUTPUT_STEM}_manifest.csv"
    ).resolve()
    args.temp_directory = (
        args.temp_directory or intermediate / f"{OUTPUT_STEM}_duckdb_tmp"
    ).resolve()


def configure(con: duckdb.DuckDBPyConnection, args: argparse.Namespace) -> None:
    args.temp_directory.mkdir(parents=True, exist_ok=True)
    con.execute(f"SET threads={int(args.threads)}")
    con.execute(f"SET memory_limit={qstr(args.memory_limit)}")
    con.execute(f"SET temp_directory={qstr(args.temp_directory)}")
    con.execute("SET preserve_insertion_order=false")


def remove_existing_outputs(args: argparse.Namespace) -> None:
    outputs = (args.output_csv, args.output_parquet, args.database, args.manifest)
    existing = [path for path in outputs if path.exists()]
    if existing and not args.overwrite:
        raise FileExistsError(
            "Outputs already exist; pass --overwrite: "
            + ", ".join(str(path) for path in existing)
        )
    if args.overwrite:
        for path in existing:
            if path.is_file():
                path.unlink()


def require_columns(con: duckdb.DuckDBPyConnection, source: str) -> None:
    columns = {
        row[0]
        for row in con.execute(f"DESCRIBE SELECT * FROM {source}").fetchall()
    }
    missing = [column for column in SOURCE_COLUMNS if column not in columns]
    if missing:
        raise ValueError("Master input is missing: " + ", ".join(missing))


def fail_if_positive(label: str, value: int) -> None:
    if int(value):
        raise ValueError(f"{label}: {int(value):,}")


def build_panel(con: duckdb.DuckDBPyConnection, source: str) -> None:
    select_columns = ",\n                ".join(qid(column) for column in SOURCE_COLUMNS)
    con.execute(
        f"""
        CREATE TABLE panel AS
        SELECT
            {select_columns},
            TRY_CAST(election_year AS INTEGER) AS _election_year,
            COALESCE(
                TRY_CAST(ym_take AS BIGINT),
                TRY_CAST(year_take AS BIGINT) * 12 + TRY_CAST(month_take AS BIGINT)
            ) AS _term_start,
            TRY_CAST(year_end AS BIGINT) * 12 + TRY_CAST(month_end AS BIGINT)
                AS _term_end
        FROM {source}
        ORDER BY unique_small_grid_id, monthyear
        """
    )

    rows, grids = con.execute(
        "SELECT count(*), count(DISTINCT unique_small_grid_id) FROM panel"
    ).fetchone()
    logging.info("Panel rows: %s", f"{int(rows):,}")
    logging.info("Panel grids: %s", f"{int(grids):,}")

    duplicate_keys, invalid_treatment, missing_terms, changing_province = con.execute(
        """
        SELECT
            (SELECT count(*) FROM (
                SELECT unique_small_grid_id, monthyear
                FROM panel GROUP BY 1, 2 HAVING count(*) <> 1
            )),
            count_if(protest5km IS NULL OR protest5km NOT IN (0, 1)),
            count_if(_election_year IS NULL OR _term_start IS NULL OR _term_end IS NULL
                     OR _term_start > monthyear OR monthyear >= _term_end),
            (SELECT count(*) FROM (
                SELECT unique_small_grid_id
                FROM panel GROUP BY 1 HAVING count(DISTINCT province) <> 1
            ))
        FROM panel
        """
    ).fetchone()
    fail_if_positive("Duplicated grid-month keys", duplicate_keys)
    fail_if_positive("Invalid or missing protest5km rows", invalid_treatment)
    fail_if_positive("Rows outside a valid election term", missing_terms)
    fail_if_positive("Grid histories that change province", changing_province)


def build_switches_and_cohorts(con: duckdb.DuckDBPyConnection) -> None:
    con.execute(
        f"""
        CREATE TABLE histories AS
        SELECT
            p.*,
            lag(protest5km) OVER (
                PARTITION BY unique_small_grid_id ORDER BY monthyear
            ) AS protest_lag
        FROM panel p
        """
    )
    reversals, multiple_switches = con.execute(
        """
        WITH unit_checks AS (
            SELECT
                unique_small_grid_id,
                count_if(protest_lag = 1 AND protest5km = 0) AS reversals,
                count_if(protest_lag = 0 AND protest5km = 1) AS switches
            FROM histories GROUP BY 1
        )
        SELECT count_if(reversals > 0), count_if(switches > 1) FROM unit_checks
        """
    ).fetchone()
    fail_if_positive("Grid histories with 1-to-0 protest reversals", reversals)
    fail_if_positive("Grid histories with multiple 0-to-1 switches", multiple_switches)

    con.execute(
        """
        CREATE TABLE unit_switches AS
        SELECT
            unique_small_grid_id,
            min(monthyear) FILTER (WHERE protest_lag = 0 AND protest5km = 1)
                AS first_switch
        FROM histories
        GROUP BY 1
        """
    )
    con.execute(
        f"""
        CREATE TABLE switch_events AS
        SELECT
            h.unique_small_grid_id,
            h.province,
            h._election_year AS cohort_election_year,
            h.monthyear AS cohort,
            h._term_start AS cohort_term_start,
            h._term_end AS cohort_term_end
        FROM histories h
        WHERE h.protest_lag = 0
          AND h.protest5km = 1
          AND h.monthyear > h._term_start
          AND h.monthyear < h._term_end
          AND (
                h.year < {LAST_ANALYSIS_YEAR}
             OR (h.year = {LAST_ANALYSIS_YEAR}
                 AND h.month <= {LAST_ANALYSIS_MONTH})
          )
        """
    )
    con.execute(
        """
        CREATE TABLE cohort_manifest_base AS
        SELECT
            row_number() OVER (
                ORDER BY province, cohort_election_year, cohort,
                         cohort_term_start, cohort_term_end
            )::INTEGER AS cohort_id,
            province,
            cohort_election_year,
            cohort,
            cohort_term_start,
            cohort_term_end,
            count(DISTINCT unique_small_grid_id)::BIGINT AS source_treated_units
        FROM switch_events
        GROUP BY
            province, cohort_election_year, cohort,
            cohort_term_start, cohort_term_end
        """
    )
    duplicate_triples = con.execute(
        """
        SELECT count(*) FROM (
            SELECT province, cohort_election_year, cohort
            FROM cohort_manifest_base
            GROUP BY 1, 2, 3
            HAVING count(*) <> 1
        )
        """
    ).fetchone()[0]
    fail_if_positive(
        "Province-election-switch triples spanning multiple government terms",
        duplicate_triples,
    )
    con.execute("DROP TABLE histories")


def build_assignments_and_stack(con: duckdb.DuckDBPyConnection) -> None:
    con.execute(
        """
        CREATE TABLE unit_terms AS
        SELECT
            unique_small_grid_id,
            province,
            _election_year AS cohort_election_year,
            _term_start AS cohort_term_start,
            _term_end AS cohort_term_end,
            min(monthyear) AS observed_term_min,
            max(monthyear) AS observed_term_max
        FROM panel
        GROUP BY 1, 2, 3, 4, 5
        """
    )
    con.execute(
        """
        CREATE TABLE assignments AS
        SELECT
            c.cohort_id,
            c.province AS cohort_province,
            c.cohort_election_year,
            c.cohort,
            c.cohort_term_start,
            c.cohort_term_end,
            u.unique_small_grid_id,
            s.first_switch AS unit_first_switch,
            CASE WHEN s.first_switch = c.cohort THEN 1 ELSE 0 END::TINYINT
                AS treat,
            CASE
                WHEN s.first_switch = c.cohort THEN 0
                WHEN s.first_switch IS NULL OR s.first_switch >= c.cohort_term_end
                    THEN 1
                ELSE 2
            END::TINYINT AS control_type,
            CASE
                WHEN s.first_switch > c.cohort
                 AND s.first_switch < c.cohort_term_end
                    THEN s.first_switch
                ELSE c.cohort_term_end
            END::BIGINT AS analysis_end_exclusive
        FROM cohort_manifest_base c
        JOIN unit_terms u
          ON u.province = c.province
         AND u.cohort_election_year = c.cohort_election_year
         AND u.cohort_term_start = c.cohort_term_start
         AND u.cohort_term_end = c.cohort_term_end
         AND u.observed_term_min <= c.cohort
         AND u.observed_term_max >= c.cohort
        JOIN unit_switches s USING (unique_small_grid_id)
        JOIN panel at_cohort
          ON at_cohort.unique_small_grid_id = u.unique_small_grid_id
         AND at_cohort.monthyear = c.cohort
        WHERE (s.first_switch IS NULL OR s.first_switch >= c.cohort)
          AND (
                (s.first_switch = c.cohort AND at_cohort.protest5km = 1)
             OR (s.first_switch IS DISTINCT FROM c.cohort
                 AND at_cohort.protest5km = 0)
          )
        """
    )

    source_cols = ",\n                ".join(f"p.{qid(c)}" for c in SOURCE_COLUMNS)
    con.execute(
        f"""
        CREATE TABLE raw_stack AS
        SELECT
            {source_cols},
            a.treat,
            CASE WHEN p.monthyear >= a.cohort THEN 1 ELSE 0 END::TINYINT AS post,
            a.cohort,
            (p.monthyear - a.cohort)::INTEGER AS relative_monthyear,
            floor((p.monthyear - a.cohort) / 12.0)::INTEGER AS relative_year,
            floor((p.monthyear - a.cohort) / 12.0)::INTEGER AS relative_year_bin,
            a.control_type,
            a.cohort_id,
            a.cohort_province,
            a.cohort_election_year,
            a.cohort_term_start,
            a.cohort_term_end,
            a.unit_first_switch AS control_switch_month
        FROM assignments a
        JOIN panel p
          ON p.unique_small_grid_id = a.unique_small_grid_id
         AND p.province = a.cohort_province
         AND p._election_year = a.cohort_election_year
         AND p._term_start = a.cohort_term_start
         AND p._term_end = a.cohort_term_end
         AND p.monthyear >= a.cohort_term_start
         AND p.monthyear < a.analysis_end_exclusive
         AND (
                p.year < {LAST_ANALYSIS_YEAR}
             OR (p.year = {LAST_ANALYSIS_YEAR}
                 AND p.month <= {LAST_ANALYSIS_MONTH})
         )
        """
    )
    con.execute(
        """
        CREATE TABLE eligible_units AS
        SELECT cohort_id, unique_small_grid_id
        FROM raw_stack
        GROUP BY 1, 2
        HAVING count_if(relative_monthyear < 0) > 0
           AND count_if(relative_monthyear >= 0) > 0
           AND count(*) = max(monthyear) - min(monthyear) + 1
           AND count(DISTINCT monthyear) = count(*)
        """
    )
    con.execute(
        """
        CREATE TABLE final_stack AS
        SELECT r.*
        FROM raw_stack r
        JOIN eligible_units b USING (cohort_id, unique_small_grid_id)
        """
    )
    con.execute("DROP TABLE raw_stack")
    con.execute("DROP TABLE panel")


def validate_final(con: duckdb.DuckDBPyConnection) -> None:
    (
        duplicate_keys,
        wrong_province,
        wrong_election,
        before_term,
        after_term,
        invalid_treated_path,
        invalid_control_path,
        invalid_control_type,
    ) = con.execute(
        f"""
        SELECT
            (SELECT count(*) FROM (
                SELECT cohort_id, unique_small_grid_id, monthyear
                FROM final_stack GROUP BY 1, 2, 3 HAVING count(*) <> 1
            )),
            count_if(province <> cohort_province),
            count_if(TRY_CAST(election_year AS INTEGER) <> cohort_election_year),
            count_if(monthyear < cohort_term_start),
            count_if(monthyear >= cohort_term_end),
            count_if(treat = 1 AND (
                (monthyear < cohort AND protest5km <> 0)
                OR (monthyear >= cohort AND protest5km <> 1)
            )),
            count_if(treat = 0 AND protest5km <> 0),
            count_if((treat = 1 AND control_type <> 0)
                     OR (treat = 0 AND control_type NOT IN (1, 2)))
        FROM final_stack
        """
    ).fetchone()
    for label, value in (
        ("Duplicated cohort-grid-month keys", duplicate_keys),
        ("Rows whose province differs from the cohort", wrong_province),
        ("Rows whose election year differs from the cohort", wrong_election),
        ("Rows before the government term", before_term),
        ("Rows after the government term", after_term),
        ("Treated rows that do not switch at cohort", invalid_treated_path),
        ("Control rows observed after becoming treated", invalid_control_path),
        ("Rows with invalid control_type", invalid_control_type),
    ):
        fail_if_positive(label, value)

    (
        mixed_cohorts,
        bad_switch_dates,
        missing_groups,
        unbalanced_units,
        discontinuous_units,
        rows_after_cutoff,
    ) = con.execute(
        f"""
        SELECT
            (SELECT count(*) FROM (
                SELECT cohort_id FROM final_stack GROUP BY 1
                HAVING count(DISTINCT cohort_province) <> 1
                    OR count(DISTINCT cohort_election_year) <> 1
                    OR count(DISTINCT cohort) <> 1
                    OR count(DISTINCT cohort_term_start) <> 1
                    OR count(DISTINCT cohort_term_end) <> 1
            )),
            (SELECT count(*) FROM (
                SELECT cohort_id FROM final_stack WHERE treat = 1 GROUP BY 1
                HAVING count(DISTINCT control_switch_month) <> 1
                    OR min(control_switch_month) <> min(cohort)
            )),
            (SELECT count(*) FROM (
                SELECT cohort_id FROM final_stack GROUP BY 1
                HAVING count(DISTINCT CASE WHEN treat = 1 THEN unique_small_grid_id END) = 0
                    OR count(DISTINCT CASE WHEN treat = 0 THEN unique_small_grid_id END) = 0
            )),
            (SELECT count(*) FROM (
                SELECT cohort_id, unique_small_grid_id FROM final_stack GROUP BY 1, 2
                HAVING count_if(relative_monthyear < 0) = 0
                    OR count_if(relative_monthyear >= 0) = 0
            )),
            (SELECT count(*) FROM (
                SELECT cohort_id, unique_small_grid_id FROM final_stack GROUP BY 1, 2
                HAVING count(*) <> max(monthyear) - min(monthyear) + 1
                    OR count(DISTINCT monthyear) <> count(*)
            )),
            count_if(
                year > {LAST_ANALYSIS_YEAR}
                OR (year = {LAST_ANALYSIS_YEAR}
                    AND month > {LAST_ANALYSIS_MONTH})
            )
            FROM final_stack
        """
    ).fetchone()
    for label, value in (
        ("Cohorts mixing province/date/election-term constants", mixed_cohorts),
        ("Cohorts whose treated grids have different switch dates", bad_switch_dates),
        ("Cohorts missing treated or control units", missing_groups),
        ("Grid-cohorts without both pre and post observations", unbalanced_units),
        ("Grid-cohorts with gaps in their retained monthly history", discontinuous_units),
        ("Rows after August 2022", rows_after_cutoff),
    ):
        fail_if_positive(label, value)


def create_manifest(con: duckdb.DuckDBPyConnection) -> None:
    con.execute(
        """
        CREATE TABLE cohort_manifest AS
        SELECT
            cohort_id,
            any_value(cohort_province) AS province,
            any_value(cohort_election_year) AS election_year,
            any_value(cohort) AS switching_month,
            any_value(cohort_term_start) AS term_start,
            any_value(cohort_term_end) AS term_end_exclusive,
            count(DISTINCT CASE WHEN treat = 1 THEN unique_small_grid_id END)
                AS treated_grids,
            count(DISTINCT CASE WHEN control_type = 1 THEN unique_small_grid_id END)
                AS never_treated_controls,
            count(DISTINCT CASE WHEN control_type = 2 THEN unique_small_grid_id END)
                AS notyet_treated_controls,
            min(relative_monthyear) AS relative_month_min,
            max(relative_monthyear) AS relative_month_max,
            count(*) AS rows
        FROM final_stack
        GROUP BY cohort_id
        ORDER BY cohort_id
        """
    )


def export_outputs(con: duckdb.DuckDBPyConnection, args: argparse.Namespace) -> None:
    logging.info("Exporting Parquet: %s", args.output_parquet)
    con.execute(
        f"COPY final_stack TO {qstr(args.output_parquet)} "
        "(FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 250000)"
    )
    logging.info("Exporting CSV: %s", args.output_csv)
    con.execute(
        f"COPY final_stack TO {qstr(args.output_csv)} "
        "(FORMAT CSV, HEADER true)"
    )
    con.execute(
        f"COPY cohort_manifest TO {qstr(args.manifest)} "
        "(FORMAT CSV, HEADER true)"
    )


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s | %(levelname)s | %(message)s",
    )
    resolve_paths(args)
    if args.threads < 1:
        raise ValueError("--threads must be positive")
    if not args.input.is_file():
        raise FileNotFoundError(args.input)
    for path in (args.output_csv, args.output_parquet, args.database, args.manifest):
        path.parent.mkdir(parents=True, exist_ok=True)

    logging.info("Input: %s", args.input)
    logging.info("Cohort key: province x election_year x switching month")
    logging.info("Control rule: never treated or censored not-yet treated")
    if args.dry_run:
        con = duckdb.connect()
        try:
            require_columns(con, source_sql(args.input))
        finally:
            con.close()
        logging.info("Dry-run schema validation completed")
        return 0

    remove_existing_outputs(args)
    con = duckdb.connect(str(args.database))
    try:
        configure(con, args)
        source = source_sql(args.input)
        require_columns(con, source)
        build_panel(con, source)
        build_switches_and_cohorts(con)
        cohort_count, treated_count = con.execute(
            "SELECT count(*), sum(source_treated_units) FROM cohort_manifest_base"
        ).fetchone()
        logging.info("Candidate cohorts: %s", f"{int(cohort_count):,}")
        logging.info("Candidate treated grids: %s", f"{int(treated_count):,}")
        build_assignments_and_stack(con)
        validate_final(con)
        create_manifest(con)
        rows, cohorts, grids = con.execute(
            """
            SELECT count(*), count(DISTINCT cohort_id),
                   count(DISTINCT unique_small_grid_id)
            FROM final_stack
            """
        ).fetchone()
        logging.info("Final rows: %s", f"{int(rows):,}")
        logging.info("Final cohorts: %s", f"{int(cohorts):,}")
        logging.info("Distinct grids used: %s", f"{int(grids):,}")
        export_outputs(con, args)
        con.execute("CHECKPOINT")
    finally:
        con.close()
    logging.info("Completed province-election-switch protest stack")
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

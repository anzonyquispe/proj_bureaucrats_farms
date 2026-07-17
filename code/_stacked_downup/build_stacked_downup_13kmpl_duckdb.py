#!/usr/bin/env python3
"""Build a stacked DiD dataset around downup_13kmpl 0 -> 1 switches.

This is a disk-backed DuckDB translation of the supplied R/data.table script.
It is designed for large CSV/Parquet inputs and low RAM use.

Default behavior mirrors the R script:
  * panel unit: unique_small_grid_id
  * treatment history: downup_13kmpl
  * cohorts: calendar months with a 0 -> 1 switch
  * treated observations: clean treatment spell around the switch
  * controls: clean zero-treatment spell covering the cohort month
  * cohort window: pooled t_min/t_max across treated grids
  * output: one final CSV, not one file per cohort

The source data must already contain downup_13kmpl. The script uses it to create
stacked treatment indicator `treat`, cohort, and relative_monthyear.

If monthyear is absent, it is created as:
    monthyear = year * 12 + month - 1

By default, the complete clean spell is retained, exactly as in the R script.
Use --pre-periods and --post-periods together to impose a fixed event window.
"""

from __future__ import annotations

import argparse
import csv
import json
import logging
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Sequence

try:
    import duckdb
except ImportError as exc:  # pragma: no cover
    raise SystemExit("DuckDB is required. Install it with: pip install duckdb") from exc


R_DEFAULT_COLUMNS = [
    "unique_small_grid_id",
    "month",
    "year",
    "monthyear",
    "province",
    "ac_uq_id",
    "downup_ac_pop",
    "downup_13kmpl",
    "count",
    "av_wind_speed",
    "wind_direction",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build one stacked DiD CSV around downup_13kmpl 0->1 events "
            "using disk-backed DuckDB."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--input",
        required=True,
        type=Path,
        help="Input CSV, compressed CSV, or Parquet file.",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Final combined CSV path.",
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=None,
        help="Working DuckDB file. Defaults to OUTPUT with suffix .duckdb.",
    )
    parser.add_argument(
        "--treatment-col",
        default="downup_13kmpl",
        help="Binary source treatment used to identify 0->1 switching events.",
    )
    parser.add_argument(
        "--unit-col",
        default="unique_small_grid_id",
        help="Column identifying one panel unit.",
    )
    parser.add_argument(
        "--time-col",
        default="monthyear",
        help=(
            "Consecutive monthly time column. If absent, it is generated from "
            "--year-col and --month-col."
        ),
    )
    parser.add_argument("--year-col", default="year")
    parser.add_argument("--month-col", default="month")

    parser.add_argument(
        "--pre-periods",
        type=int,
        default=None,
        help=(
            "Optional maximum number of pre-treatment months. Omit this and "
            "--post-periods to preserve the R script's full clean spell."
        ),
    )
    parser.add_argument(
        "--post-periods",
        type=int,
        default=None,
        help=(
            "Optional number of post-treatment months. Must be supplied together "
            "with --pre-periods."
        ),
    )
    parser.add_argument(
        "--post-definition",
        choices=["include_event", "after_event"],
        default="include_event",
        help=(
            "include_event: post periods are 0,...,P-1; after_event: counted post "
            "periods are 1,...,P while event time 0 is still retained."
        ),
    )
    parser.add_argument(
        "--min-pre",
        type=int,
        default=0,
        help="Minimum distinct pre-treatment months required per stacked unit.",
    )
    parser.add_argument(
        "--min-post",
        type=int,
        default=0,
        help="Minimum distinct post-treatment months required per stacked unit.",
    )
    parser.add_argument(
        "--require-full-window",
        action="store_true",
        help="Require all requested pre and post periods.",
    )

    parser.add_argument(
        "--cutoff-year",
        type=int,
        default=None,
        help=(
            "Optional final sample year. If supplied, retain earlier years and "
            "months through --cutoff-month in this year."
        ),
    )
    parser.add_argument(
        "--cutoff-month",
        type=int,
        default=12,
        help="Last retained month in --cutoff-year.",
    )

    parser.add_argument(
        "--keep-cols",
        nargs="*",
        default=None,
        help=(
            "Source columns retained in the final stack. Defaults to the columns "
            "listed in the R script. Required identifiers are added automatically."
        ),
    )
    parser.add_argument(
        "--keep-all-columns",
        action="store_true",
        help="Retain every input column. This increases disk use and runtime.",
    )
    parser.add_argument(
        "--allow-missing-default-columns",
        action="store_true",
        help=(
            "Do not fail when optional R-script columns such as province or "
            "downup_ac_pop are absent; retain those that exist."
        ),
    )
    parser.add_argument(
        "--allow-duplicate-unit-time",
        action="store_true",
        help="Allow duplicate unit-month rows. This is not recommended.",
    )

    parser.add_argument(
        "--memory-limit",
        default="8GB",
        help="DuckDB RAM limit, for example 8GB or 60000MB.",
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, min(8, os.cpu_count() or 1)),
        help="DuckDB worker threads.",
    )
    parser.add_argument(
        "--temp-directory",
        type=Path,
        default=None,
        help="Directory used when DuckDB spills operations to disk.",
    )
    parser.add_argument(
        "--csv-sample-size",
        type=int,
        default=100_000,
        help="Rows sampled by DuckDB for CSV type inference; -1 scans all rows.",
    )
    parser.add_argument(
        "--checkpoint-every",
        type=int,
        default=25,
        help="Checkpoint the database after this many cohorts.",
    )
    parser.add_argument(
        "--cohort-min",
        type=int,
        default=None,
        help="Optional minimum cohort time index.",
    )
    parser.add_argument(
        "--cohort-max",
        type=int,
        default=None,
        help="Optional maximum cohort time index.",
    )
    parser.add_argument(
        "--compression",
        choices=["none", "gzip", "zstd"],
        default="none",
        help="Compression for the final CSV.",
    )
    parser.add_argument(
        "--sort-final",
        action="store_true",
        help="Sort final CSV by cohort, unit, and monthyear. This can be expensive.",
    )
    parser.add_argument(
        "--write-manifest",
        action="store_true",
        help="Also write a small cohort-level manifest CSV.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Delete existing output/database and rebuild.",
    )
    parser.add_argument(
        "--delete-database-after",
        action="store_true",
        help="Delete the working database after successful CSV export.",
    )
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING"],
        default="INFO",
    )
    return parser.parse_args()


def qid(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def qstr(value: str | Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def unique_ordered(values: Iterable[str]) -> list[str]:
    return list(dict.fromkeys(values))


def table_exists(con: duckdb.DuckDBPyConnection, table_name: str) -> bool:
    return bool(
        con.execute(
            """
            SELECT COUNT(*)
            FROM information_schema.tables
            WHERE table_schema = 'main' AND table_name = ?
            """,
            [table_name],
        ).fetchone()[0]
    )


def source_expression(path: Path, sample_size: int) -> str:
    suffixes = "".join(path.suffixes).lower()
    path_sql = qstr(path.resolve())
    if suffixes.endswith(".parquet"):
        return f"read_parquet({path_sql})"
    if suffixes.endswith((".csv", ".csv.gz", ".csv.zst", ".csv.bz2")):
        return (
            f"read_csv_auto({path_sql}, header=true, sample_size={sample_size}, "
            "parallel=true, ignore_errors=false)"
        )
    raise ValueError(f"Unsupported input format: {path}")


def configure_connection(
    con: duckdb.DuckDBPyConnection,
    memory_limit: str,
    threads: int,
    temp_directory: Path,
) -> None:
    temp_directory.mkdir(parents=True, exist_ok=True)
    con.execute(f"SET memory_limit = {qstr(memory_limit)}")
    con.execute(f"SET threads = {int(threads)}")
    con.execute(f"SET temp_directory = {qstr(temp_directory.resolve())}")
    con.execute("SET preserve_insertion_order = false")
    con.execute("SET enable_progress_bar = true")


def discover_columns(con: duckdb.DuckDBPyConnection, source_sql: str) -> list[str]:
    con.execute(f"CREATE OR REPLACE TEMP VIEW source_raw AS SELECT * FROM {source_sql}")
    return [row[0] for row in con.execute("DESCRIBE source_raw").fetchall()]


def validate_args(args: argparse.Namespace) -> None:
    if not args.input.exists():
        raise FileNotFoundError(args.input)
    if args.threads < 1:
        raise ValueError("--threads must be at least 1")
    if args.checkpoint_every < 1:
        raise ValueError("--checkpoint-every must be at least 1")
    if not 1 <= args.cutoff_month <= 12:
        raise ValueError("--cutoff-month must be between 1 and 12")

    one_window_arg = (args.pre_periods is None) != (args.post_periods is None)
    if one_window_arg:
        raise ValueError("Supply --pre-periods and --post-periods together")
    if args.pre_periods is not None:
        if args.pre_periods < 0 or args.post_periods < 0:
            raise ValueError("Pre/post periods must be nonnegative")
    elif args.require_full_window or args.min_pre > 0 or args.min_post > 0:
        raise ValueError(
            "--min-pre, --min-post, and --require-full-window require both "
            "--pre-periods and --post-periods"
        )
    if args.min_pre < 0 or args.min_post < 0:
        raise ValueError("--min-pre and --min-post must be nonnegative")


def choose_columns(
    args: argparse.Namespace,
    source_cols: Sequence[str],
) -> list[str]:
    args.derive_time = args.time_col not in source_cols

    core_required = [
        args.unit_col,
        args.treatment_col,
        args.year_col,
        args.month_col,
    ]
    if not args.derive_time:
        core_required.append(args.time_col)

    missing_core = [c for c in core_required if c not in source_cols]
    if missing_core:
        raise ValueError("Input is missing required columns: " + ", ".join(missing_core))

    if args.keep_all_columns:
        selected = list(source_cols)
    elif args.keep_cols:
        requested = list(args.keep_cols)
        missing_requested = [
            c for c in requested if c not in source_cols and not (c == args.time_col and args.derive_time)
        ]
        if missing_requested:
            raise ValueError(
                "Requested --keep-cols are absent: " + ", ".join(missing_requested)
            )
        selected = requested
    else:
        default_requested = [
            args.unit_col if c == "unique_small_grid_id" else
            args.year_col if c == "year" else
            args.month_col if c == "month" else
            args.time_col if c == "monthyear" else
            args.treatment_col if c == "downup_13kmpl" else c
            for c in R_DEFAULT_COLUMNS
        ]
        missing_defaults = [
            c for c in default_requested
            if c not in source_cols and not (c == args.time_col and args.derive_time)
        ]
        if missing_defaults and not args.allow_missing_default_columns:
            raise ValueError(
                "Input is missing R-script output columns: "
                + ", ".join(missing_defaults)
                + ". Use --allow-missing-default-columns to keep only available columns."
            )
        selected = [
            c for c in default_requested
            if c in source_cols or (c == args.time_col and args.derive_time)
        ]

    required_output = [
        args.unit_col,
        args.year_col,
        args.month_col,
        args.time_col,
        args.treatment_col,
    ]
    return unique_ordered([*selected, *required_output])


def effective_window(args: argparse.Namespace) -> dict | None:
    if args.pre_periods is None:
        return None

    if args.post_definition == "include_event":
        rel_max = args.post_periods - 1
        post_min, post_max = 0, args.post_periods - 1
    else:
        rel_max = args.post_periods
        post_min, post_max = 1, args.post_periods

    min_pre = args.pre_periods if args.require_full_window else args.min_pre
    min_post = args.post_periods if args.require_full_window else args.min_post
    return {
        "rel_min": -args.pre_periods,
        "rel_max": rel_max,
        "pre_min": -args.pre_periods,
        "pre_max": -1,
        "post_min": post_min,
        "post_max": post_max,
        "min_pre": min_pre,
        "min_post": min_post,
    }


def build_config(
    args: argparse.Namespace,
    database_path: Path,
    selected_cols: Sequence[str],
) -> dict:
    stat = args.input.stat()
    return {
        "input": str(args.input.resolve()),
        "input_size": stat.st_size,
        "input_mtime_ns": stat.st_mtime_ns,
        "database": str(database_path.resolve()),
        "unit_col": args.unit_col,
        "treatment_col": args.treatment_col,
        "time_col": args.time_col,
        "year_col": args.year_col,
        "month_col": args.month_col,
        "derive_time": bool(args.derive_time),
        "selected_cols": list(selected_cols),
        "window": effective_window(args),
        "cutoff_year": args.cutoff_year,
        "cutoff_month": args.cutoff_month,
    }


def initialize_database(
    con: duckdb.DuckDBPyConnection,
    args: argparse.Namespace,
    source_sql: str,
    selected_cols: Sequence[str],
    config_json: str,
) -> None:
    logging.info("Importing required columns into the DuckDB working database...")

    select_exprs: list[str] = []
    for col in selected_cols:
        if col == args.time_col:
            if args.derive_time:
                select_exprs.append(
                    f"(TRY_CAST({qid(args.year_col)} AS BIGINT) * 12 + "
                    f"TRY_CAST({qid(args.month_col)} AS BIGINT) - 1) AS {qid(col)}"
                )
            else:
                select_exprs.append(f"TRY_CAST({qid(col)} AS BIGINT) AS {qid(col)}")
        elif col == args.year_col:
            select_exprs.append(f"TRY_CAST({qid(col)} AS INTEGER) AS {qid(col)}")
        elif col == args.month_col:
            select_exprs.append(f"TRY_CAST({qid(col)} AS INTEGER) AS {qid(col)}")
        elif col == args.treatment_col:
            select_exprs.append(f"TRY_CAST({qid(col)} AS TINYINT) AS {qid(col)}")
        else:
            select_exprs.append(qid(col))

    where_parts = [
        f"TRY_CAST({qid(args.month_col)} AS INTEGER) BETWEEN 1 AND 12",
        f"TRY_CAST({qid(args.year_col)} AS INTEGER) IS NOT NULL",
    ]
    if args.cutoff_year is not None:
        year_sql = f"TRY_CAST({qid(args.year_col)} AS INTEGER)"
        month_sql = f"TRY_CAST({qid(args.month_col)} AS INTEGER)"
        where_parts.append(
            f"({year_sql} < {int(args.cutoff_year)} OR "
            f"({year_sql} = {int(args.cutoff_year)} AND "
            f"{month_sql} <= {int(args.cutoff_month)}))"
        )

    con.execute(
        f"""
        CREATE TABLE panel AS
        SELECT {', '.join(select_exprs)}
        FROM {source_sql}
        WHERE {' AND '.join(where_parts)}
        ORDER BY {qid(args.unit_col)}, {qid(args.time_col)}
        """
    )

    if args.derive_time:
        logging.info(
            "Created %s = %s * 12 + %s - 1",
            args.time_col,
            args.year_col,
            args.month_col,
        )
    if args.cutoff_year is not None:
        logging.info(
            "Applied cutoff: year < %s OR (year = %s AND month <= %s)",
            args.cutoff_year,
            args.cutoff_year,
            args.cutoff_month,
        )

    invalid_treatment = con.execute(
        f"""
        SELECT COUNT(*)
        FROM panel
        WHERE {qid(args.treatment_col)} IS NOT NULL
          AND {qid(args.treatment_col)} NOT IN (0, 1)
        """
    ).fetchone()[0]
    if invalid_treatment:
        raise ValueError(
            f"{args.treatment_col} has {invalid_treatment:,} nonmissing values outside 0/1"
        )

    null_time = con.execute(
        f"SELECT COUNT(*) FROM panel WHERE {qid(args.time_col)} IS NULL"
    ).fetchone()[0]
    if null_time:
        raise ValueError(f"Found {null_time:,} rows with missing {args.time_col}")

    duplicate_groups = con.execute(
        f"""
        SELECT COUNT(*)
        FROM (
            SELECT {qid(args.unit_col)}, {qid(args.time_col)}, COUNT(*) AS n
            FROM panel
            GROUP BY {qid(args.unit_col)}, {qid(args.time_col)}
            HAVING COUNT(*) > 1
        )
        """
    ).fetchone()[0]
    if duplicate_groups and not args.allow_duplicate_unit_time:
        raise ValueError(
            f"Found {duplicate_groups:,} duplicated {args.unit_col} x {args.time_col} groups. "
            "The R script assumes one row per grid-month."
        )
    if duplicate_groups:
        logging.warning("Allowing %s duplicate unit-time groups", f"{duplicate_groups:,}")

    unit = qid(args.unit_col)
    time = qid(args.time_col)
    treatment = qid(args.treatment_col)

    logging.info("Computing treatment lags and clean-spell boundaries...")
    con.execute(
        f"""
        CREATE TABLE panel_enriched AS
        SELECT
            *,
            LAG({treatment}) OVER (
                PARTITION BY {unit}
                ORDER BY {time}
            ) AS _treatment_lag,
            MAX(CASE WHEN {treatment} = 1 THEN {time} END) OVER (
                PARTITION BY {unit}
                ORDER BY {time}
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS _prev_one,
            MIN(CASE WHEN {treatment} = 0 THEN {time} END) OVER (
                PARTITION BY {unit}
                ORDER BY {time}
                ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
            ) AS _next_zero,
            MIN(CASE WHEN {treatment} = 1 THEN {time} END) OVER (
                PARTITION BY {unit}
                ORDER BY {time}
                ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
            ) AS _next_one
        FROM panel
        ORDER BY {unit}, {time}
        """
    )
    con.execute("DROP TABLE panel")

    con.execute(
        f"""
        CREATE TABLE switch_events AS
        SELECT
            {unit},
            {time} AS cohort,
            _prev_one AS d_pre,
            _next_zero AS d_post
        FROM panel_enriched
        WHERE _treatment_lag = 0
          AND {treatment} = 1
        """
    )

    con.execute(
        f"""
        CREATE TABLE zero_spells AS
        SELECT DISTINCT
            {unit},
            _prev_one AS d_pre,
            _next_one AS d_post
        FROM panel_enriched
        WHERE {treatment} = 0
        """
    )

    con.execute(
        f"""
        CREATE TABLE unit_summary AS
        SELECT
            {unit},
            MIN({time}) FILTER (WHERE {treatment} = 0) AS min_zero,
            MAX({time}) FILTER (WHERE {treatment} = 1) AS max_one
        FROM panel_enriched
        GROUP BY {unit}
        """
    )

    base_cols = ", ".join(qid(c) for c in selected_cols)
    con.execute(
        f"""
        CREATE TABLE final_stack AS
        SELECT
            {base_cols},
            CAST(NULL AS INTEGER) AS treat,
            CAST(NULL AS BIGINT) AS cohort,
            CAST(NULL AS BIGINT) AS relative_monthyear
        FROM panel_enriched
        WHERE FALSE
        """
    )

    con.execute(
        """
        CREATE TABLE processed_cohorts (
            cohort BIGINT PRIMARY KEY,
            treated_units BIGINT,
            eligible_units BIGINT,
            treated_rows BIGINT,
            control_rows BIGINT,
            total_rows BIGINT,
            processed_at TIMESTAMP
        )
        """
    )
    con.execute("CREATE TABLE pipeline_config (config_json VARCHAR)")
    con.execute("INSERT INTO pipeline_config VALUES (?)", [config_json])

    con.execute("ANALYZE panel_enriched")
    con.execute("ANALYZE switch_events")
    con.execute("ANALYZE zero_spells")
    con.execute("ANALYZE unit_summary")
    con.execute("CHECKPOINT")


def assert_matching_config(con: duckdb.DuckDBPyConnection, expected_json: str) -> None:
    if not table_exists(con, "pipeline_config"):
        raise RuntimeError("Existing database is incompatible; use --overwrite")
    stored = con.execute("SELECT config_json FROM pipeline_config LIMIT 1").fetchone()[0]
    if json.loads(stored) != json.loads(expected_json):
        raise RuntimeError(
            "Existing database was created with different settings. "
            "Use --overwrite or another --database path."
        )


def process_cohort(
    con: duckdb.DuckDBPyConnection,
    args: argparse.Namespace,
    selected_cols: Sequence[str],
    cohort: int,
) -> dict:
    unit = qid(args.unit_col)
    time = qid(args.time_col)
    treatment = qid(args.treatment_col)
    base_cols = ", ".join(f"p.{qid(c)}" for c in selected_cols)
    window = effective_window(args)

    if window is None:
        relative_filter = ""
    else:
        relative_filter = (
            f"AND (p.{time} - {int(cohort)}) BETWEEN "
            f"{int(window['rel_min'])} AND {int(window['rel_max'])}"
        )

    con.execute("BEGIN TRANSACTION")
    try:
        con.execute("DROP TABLE IF EXISTS cohort_events")
        con.execute("DROP TABLE IF EXISTS cohort_rows")
        con.execute("DROP TABLE IF EXISTS eligible_units")

        con.execute(
            f"""
            CREATE TEMP TABLE cohort_events AS
            SELECT e.*, u.min_zero, u.max_one
            FROM switch_events e
            JOIN unit_summary u USING ({unit})
            WHERE e.cohort = {int(cohort)}
            """
        )

        treated_units, t_min, t_max = con.execute(
            "SELECT COUNT(*), MIN(min_zero), MAX(max_one) FROM cohort_events"
        ).fetchone()

        if not treated_units or t_min is None or t_max is None:
            con.execute(
                "INSERT INTO processed_cohorts VALUES (?, ?, 0, 0, 0, 0, ?)",
                [cohort, treated_units or 0, datetime.now(timezone.utc)],
            )
            con.execute("COMMIT")
            return {
                "cohort": cohort,
                "treated_units": treated_units or 0,
                "eligible_units": 0,
                "treated_rows": 0,
                "control_rows": 0,
                "total_rows": 0,
            }

        con.execute(
            f"""
            CREATE TEMP TABLE cohort_rows AS

            -- Treated grids: clean spell around their 0->1 switch.
            SELECT
                {base_cols},
                1::INTEGER AS treat,
                {int(cohort)}::BIGINT AS cohort,
                (p.{time} - {int(cohort)})::BIGINT AS relative_monthyear
            FROM panel_enriched p
            JOIN cohort_events e USING ({unit})
            WHERE p.{time} BETWEEN {int(t_min)} AND {int(t_max)}
              AND (e.d_pre IS NULL OR p.{time} > e.d_pre)
              AND (e.d_post IS NULL OR p.{time} < e.d_post)
              {relative_filter}

            UNION ALL

            -- Controls: zero-treatment spell that covers the cohort month.
            SELECT
                {base_cols},
                0::INTEGER AS treat,
                {int(cohort)}::BIGINT AS cohort,
                (p.{time} - {int(cohort)})::BIGINT AS relative_monthyear
            FROM panel_enriched p
            JOIN zero_spells z USING ({unit})
            WHERE ({int(cohort)} > z.d_pre OR z.d_pre IS NULL)
              AND ({int(cohort)} < z.d_post OR z.d_post IS NULL)
              AND NOT EXISTS (
                    SELECT 1
                    FROM cohort_events e
                    WHERE e.{unit} IS NOT DISTINCT FROM z.{unit}
              )
              AND p.{treatment} = 0
              AND p.{time} BETWEEN {int(t_min)} AND {int(t_max)}
              AND (z.d_pre IS NULL OR p.{time} > z.d_pre)
              AND (z.d_post IS NULL OR p.{time} < z.d_post)
              {relative_filter}
            """
        )

        if window is not None and (window["min_pre"] > 0 or window["min_post"] > 0):
            having_parts: list[str] = []
            if window["min_pre"] > 0:
                having_parts.append(
                    "COUNT(DISTINCT CASE WHEN relative_monthyear BETWEEN "
                    f"{window['pre_min']} AND {window['pre_max']} THEN {time} END) "
                    f">= {window['min_pre']}"
                )
            if window["min_post"] > 0:
                having_parts.append(
                    "COUNT(DISTINCT CASE WHEN relative_monthyear BETWEEN "
                    f"{window['post_min']} AND {window['post_max']} THEN {time} END) "
                    f">= {window['min_post']}"
                )
            con.execute(
                f"""
                CREATE TEMP TABLE eligible_units AS
                SELECT {unit}
                FROM cohort_rows
                GROUP BY {unit}
                HAVING {' AND '.join(having_parts)}
                """
            )
        else:
            con.execute(
                f"CREATE TEMP TABLE eligible_units AS "
                f"SELECT DISTINCT {unit} FROM cohort_rows"
            )

        eligible_units = con.execute("SELECT COUNT(*) FROM eligible_units").fetchone()[0]
        treated_rows, control_rows, total_rows = con.execute(
            f"""
            SELECT
                COUNT(*) FILTER (WHERE cr.treat = 1),
                COUNT(*) FILTER (WHERE cr.treat = 0),
                COUNT(*)
            FROM cohort_rows cr
            JOIN eligible_units eu USING ({unit})
            """
        ).fetchone()

        con.execute(
            f"""
            INSERT INTO final_stack
            SELECT cr.*
            FROM cohort_rows cr
            JOIN eligible_units eu USING ({unit})
            """
        )
        con.execute(
            "INSERT INTO processed_cohorts VALUES (?, ?, ?, ?, ?, ?, ?)",
            [
                cohort,
                treated_units,
                eligible_units,
                treated_rows,
                control_rows,
                total_rows,
                datetime.now(timezone.utc),
            ],
        )
        con.execute("COMMIT")
        return {
            "cohort": cohort,
            "treated_units": treated_units,
            "eligible_units": eligible_units,
            "treated_rows": treated_rows,
            "control_rows": control_rows,
            "total_rows": total_rows,
        }
    except Exception:
        con.execute("ROLLBACK")
        raise
    finally:
        con.execute("DROP TABLE IF EXISTS cohort_events")
        con.execute("DROP TABLE IF EXISTS cohort_rows")
        con.execute("DROP TABLE IF EXISTS eligible_units")


def get_cohorts(con: duckdb.DuckDBPyConnection, args: argparse.Namespace) -> list[int]:
    clauses: list[str] = []
    if args.cohort_min is not None:
        clauses.append(f"cohort >= {int(args.cohort_min)}")
    if args.cohort_max is not None:
        clauses.append(f"cohort <= {int(args.cohort_max)}")
    where = "WHERE " + " AND ".join(clauses) if clauses else ""
    return [
        int(row[0])
        for row in con.execute(
            f"SELECT DISTINCT cohort FROM switch_events {where} ORDER BY cohort"
        ).fetchall()
    ]


def export_manifest(con: duckdb.DuckDBPyConnection, output: Path) -> Path:
    manifest = output.with_name(output.stem + "_manifest.csv")
    rows = con.execute(
        """
        SELECT cohort, treated_units, eligible_units, treated_rows,
               control_rows, total_rows, processed_at
        FROM processed_cohorts
        ORDER BY cohort
        """
    ).fetchall()
    with manifest.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "cohort",
                "treated_units",
                "eligible_units",
                "treated_rows",
                "control_rows",
                "total_rows",
                "processed_at",
            ]
        )
        writer.writerows(rows)
    return manifest


def export_final_csv(
    con: duckdb.DuckDBPyConnection,
    args: argparse.Namespace,
    selected_cols: Sequence[str],
) -> None:
    output_cols = [*selected_cols, "treat", "cohort", "relative_monthyear"]
    selected = ", ".join(qid(c) for c in output_cols)
    order_sql = ""
    if args.sort_final:
        order_sql = (
            f" ORDER BY cohort, {qid(args.unit_col)}, {qid(args.time_col)}"
        )

    compression_sql = ""
    if args.compression != "none":
        compression_sql = f", COMPRESSION {args.compression}"

    con.execute(
        f"""
        COPY (
            SELECT {selected}
            FROM final_stack
            {order_sql}
        )
        TO {qstr(args.output.resolve())}
        (FORMAT CSV, HEADER true{compression_sql})
        """
    )


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s | %(levelname)s | %(message)s",
    )
    validate_args(args)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    database_path = args.database or args.output.with_suffix(".duckdb")
    database_path.parent.mkdir(parents=True, exist_ok=True)
    temp_directory = args.temp_directory or database_path.parent / "duckdb_temp_13kmpl"

    if args.overwrite:
        if database_path.exists():
            database_path.unlink()
        if args.output.exists():
            args.output.unlink()
        manifest = args.output.with_name(args.output.stem + "_manifest.csv")
        if manifest.exists():
            manifest.unlink()
    elif args.output.exists():
        logging.info("Existing final CSV will be replaced: %s", args.output)
        args.output.unlink()

    source_sql = source_expression(args.input, args.csv_sample_size)
    con = duckdb.connect(str(database_path))
    try:
        configure_connection(
            con,
            memory_limit=args.memory_limit,
            threads=args.threads,
            temp_directory=temp_directory,
        )
        source_cols = discover_columns(con, source_sql)
        selected_cols = choose_columns(args, source_cols)
        config = build_config(args, database_path, selected_cols)
        config_json = json.dumps(config, sort_keys=True)

        if table_exists(con, "pipeline_config"):
            assert_matching_config(con, config_json)
            logging.info("Resuming compatible database: %s", database_path)
        else:
            initialize_database(con, args, source_sql, selected_cols, config_json)

        total_rows = con.execute("SELECT COUNT(*) FROM panel_enriched").fetchone()[0]
        unique_units = con.execute(
            f"SELECT COUNT(DISTINCT {qid(args.unit_col)}) FROM panel_enriched"
        ).fetchone()[0]
        cohorts = get_cohorts(con, args)
        processed = {
            int(row[0])
            for row in con.execute("SELECT cohort FROM processed_cohorts").fetchall()
        }
        pending = [c for c in cohorts if c not in processed]

        logging.info("Stored panel rows: %s", f"{total_rows:,}")
        logging.info("Unique grids: %s", f"{unique_units:,}")
        logging.info("Detected cohorts: %s", f"{len(cohorts):,}")
        logging.info("Pending cohorts: %s", f"{len(pending):,}")
        logging.info("Treatment variable: %s", args.treatment_col)
        logging.info("Working database: %s", database_path)

        for index, cohort in enumerate(pending, start=1):
            result = process_cohort(con, args, selected_cols, cohort)
            logging.info(
                "Cohort %s (%s/%s): %s rows; %s eligible grids",
                cohort,
                index,
                len(pending),
                f"{result['total_rows']:,}",
                f"{result['eligible_units']:,}",
            )
            if index % args.checkpoint_every == 0:
                con.execute("CHECKPOINT")

        con.execute("CHECKPOINT")
        final_rows = con.execute("SELECT COUNT(*) FROM final_stack").fetchone()[0]
        logging.info("Exporting final CSV with %s rows...", f"{final_rows:,}")
        export_final_csv(con, args, selected_cols)
        manifest = export_manifest(con, args.output) if args.write_manifest else None
        con.execute("CHECKPOINT")

        logging.info("Final CSV: %s", args.output)
        if manifest:
            logging.info("Manifest: %s", manifest)
        logging.info("Working database: %s", database_path)
    finally:
        con.close()

    if args.delete_database_after and database_path.exists():
        database_path.unlink()
        shutil.rmtree(temp_directory, ignore_errors=True)
        logging.info("Deleted working database: %s", database_path)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        logging.error("Interrupted. Re-run the same command to resume completed cohorts.")
        raise SystemExit(130)
    except Exception as exc:
        logging.exception("Pipeline failed: %s", exc)
        raise SystemExit(1)

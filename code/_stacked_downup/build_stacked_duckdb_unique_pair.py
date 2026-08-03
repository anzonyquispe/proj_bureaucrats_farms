#!/usr/bin/env python3
"""Build stacked neighbour-treatment event-study data with DuckDB.

The pipeline is designed for large CSV/Parquet inputs and low RAM use:

1. Import only required columns into one disk-backed DuckDB database.
2. Precompute treatment switches and clean zero-treatment spells once.
3. Process cohorts sequentially with SQL that can spill to disk.
4. Append every cohort to one table inside the database.
5. Export one final CSV; no per-cohort DTA/CSV files are created.

The script creates a numeric unique_pair identifier from:
    unique_small_grid_id + ac_uq_id_neighbor

The default panel unit is this generated unique_pair. The source identifiers are
also retained in the final output.

Window conventions
------------------
With --pre-periods 6 --post-periods 6:

* --post-definition include_event retains relative periods -6,...,-1,0,...,5.
  Event time 0 counts as the first post-treatment period.

* --post-definition after_event retains relative periods -6,...,-1,0,...,6.
  Event time 0 is retained, while +1,...,+6 count as post periods.
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
    raise SystemExit(
        "DuckDB is required. Install it with: pip install duckdb"
    ) from exc


DEFAULT_KEEP_COLS = [
    "unique_pair",
    "unique_small_grid_id",
    "month",
    "year",
    "monthyear",
    "province",
    "ac_uq_id",
    "ac_uq_id_neighbor",
    "downwind_neighbours",
    "count",
    "av_wind_speed",
    "wind_direction",
    "dist_q",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build one stacked event-study CSV using disk-backed DuckDB.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--input",
        required=True,
        type=Path,
        help="Input CSV, CSV.GZ, CSV.ZST, or Parquet file.",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Final output CSV path. No per-cohort files are written.",
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=None,
        help="Working DuckDB file. Defaults to OUTPUT with a .duckdb suffix.",
    )
    parser.add_argument(
        "--treatment-col",
        default="downwind_neighbours",
        help="Binary 0/1 treatment used to detect 0 -> 1 switches.",
    )
    parser.add_argument(
        "--time-col",
        default="monthyear",
        help=(
            "Integer, consecutive panel-time variable. If absent, it is created "
            "automatically from --year-col and --month-col."
        ),
    )
    parser.add_argument(
        "--year-col",
        default="year",
        help="Year column used when --time-col is absent.",
    )
    parser.add_argument(
        "--month-col",
        default="month",
        help="Month column (1-12) used when --time-col is absent.",
    )
    parser.add_argument(
        "--pair-cols",
        nargs=2,
        default=["unique_small_grid_id", "ac_uq_id_neighbor"],
        metavar=("GRID_COL", "NEIGHBOR_COL"),
        help="Two source columns whose distinct combinations define unique_pair.",
    )
    parser.add_argument(
        "--pair-id-col",
        default="unique_pair",
        help="Name of the generated numeric grid-neighbor identifier.",
    )
    parser.add_argument(
        "--unit-cols",
        nargs="+",
        default=["unique_pair"],
        help="Columns defining one panel unit. By default, use generated unique_pair.",
    )
    parser.add_argument(
        "--dist-col",
        default="dist_q",
        help="Distance-quantile column that must be retained in the final output.",
    )
    parser.add_argument(
        "--cutoff-year",
        type=int,
        default=2022,
        help="Keep years below this value and months through --cutoff-month in this year.",
    )
    parser.add_argument(
        "--cutoff-month",
        type=int,
        default=8,
        help="Last retained month in --cutoff-year.",
    )
    parser.add_argument("--pre-periods", type=int, default=6)
    parser.add_argument("--post-periods", type=int, default=6)
    parser.add_argument(
        "--post-definition",
        choices=["include_event", "after_event"],
        default="include_event",
    )
    parser.add_argument(
        "--min-pre",
        type=int,
        default=0,
        help="Minimum distinct pre-treatment periods required per stacked unit.",
    )
    parser.add_argument(
        "--min-post",
        type=int,
        default=0,
        help="Minimum distinct post-treatment periods required per stacked unit.",
    )
    parser.add_argument(
        "--require-full-window",
        action="store_true",
        help="Require every requested pre and post period.",
    )
    parser.add_argument(
        "--keep-cols",
        nargs="*",
        default=None,
        help="Columns retained in the output. Required columns are added automatically.",
    )
    parser.add_argument(
        "--keep-all-columns",
        action="store_true",
        help="Retain every source column. This increases database size and execution time.",
    )
    parser.add_argument(
        "--memory-limit",
        default="8GB",
        help="Maximum RAM available to DuckDB, for example 4GB or 12000MB.",
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
        help="Rows sampled by DuckDB to infer CSV types; -1 scans the full file.",
    )
    parser.add_argument(
        "--cohort-min",
        type=int,
        default=None,
        help="Optional earliest cohort value.",
    )
    parser.add_argument(
        "--cohort-max",
        type=int,
        default=None,
        help="Optional latest cohort value.",
    )
    parser.add_argument(
        "--checkpoint-every",
        type=int,
        default=25,
        help="Checkpoint the DuckDB database after this many cohorts.",
    )
    parser.add_argument(
        "--compression",
        choices=["none", "gzip", "zstd"],
        default="none",
        help="Compression for the final CSV. Use .csv.gz or .csv.zst accordingly.",
    )
    parser.add_argument(
        "--sort-final",
        action="store_true",
        help="Sort final CSV by cohort, unit, and time. Sorting can substantially increase runtime.",
    )
    parser.add_argument(
        "--write-manifest",
        action="store_true",
        help="Also export a small cohort-level manifest CSV. By default only the final CSV and DuckDB file are kept.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Delete an existing database/output and rebuild from the beginning.",
    )
    parser.add_argument(
        "--delete-database-after",
        action="store_true",
        help="Delete the working .duckdb file after the final CSV is exported.",
    )
    parser.add_argument(
        "--allow-duplicate-unit-time",
        action="store_true",
        help="Allow duplicate unit-time rows. This is not recommended.",
    )
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING"],
        default="INFO",
    )
    return parser.parse_args()


def qid(name: str) -> str:
    """Quote a SQL identifier safely."""
    return '"' + name.replace('"', '""') + '"'


def qstr(value: str | Path) -> str:
    """Quote a SQL string literal safely."""
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


def source_expression(path: Path, csv_sample_size: int) -> str:
    suffixes = "".join(path.suffixes).lower()
    path_sql = qstr(path.resolve())
    if suffixes.endswith(".parquet"):
        return f"read_parquet({path_sql})"
    if suffixes.endswith((".csv", ".csv.gz", ".csv.zst", ".csv.bz2")):
        return (
            f"read_csv_auto({path_sql}, header = true, "
            f"sample_size = {csv_sample_size}, parallel = true)"
        )
    raise ValueError(
        f"Unsupported input format for {path}. Use CSV, compressed CSV, or Parquet."
    )


def configure_connection(
    con: duckdb.DuckDBPyConnection,
    *,
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


def discover_columns(
    con: duckdb.DuckDBPyConnection,
    source_sql: str,
) -> list[str]:
    con.execute(f"CREATE OR REPLACE TEMP VIEW source_raw AS SELECT * FROM {source_sql}")
    return [row[0] for row in con.execute("DESCRIBE source_raw").fetchall()]


def choose_columns(args: argparse.Namespace, source_cols: Sequence[str]) -> list[str]:
    """Validate source columns and determine final retained columns."""
    args.derive_time_from_year_month = args.time_col not in source_cols

    # unique_pair is generated by this script, so it must not collide with a source column.
    if args.pair_id_col in source_cols:
        logging.warning(
            "Source already contains %s; it will be replaced by a freshly generated ID.",
            args.pair_id_col,
        )

    required_source = unique_ordered([
        *args.pair_cols,
        args.treatment_col,
        args.year_col,
        args.month_col,
        args.dist_col,
    ])
    if not args.derive_time_from_year_month:
        required_source.append(args.time_col)

    missing = [col for col in required_source if col not in source_cols]
    if missing:
        raise ValueError("Input is missing required columns: " + ", ".join(missing))

    generated_cols = {args.pair_id_col}
    if args.derive_time_from_year_month:
        generated_cols.add(args.time_col)

    if args.keep_all_columns:
        selected = [col for col in source_cols if col != args.pair_id_col]
    elif args.keep_cols:
        missing_keep = [
            col for col in args.keep_cols
            if col not in source_cols and col not in generated_cols
        ]
        if missing_keep:
            raise ValueError(
                "Requested --keep-cols are absent: " + ", ".join(missing_keep)
            )
        selected = [col for col in args.keep_cols if col != args.pair_id_col]
    else:
        selected = [
            col for col in DEFAULT_KEEP_COLS
            if col in source_cols or col in generated_cols
        ]

    # Always retain the generated pair ID, original pair columns, calendar columns,
    # treatment, time index, and dist_q (or the name supplied with --dist-col).
    required_output = [
        args.pair_id_col,
        *args.pair_cols,
        *args.unit_cols,
        args.treatment_col,
        args.time_col,
        args.year_col,
        args.month_col,
        args.dist_col,
    ]

    return unique_ordered([*selected, *required_output])

def build_config(
    args: argparse.Namespace,
    database_path: Path,
    selected_cols: Sequence[str],
) -> dict:
    stat = args.input.stat()
    min_pre = args.pre_periods if args.require_full_window else args.min_pre
    min_post = args.post_periods if args.require_full_window else args.min_post
    return {
        "input": str(args.input.resolve()),
        "input_size": stat.st_size,
        "input_mtime_ns": stat.st_mtime_ns,
        "database": str(database_path.resolve()),
        "treatment_col": args.treatment_col,
        "time_col": args.time_col,
        "year_col": args.year_col,
        "month_col": args.month_col,
        "derive_time_from_year_month": bool(args.derive_time_from_year_month),
        "pair_cols": list(args.pair_cols),
        "pair_id_col": args.pair_id_col,
        "unit_cols": list(args.unit_cols),
        "dist_col": args.dist_col,
        "cutoff_year": args.cutoff_year,
        "cutoff_month": args.cutoff_month,
        "selected_cols": list(selected_cols),
        "pre_periods": args.pre_periods,
        "post_periods": args.post_periods,
        "post_definition": args.post_definition,
        "min_pre": min_pre,
        "min_post": min_post,
        "cohort_min": args.cohort_min,
        "cohort_max": args.cohort_max,
    }


def validate_args(args: argparse.Namespace) -> None:
    if not args.input.exists():
        raise FileNotFoundError(args.input)
    if args.pre_periods < 0 or args.post_periods < 0:
        raise ValueError("--pre-periods and --post-periods must be nonnegative.")
    if args.min_pre < 0 or args.min_post < 0:
        raise ValueError("--min-pre and --min-post must be nonnegative.")
    if args.threads < 1:
        raise ValueError("--threads must be at least 1.")
    if args.checkpoint_every < 1:
        raise ValueError("--checkpoint-every must be at least 1.")
    if not 1 <= args.cutoff_month <= 12:
        raise ValueError("--cutoff-month must be between 1 and 12.")


def initialize_database(
    con: duckdb.DuckDBPyConnection,
    args: argparse.Namespace,
    source_sql: str,
    selected_cols: Sequence[str],
    config_json: str,
) -> None:
    logging.info("Importing selected source columns into DuckDB...")

    select_exprs: list[str] = []
    for col in selected_cols:
        if col == args.pair_id_col:
            pair_order = ", ".join(qid(c) for c in args.pair_cols)
            select_exprs.append(
                f"CAST(DENSE_RANK() OVER (ORDER BY {pair_order}) AS BIGINT) AS {qid(col)}"
            )
        elif col == args.time_col:
            if args.derive_time_from_year_month:
                # Consecutive monthly index. Do NOT use YYYYMM because 202201-202112 != 1.
                select_exprs.append(
                    f"(CAST({qid(args.year_col)} AS BIGINT) * 12 + "
                    f"CAST({qid(args.month_col)} AS BIGINT) - 1) AS {qid(col)}"
                )
            else:
                select_exprs.append(f"CAST({qid(col)} AS BIGINT) AS {qid(col)}")
        elif col == args.treatment_col:
            select_exprs.append(f"CAST({qid(col)} AS TINYINT) AS {qid(col)}")
        else:
            select_exprs.append(qid(col))

    unit_time_order = ", ".join(qid(c) for c in [*args.unit_cols, args.time_col])
    year_sql = f"TRY_CAST({qid(args.year_col)} AS INTEGER)"
    month_sql = f"TRY_CAST({qid(args.month_col)} AS INTEGER)"
    cutoff_sql = (
        f"({year_sql} < {int(args.cutoff_year)} OR "
        f"({year_sql} = {int(args.cutoff_year)} AND "
        f"{month_sql} <= {int(args.cutoff_month)}))"
    )
    con.execute(
        f"""
        CREATE TABLE panel AS
        WITH filtered_source AS (
            SELECT *
            FROM {source_sql}
            WHERE {cutoff_sql}
        )
        SELECT {', '.join(select_exprs)}
        FROM filtered_source
        ORDER BY {unit_time_order}
        """
    )
    logging.info(
        "Applied sample cutoff: year < %s OR (year = %s AND month <= %s).",
        args.cutoff_year,
        args.cutoff_year,
        args.cutoff_month,
    )

    if args.derive_time_from_year_month:
        invalid_calendar = con.execute(
            f"""
            SELECT COUNT(*)
            FROM panel
            WHERE {qid(args.year_col)} IS NULL
               OR {qid(args.month_col)} IS NULL
               OR TRY_CAST({qid(args.month_col)} AS INTEGER) NOT BETWEEN 1 AND 12
            """
        ).fetchone()[0]
        if invalid_calendar:
            raise ValueError(
                f"Found {invalid_calendar:,} rows with missing year/month or month outside 1-12."
            )
        logging.info(
            "Created %s internally as year * 12 + month - 1.",
            args.time_col,
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
            f"{args.treatment_col!r} contains {invalid_treatment:,} nonmissing values outside 0/1."
        )

    null_time = con.execute(
        f"SELECT COUNT(*) FROM panel WHERE {qid(args.time_col)} IS NULL"
    ).fetchone()[0]
    if null_time:
        raise ValueError(
            f"{args.time_col!r} contains {null_time:,} missing values."
        )

    group_cols = ", ".join(qid(c) for c in [*args.unit_cols, args.time_col])
    duplicate_groups = con.execute(
        f"""
        SELECT COUNT(*)
        FROM (
            SELECT {group_cols}, COUNT(*) AS n
            FROM panel
            GROUP BY {group_cols}
            HAVING COUNT(*) > 1
        )
        """
    ).fetchone()[0]
    if duplicate_groups and not args.allow_duplicate_unit_time:
        raise ValueError(
            f"Found {duplicate_groups:,} duplicated unit-time combinations. "
            "For neighbour treatment, normally use the generated --unit-cols unique_pair."
        )
    if duplicate_groups:
        logging.warning("Allowing %s duplicated unit-time groups", f"{duplicate_groups:,}")

    partition = ", ".join(qid(c) for c in args.unit_cols)
    time_col = qid(args.time_col)
    treatment = qid(args.treatment_col)

    logging.info("Precomputing lags and clean treatment-spell boundaries...")
    con.execute(
        f"""
        CREATE TABLE panel_enriched AS
        SELECT
            *,
            LAG({treatment}) OVER (
                PARTITION BY {partition}
                ORDER BY {time_col}
            ) AS _treatment_lag,
            MAX(CASE WHEN {treatment} = 1 THEN {time_col} END) OVER (
                PARTITION BY {partition}
                ORDER BY {time_col}
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS _prev_one,
            MIN(CASE WHEN {treatment} = 0 THEN {time_col} END) OVER (
                PARTITION BY {partition}
                ORDER BY {time_col}
                ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
            ) AS _next_zero,
            MIN(CASE WHEN {treatment} = 1 THEN {time_col} END) OVER (
                PARTITION BY {partition}
                ORDER BY {time_col}
                ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
            ) AS _next_one
        FROM panel
        ORDER BY {unit_time_order}
        """
    )
    con.execute("DROP TABLE panel")

    units = ", ".join(qid(c) for c in args.unit_cols)
    con.execute(
        f"""
        CREATE TABLE switch_events AS
        SELECT
            {units},
            {time_col} AS cohort,
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
            {units},
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
            {units},
            MIN({time_col}) FILTER (WHERE {treatment} = 0) AS min_zero,
            MAX({time_col}) FILTER (WHERE {treatment} = 1) AS max_one
        FROM panel_enriched
        GROUP BY {units}
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


def assert_matching_config(
    con: duckdb.DuckDBPyConnection,
    expected_json: str,
) -> None:
    if not table_exists(con, "pipeline_config"):
        raise RuntimeError(
            "The existing database is not a compatible stacked-data database. "
            "Use --overwrite or choose another --database path."
        )
    stored = con.execute("SELECT config_json FROM pipeline_config LIMIT 1").fetchone()[0]
    if json.loads(stored) != json.loads(expected_json):
        raise RuntimeError(
            "The existing database was created with different input or settings. "
            "Use --overwrite or choose another --database path."
        )


def relative_window(args: argparse.Namespace) -> tuple[int, int, int, int, int, int, int, int]:
    rel_min = -args.pre_periods
    if args.post_definition == "include_event":
        rel_max = args.post_periods - 1
        post_count_min = 0
        post_count_max = args.post_periods - 1
    else:
        rel_max = args.post_periods
        post_count_min = 1
        post_count_max = args.post_periods

    min_pre = args.pre_periods if args.require_full_window else args.min_pre
    min_post = args.post_periods if args.require_full_window else args.min_post
    return rel_min, rel_max, -args.pre_periods, -1, post_count_min, post_count_max, min_pre, min_post


def same_unit(left: str, right: str, unit_cols: Sequence[str]) -> str:
    return " AND ".join(
        f"{left}.{qid(col)} IS NOT DISTINCT FROM {right}.{qid(col)}"
        for col in unit_cols
    )


def process_cohort(
    con: duckdb.DuckDBPyConnection,
    args: argparse.Namespace,
    selected_cols: Sequence[str],
    cohort: int,
) -> dict:
    units = ", ".join(qid(c) for c in args.unit_cols)
    using_units = ", ".join(qid(c) for c in args.unit_cols)
    time_col = qid(args.time_col)
    treatment = qid(args.treatment_col)
    base_cols_p = ", ".join(f"p.{qid(c)}" for c in selected_cols)

    rel_min, rel_max, pre_min, pre_max, post_min, post_max, min_pre, min_post = relative_window(args)

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
            JOIN unit_summary u USING ({using_units})
            WHERE e.cohort = {int(cohort)}
            """
        )

        treated_units, t_min, t_max = con.execute(
            """
            SELECT COUNT(*), MIN(min_zero), MAX(max_one)
            FROM cohort_events
            """
        ).fetchone()

        if not treated_units or t_min is None or t_max is None:
            con.execute(
                """
                INSERT INTO processed_cohorts
                VALUES (?, ?, 0, 0, 0, 0, ?)
                """,
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

        unit_not_in_treated = same_unit("e", "z", args.unit_cols)

        con.execute(
            f"""
            CREATE TEMP TABLE cohort_rows AS
            SELECT
                {base_cols_p},
                1::INTEGER AS treat,
                {int(cohort)}::BIGINT AS cohort,
                (p.{time_col} - {int(cohort)})::BIGINT AS relative_monthyear
            FROM panel_enriched p
            JOIN cohort_events e USING ({using_units})
            WHERE p.{time_col} BETWEEN {int(t_min)} AND {int(t_max)}
              AND (e.d_pre IS NULL OR p.{time_col} > e.d_pre)
              AND (e.d_post IS NULL OR p.{time_col} < e.d_post)
              AND (p.{time_col} - {int(cohort)}) BETWEEN {int(rel_min)} AND {int(rel_max)}

            UNION ALL

            SELECT
                {base_cols_p},
                0::INTEGER AS treat,
                {int(cohort)}::BIGINT AS cohort,
                (p.{time_col} - {int(cohort)})::BIGINT AS relative_monthyear
            FROM panel_enriched p
            JOIN zero_spells z USING ({using_units})
            WHERE ({int(cohort)} > z.d_pre OR z.d_pre IS NULL)
              AND ({int(cohort)} < z.d_post OR z.d_post IS NULL)
              AND NOT EXISTS (
                    SELECT 1
                    FROM cohort_events e
                    WHERE {unit_not_in_treated}
              )
              AND p.{treatment} = 0
              AND p.{time_col} BETWEEN {int(t_min)} AND {int(t_max)}
              AND (z.d_pre IS NULL OR p.{time_col} > z.d_pre)
              AND (z.d_post IS NULL OR p.{time_col} < z.d_post)
              AND (p.{time_col} - {int(cohort)}) BETWEEN {int(rel_min)} AND {int(rel_max)}
            """
        )

        if min_pre > 0 or min_post > 0:
            having_parts: list[str] = []
            if min_pre > 0:
                having_parts.append(
                    f"COUNT(DISTINCT CASE WHEN relative_monthyear BETWEEN {pre_min} AND {pre_max} "
                    f"THEN {time_col} END) >= {min_pre}"
                )
            if min_post > 0:
                if post_min <= post_max:
                    having_parts.append(
                        f"COUNT(DISTINCT CASE WHEN relative_monthyear BETWEEN {post_min} AND {post_max} "
                        f"THEN {time_col} END) >= {min_post}"
                    )
                else:
                    having_parts.append("0 >= " + str(min_post))

            con.execute(
                f"""
                CREATE TEMP TABLE eligible_units AS
                SELECT {units}
                FROM cohort_rows
                GROUP BY {units}
                HAVING {' AND '.join(having_parts)}
                """
            )
        else:
            con.execute(
                f"""
                CREATE TEMP TABLE eligible_units AS
                SELECT DISTINCT {units}
                FROM cohort_rows
                """
            )

        eligible_units = con.execute("SELECT COUNT(*) FROM eligible_units").fetchone()[0]
        treated_rows, control_rows, total_rows = con.execute(
            f"""
            SELECT
                COUNT(*) FILTER (WHERE cr.treat = 1),
                COUNT(*) FILTER (WHERE cr.treat = 0),
                COUNT(*)
            FROM cohort_rows cr
            JOIN eligible_units eu USING ({using_units})
            """
        ).fetchone()

        con.execute(
            f"""
            INSERT INTO final_stack
            SELECT cr.*
            FROM cohort_rows cr
            JOIN eligible_units eu USING ({using_units})
            """
        )
        con.execute(
            """
            INSERT INTO processed_cohorts
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
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
        order_cols = ["cohort", *args.unit_cols, args.time_col]
        order_sql = " ORDER BY " + ", ".join(qid(c) for c in order_cols)

    compression = ""
    if args.compression != "none":
        compression = f", COMPRESSION {args.compression}"

    con.execute(
        f"""
        COPY (
            SELECT {selected}
            FROM final_stack
            {order_sql}
        )
        TO {qstr(args.output.resolve())}
        (FORMAT CSV, HEADER true{compression})
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
    temp_directory = args.temp_directory or database_path.parent / "duckdb_temp"

    if args.overwrite:
        if database_path.exists():
            database_path.unlink()
        if args.output.exists():
            args.output.unlink()
        manifest = args.output.with_name(args.output.stem + "_manifest.csv")
        if manifest.exists():
            manifest.unlink()
    elif args.output.exists():
        logging.info("Existing final CSV will be replaced after processing completes: %s", args.output)
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
            "SELECT COUNT(*) FROM (SELECT DISTINCT "
            + ", ".join(qid(c) for c in args.unit_cols)
            + " FROM panel_enriched)"
        ).fetchone()[0]
        cohorts = get_cohorts(con, args)
        processed = {
            int(row[0])
            for row in con.execute("SELECT cohort FROM processed_cohorts").fetchall()
        }
        pending = [cohort for cohort in cohorts if cohort not in processed]

        logging.info("Input rows stored: %s", f"{total_rows:,}")
        logging.info("Unique panel units: %s", f"{unique_units:,}")
        logging.info("Detected cohorts: %s", f"{len(cohorts):,}")
        logging.info("Pending cohorts: %s", f"{len(pending):,}")
        logging.info("DuckDB database: %s", database_path)
        logging.info("Spill directory: %s", temp_directory)

        for index, cohort in enumerate(pending, start=1):
            result = process_cohort(con, args, selected_cols, cohort)
            logging.info(
                "Cohort %s (%s/%s): %s rows; %s eligible units",
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
        logging.info("Exporting one final CSV with %s rows...", f"{final_rows:,}")
        export_final_csv(con, args, selected_cols)
        manifest_path = export_manifest(con, args.output) if args.write_manifest else None
        con.execute("CHECKPOINT")

        logging.info("Final CSV: %s", args.output)
        if manifest_path is not None:
            logging.info("Manifest: %s", manifest_path)
        logging.info("Working database: %s", database_path)
    finally:
        con.close()

    if args.delete_database_after and database_path.exists():
        database_path.unlink()
        logging.info("Deleted working database: %s", database_path)
        if temp_directory.exists():
            shutil.rmtree(temp_directory, ignore_errors=True)

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

#!/usr/bin/env python3
"""Build the MODIS T-2 fire baseline for the politician-characteristics stack.

The politician event study can be expressed against ``T-2``, the electoral term
before the control term, by netting each observation against its own grid's
fire level in that term. ``T-2`` never enters the estimation window; it only
supplies the baseline. That is what makes this possible without restricting the
sample: a lookup table is enough, so no stack has to be rebuilt and no unit has
to be dropped.

Why MODIS only
--------------
``count`` is a raw detection count, so it scales with how many instruments are
observing. MODIS runs from 2000, VIIRS only from 2012, so a baseline drawn from
the combined series would be measured on a different scale for old cohorts than
for recent ones. A single-instrument baseline is comparable across all of them.

The baseline window
-------------------
``[control_term_start - 60, control_term_start - 1]``: the 60 months before the
control term opens.

The real ``T-2`` boundaries are not recoverable for the early cohorts, because
the electoral calendar is derived from the master and those terms ended before
the master begins in 2012-09. The arithmetic window is preferable anyway:

* 60 months is exactly 5 years, so every baseline month lands on the same
  CALENDAR month. Real electoral spacing is irregular (61 months between the
  first two elections, 60 between the next two) and using it would compare
  October against September in a series dominated by October-November burning.
* It is the same length for every cohort, so every grid-cohort gets exactly 5
  observations per calendar month. The two-cycle stack gave 26, 39 or 55 months
  depending on the cohort.
* It needs only ``control_term_start``, which is derivable for all eight
  cohorts because the control term always has months inside the master.

Months with no detection are absent from the MODIS grid, so the window is
expanded per unit and LEFT JOINed: a month without fire enters as zero. Taking
the average over matched rows only would overstate the baseline, and would do so
in proportion to how fire-prone the grid is.
"""

from __future__ import annotations

import argparse
import logging
import os
from pathlib import Path
from typing import Sequence

import duckdb

from _stacked_duckdb_core import configure_connection, qid, qstr, source_expression
from build_all_stacked_datasets_duckdb import CLUSTER_INTERMEDIATE, LOCAL_INTERMEDIATE

# The electoral calendar and the unit-to-control-term match are imported rather
# than copied: this table must describe exactly the same terms the stacked
# datasets describe, and two near-identical copies would drift silently.
from build_politicians_characteristics_2cycles import (
    build_ac_terms,
    build_unit_windows,
    check_source_freshness,
    cohort_key,
    relation_columns,
    require_columns,
    scalar,
)


SOURCE_DATABASE = "politicians_characteristics_byprov.db"
SOURCE_VIEW = "final_stack"
OUTPUT_STEM = "politicians_characteristics_byprov_t2_baseline"
PANEL_STEM = "politicians_characteristics_byprov_modis_panel"
BASELINE_MONTHS = 60
MONTHS_PER_CALENDAR_MONTH = BASELINE_MONTHS // 12

STATA_VARIABLE_LABELS = {
    "unique_small_grid_id": "5 km grid identifier",
    "cohort_id": "Province-election cohort identifier",
    "month": "Calendar month (1-12)",
    "t2_count_modis": "Mean MODIS fire count in that calendar month of T-2",
    "t2_window_start": "First month of the T-2 baseline window",
    "t2_window_end": "Last month of the T-2 baseline window",
}

PANEL_VARIABLE_LABELS = {
    "unique_small_grid_id": "5 km grid identifier",
    "year": "Calendar year",
    "month": "Calendar month (1-12)",
    "count_modis": "MODIS-only fire detections in that grid-month",
}


def default_intermediate() -> Path:
    return LOCAL_INTERMEDIATE if LOCAL_INTERMEDIATE.exists() else CLUSTER_INTERMEDIATE


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--intermediate", type=Path, default=default_intermediate())
    parser.add_argument(
        "--input",
        type=Path,
        default=None,
        help="Master Parquet/CSV; defaults to INTERMEDIATE/0_master_dataset.parquet.",
    )
    parser.add_argument(
        "--modis-grid",
        type=Path,
        default=None,
        help=(
            "MODIS-only fire grid; defaults to INTERMEDIATE/_3_fire_grid_MODIS_only.csv, "
            "written by build_fire_grid_duckdb_modis_only.py."
        ),
    )
    parser.add_argument(
        "--source-database",
        type=Path,
        default=None,
        help="Source politician stack; defaults to INTERMEDIATE/" + SOURCE_DATABASE,
    )
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--database", type=Path, default=None)
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument("--memory-limit", default="90GB")
    parser.add_argument("--csv-sample-size", type=int, default=100_000)
    parser.add_argument(
        "--baseline-months",
        type=int,
        default=BASELINE_MONTHS,
        help=(
            "Length of the baseline window. Keep it a multiple of 12 or the "
            "calendar-month alignment the design relies on is lost."
        ),
    )
    parser.add_argument(
        "--allow-stale-source",
        action="store_true",
        help="Skip the check that the source stack is newer than the master.",
    )
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument(
        "--log-level", choices=["DEBUG", "INFO", "WARNING"], default="INFO"
    )
    args = parser.parse_args(argv)
    if args.threads < 1:
        parser.error("--threads must be positive.")
    if args.baseline_months < 12:
        parser.error("--baseline-months must cover at least one year.")
    if args.baseline_months % 12:
        parser.error(
            "--baseline-months must be a multiple of 12 so that every calendar "
            "month gets the same number of baseline observations."
        )
    return args


def source_grid_type(
    connection: duckdb.DuckDBPyConnection, source_relation: str
) -> str:
    """Declared type of the stack's grid id, so the fire grid can match it.

    The published stacks store it as an integer, but the key only has to be
    consistent between the two sides of the join, so the type is read rather
    than assumed.
    """

    for row in connection.execute(f"DESCRIBE SELECT * FROM {source_relation}").fetchall():
        if str(row[0]) == "unique_small_grid_id":
            return str(row[1])
    raise ValueError(f"{source_relation} has no unique_small_grid_id column.")


def load_modis_grid(
    connection: duckdb.DuckDBPyConnection,
    modis_path: Path,
    csv_sample_size: int,
    grid_type: str,
) -> None:
    """Create ``modis_grid``: MODIS fire counts keyed by grid and month index."""

    relation = source_expression(modis_path, csv_sample_size)
    columns = relation_columns(connection, relation)
    require_columns(
        columns,
        ("unique_small_grid_id", "year", "month", "count"),
        f"MODIS fire grid {modis_path.name}",
    )
    connection.execute(
        f"""
        CREATE TEMP TABLE modis_grid AS
        SELECT
            CAST(unique_small_grid_id AS {grid_type}) AS unique_small_grid_id,
            CAST(year AS BIGINT) * 12 + CAST(month AS BIGINT) AS monthyear,
            CAST("count" AS BIGINT) AS "count"
        FROM {relation}
        """
    )
    duplicates = scalar(
        connection,
        """
        SELECT count(*)
        FROM (
            SELECT unique_small_grid_id, monthyear
            FROM modis_grid
            GROUP BY ALL
            HAVING count(*) <> 1
        )
        """,
    )
    if duplicates:
        raise ValueError(
            f"{duplicates:,} duplicated grid-months in {modis_path.name}; the fire "
            "grid key must be unique."
        )
    rows, grids, first, last = connection.execute(
        """
        SELECT count(*), count(DISTINCT unique_small_grid_id),
               min(monthyear), max(monthyear)
        FROM modis_grid
        """
    ).fetchone()
    logging.info(
        "MODIS grid: %s rows, %s grids, months %s to %s",
        f"{rows:,}",
        f"{grids:,}",
        first,
        last,
    )


def build_baseline(
    connection: duckdb.DuckDBPyConnection, table: str, baseline_months: int
) -> None:
    """Create the baseline table from the expanded window, zero-filling gaps."""

    connection.execute(
        f"""
        CREATE TEMP TABLE baseline_months AS
        SELECT
            u.unique_small_grid_id,
            u.cohort_id,
            u.control_term_start - offsets.step AS monthyear
        FROM unit_window AS u
        CROSS JOIN (
            SELECT unnest(range(1, {int(baseline_months) + 1})) AS step
        ) AS offsets
        """
    )

    # A month with no detection has no row in the fire grid, so it must be
    # zero-filled rather than dropped. Averaging matched rows only would
    # overstate the baseline in proportion to how fire-prone the grid is.
    connection.execute(
        f"""
        CREATE TABLE {qid(table)} AS
        SELECT
            b.unique_small_grid_id,
            b.cohort_id,
            (((b.monthyear - 1) % 12) + 1)::TINYINT AS month,
            avg(COALESCE(f."count", 0))::DOUBLE AS t2_count_modis,
            min(b.monthyear)::BIGINT AS t2_window_start,
            max(b.monthyear)::BIGINT AS t2_window_end,
            count(*)::INTEGER AS t2_months
        FROM baseline_months AS b
        LEFT JOIN modis_grid AS f
          ON f.unique_small_grid_id = b.unique_small_grid_id
         AND f.monthyear = b.monthyear
        GROUP BY 1, 2, 3
        """
    )


def validate_baseline(
    connection: duckdb.DuckDBPyConnection,
    table: str,
    source_relation: str,
    key_columns: Sequence[str],
    baseline_months: int,
) -> None:
    quoted = qid(table)
    expected_per_month = baseline_months // 12

    wrong_width = scalar(
        connection,
        f"""
        SELECT count(*)
        FROM (
            SELECT unique_small_grid_id, cohort_id
            FROM {quoted}
            GROUP BY ALL
            HAVING count(*) <> 12
        )
        """,
    )
    if wrong_width:
        raise ValueError(
            f"{wrong_width:,} unit-cohorts do not have one row per calendar month."
        )

    wrong_depth = scalar(
        connection, f"SELECT count(*) FROM {quoted} WHERE t2_months <> {expected_per_month}"
    )
    if wrong_depth:
        raise ValueError(
            f"{wrong_depth:,} cells do not average over exactly "
            f"{expected_per_month} baseline months."
        )

    bad_values = scalar(
        connection,
        f"SELECT count(*) FROM {quoted} WHERE t2_count_modis IS NULL OR t2_count_modis < 0",
    )
    if bad_values:
        raise ValueError(f"{bad_values:,} cells carry a missing or negative baseline.")

    # Every unit-cohort of the stack must be covered; the whole point of this
    # table is that it restricts nothing.
    key_sql = ", ".join(qid(column) for column in key_columns)
    missing_units = scalar(
        connection,
        f"""
        SELECT count(*)
        FROM (
            SELECT DISTINCT unique_small_grid_id, {key_sql} FROM {source_relation}
            EXCEPT
            SELECT DISTINCT unique_small_grid_id, {key_sql} FROM {quoted}
        )
        """,
    )
    if missing_units:
        raise ValueError(
            f"{missing_units:,} unit-cohorts of the source stack have no baseline; "
            "the control-term match failed for them."
        )

    units, cohorts, rows = connection.execute(
        f"""
        SELECT count(DISTINCT unique_small_grid_id), count(DISTINCT cohort_id), count(*)
        FROM {quoted}
        """
    ).fetchone()
    windows = connection.execute(
        f"""
        SELECT cohort_id, min(t2_window_start), max(t2_window_end)
        FROM {quoted} GROUP BY cohort_id ORDER BY cohort_id
        """
    ).fetchall()
    logging.info(
        "Baseline: %s rows, %s grids, %s cohorts", f"{rows:,}", f"{units:,}", cohorts
    )
    for cohort_id, start, end in windows:
        logging.info("  cohort %s: baseline window %s to %s", cohort_id, start, end)

    zero_share = scalar(
        connection, f"SELECT avg(CASE WHEN t2_count_modis = 0 THEN 1 ELSE 0 END) FROM {quoted}"
    )
    logging.info("Cells with a zero baseline: %.1f%%", 100.0 * float(zero_share))


def write_outputs(
    connection: duckdb.DuckDBPyConnection,
    table: str,
    output_csv: Path,
    output_dta: Path,
) -> None:
    csv_temp = output_csv.with_name(output_csv.name + ".tmp")
    connection.execute(
        f"""
        COPY (
            SELECT unique_small_grid_id, cohort_id, month, t2_count_modis,
                   t2_window_start, t2_window_end
            FROM {qid(table)}
            ORDER BY unique_small_grid_id, cohort_id, month
        ) TO {qstr(csv_temp)} (FORMAT CSV, HEADER TRUE)
        """
    )
    os.replace(csv_temp, output_csv)

    frame = connection.execute(
        f"""
        SELECT unique_small_grid_id, cohort_id, month, t2_count_modis,
               t2_window_start, t2_window_end
        FROM {qid(table)}
        ORDER BY unique_small_grid_id, cohort_id, month
        """
    ).df()
    dta_temp = output_dta.with_name(output_dta.name + ".tmp")
    frame.to_stata(
        dta_temp,
        write_index=False,
        version=118,
        data_label="MODIS T-2 fire baseline by grid, cohort and calendar month",
        variable_labels=STATA_VARIABLE_LABELS,
    )
    os.replace(dta_temp, output_dta)


def write_modis_panel(
    connection: duckdb.DuckDBPyConnection,
    source_relation: str,
    panel_csv: Path,
    panel_dta: Path,
) -> None:
    """Write MODIS counts over the stack's own window, zero-filled.

    The baseline alone cannot support a MODIS-only outcome, because it says
    nothing about the estimation months. This panel supplies them, so the
    dofile can also estimate the arm where outcome and baseline come from the
    same instrument and the mixed subtraction can be checked.
    """

    first, last = connection.execute(
        f"SELECT min(monthyear), max(monthyear) FROM {source_relation}"
    ).fetchone()
    frame = connection.execute(
        f"""
        SELECT
            f.unique_small_grid_id,
            ((f.monthyear - 1) // 12)::INTEGER AS year,
            (((f.monthyear - 1) % 12) + 1)::TINYINT AS month,
            f."count"::BIGINT AS count_modis
        FROM modis_grid AS f
        WHERE f.monthyear BETWEEN {int(first)} AND {int(last)}
          AND f.unique_small_grid_id IN (
              SELECT DISTINCT unique_small_grid_id FROM unit_window
          )
        ORDER BY f.unique_small_grid_id, year, month
        """
    ).df()
    logging.info("MODIS estimation panel: %s rows", f"{len(frame):,}")

    csv_temp = panel_csv.with_name(panel_csv.name + ".tmp")
    frame.to_csv(csv_temp, index=False)
    os.replace(csv_temp, panel_csv)

    dta_temp = panel_dta.with_name(panel_dta.name + ".tmp")
    frame.to_stata(
        dta_temp,
        write_index=False,
        version=118,
        data_label="MODIS-only fire counts over the politician stack window",
        variable_labels=PANEL_VARIABLE_LABELS,
    )
    os.replace(dta_temp, panel_dta)


def build(
    master_path: Path,
    modis_path: Path,
    source_database: Path,
    output_csv: Path,
    output_dta: Path,
    database_path: Path,
    args: argparse.Namespace,
) -> None:
    for required in (master_path, modis_path, source_database):
        if not required.is_file():
            raise FileNotFoundError(f"Input not found: {required}")
    check_source_freshness(master_path, source_database, args.allow_stale_source)

    existing = [
        path
        for path in (
            output_csv,
            output_dta,
            database_path,
            output_csv.with_name(f"{PANEL_STEM}.csv"),
            output_csv.with_name(f"{PANEL_STEM}.dta"),
        )
        if path.exists()
    ]
    if existing and not args.overwrite:
        raise FileExistsError(
            "Outputs exist; pass --overwrite: " + ", ".join(map(str, existing))
        )

    database_temp = database_path.with_name(database_path.name + ".tmp")
    for temp_path in (database_temp,):
        if temp_path.exists():
            temp_path.unlink()

    master_sql = source_expression(master_path, args.csv_sample_size)
    succeeded = False
    connection = duckdb.connect(str(database_temp))
    try:
        configure_connection(
            connection,
            memory_limit=args.memory_limit,
            threads=args.threads,
            temp_directory=database_path.parent,
        )
        connection.execute(f"ATTACH {qstr(source_database)} AS src (READ_ONLY)")
        source_relation = f"src.{qid(SOURCE_VIEW)}"
        source_columns = relation_columns(connection, source_relation)
        require_columns(
            source_columns,
            ("unique_small_grid_id", "ac_uq_id", "cohort", "treat"),
            f"source stack {source_database.name}",
        )
        key_columns = cohort_key(source_columns)
        if key_columns != ("cohort_id",):
            raise ValueError(
                "This baseline is keyed on cohort_id, so it needs the "
                "province-election stack rather than the pooled one."
            )

        load_modis_grid(
            connection,
            modis_path,
            args.csv_sample_size,
            source_grid_type(connection, source_relation),
        )
        build_ac_terms(connection, master_sql, "nonagricultural")
        # unit_window covers every unit-cohort. The kept_units view that the
        # two-cycle builder uses applies its retention rule; here nothing is
        # dropped, which is the entire point.
        build_unit_windows(connection, source_relation, "nonagricultural", key_columns)

        no_control_term = scalar(
            connection, "SELECT count(*) FROM unit_window WHERE control_term_start IS NULL"
        )
        if no_control_term:
            raise ValueError(
                f"{no_control_term:,} unit-cohorts have no control term, so their "
                "baseline window cannot be placed."
            )

        build_baseline(connection, OUTPUT_STEM, args.baseline_months)
        validate_baseline(
            connection, OUTPUT_STEM, source_relation, key_columns, args.baseline_months
        )
        write_outputs(connection, OUTPUT_STEM, output_csv, output_dta)
        write_modis_panel(
            connection,
            source_relation,
            output_csv.with_name(f"{PANEL_STEM}.csv"),
            output_csv.with_name(f"{PANEL_STEM}.dta"),
        )
        connection.execute("DETACH src")
        connection.execute("CHECKPOINT")
        succeeded = True
    except BaseException:
        succeeded = False
        raise
    finally:
        connection.close()
        if not succeeded and database_temp.exists():
            database_temp.unlink()

    os.replace(database_temp, database_path)
    logging.info("CSV: %s", output_csv)
    logging.info("Stata: %s", output_dta)
    logging.info("DuckDB: %s", database_path)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s | %(levelname)s | %(message)s",
    )
    intermediate = args.intermediate.resolve()
    master_path = (
        args.input.resolve() if args.input else intermediate / "0_master_dataset.parquet"
    )
    modis_path = (
        args.modis_grid.resolve()
        if args.modis_grid
        else intermediate / "_3_fire_grid_MODIS_only.csv"
    )
    source_database = (
        args.source_database.resolve()
        if args.source_database
        else intermediate / SOURCE_DATABASE
    )
    output_csv = args.output.resolve() if args.output else intermediate / f"{OUTPUT_STEM}.csv"
    output_dta = output_csv.with_suffix(".dta")
    database_path = (
        args.database.resolve() if args.database else intermediate / f"{OUTPUT_STEM}.db"
    )

    logging.info("Building the MODIS T-2 baseline over %s months", args.baseline_months)
    build(
        master_path,
        modis_path,
        source_database,
        output_csv,
        output_dta,
        database_path,
        args,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

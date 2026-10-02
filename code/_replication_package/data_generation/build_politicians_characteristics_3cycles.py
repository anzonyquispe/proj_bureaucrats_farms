#!/usr/bin/env python3
"""Extend a politician-characteristics stack to three electoral terms.

Naming warning: "3cycles" counts **electoral terms**, while the sibling
``build_politicians_characteristics_2cycles.py`` counts **clean cycles without an
agricultural politician**. Both stacks therefore span three terms; they differ in
what they demand of the oldest one.

The terms, oldest first:

* ``T-2`` is the prior term. **Its profession is unrestricted** -- it may be
  agricultural. This is the whole point of this builder.
* ``T-1`` is the control term in force just before the cohort month. It must be
  non-agricultural, which the switch definition already guarantees for treated
  units.
* ``T0`` is the treated term that opens at the cohort month.

A unit is retained only when ``T-2`` is observed in the master panel; everything
else is dropped in full, post-treatment rows included. Because the master starts
in 2012-09, that keeps the four second-round cohorts, exactly as in the
two-cycle stack.

Why this builder adds rows instead of filtering
-----------------------------------------------
The stacking engine truncates a treated unit's spell at ``d_pre``, the last month
with ``self_profession_nomiss = 1`` before the switch. When ``T-2`` was
agricultural its months were therefore **already removed from the source stack**.
The two-cycle builder leans on that fact and is a pure row subset of its source.
Here the invariant necessarily breaks: the months of an agricultural ``T-2`` are
recovered from the master and their engine-derived columns are recomputed.

Every output row is still a real master observation, and that is asserted rather
than assumed. Rows carry ``row_source`` so the recovered ones stay auditable.

Caveat on ``control_type``
--------------------------
``control_type`` is carried over from the source stack without recomputation, so
it keeps describing the engine's original window rather than the extended one.
That is deliberate: it keeps ``keep if treat == 1 | control_type == 1`` meaning
the same thing here as in the published datasets.
"""

from __future__ import annotations

import argparse
import logging
import os
from pathlib import Path
from typing import Sequence

import duckdb

from _stacked_duckdb_core import (
    configure_connection,
    qid,
    qstr,
    source_expression,
)
from build_all_stacked_datasets_duckdb import (
    CLUSTER_INTERMEDIATE,
    LOCAL_INTERMEDIATE,
)

# The electoral calendar and the small source-inspection helpers are imported
# rather than copied: both builders must read exactly the same term boundaries,
# and a divergence between two near-identical copies would be silent.
from build_politicians_characteristics_2cycles import (
    StackSource,
    build_ac_terms,
    check_source_freshness,
    cohort_key,
    relation_columns,
    require_columns,
    scalar,
)


TREATMENT_COLUMN = "self_profession_nomiss"
DEFAULT_EXPECTED_COHORTS = 4
SOURCE_VIEW = "final_stack"


SOURCES: dict[str, StackSource] = {
    "byprov": StackSource(
        name="byprov",
        source_database="politicians_characteristics_byprov.db",
        output_csv="politicians_characteristics_byprov_3cycles.csv",
        database="politicians_characteristics_byprov_3cycles.db",
        manifest="politicians_characteristics_byprov_3cycles_manifest.csv",
        table="politicians_characteristics_byprov_3cycles",
        description="province-election politician stack",
    ),
    "pooled": StackSource(
        name="pooled",
        source_database="politicians_characteristics.db",
        output_csv="politicians_characteristics_3cycles.csv",
        database="politicians_characteristics_3cycles.db",
        manifest="politicians_characteristics_3cycles_manifest.csv",
        table="politicians_characteristics_3cycles",
        description="pooled calendar-cohort politician stack",
    ),
}

DIAGNOSTIC_COLUMNS = (
    "control_term_start",
    "control_term_election_year",
    "prev_term_start",
    "prev_term_election_year",
    "prev_term_agricultural",
    "prev_term_obs_months",
    "pre_window_start_monthyear",
    "relative_term",
    "row_source",
)

# Columns of the source stack that are constant inside a unit-cohort, so a
# recovered row can take them straight from the stack.
UNIT_CONSTANT_CANDIDATES = (
    "treat",
    "cohort",
    "control_type",
    "cohort_id",
    "cohort_year",
    "cohort_month",
    "cohort_province",
)

# Columns the engine derives. Every recovered row is pre-treatment by
# construction, hence the constant ``post``.
BACKFILL_COMPUTED_SQL = {
    "post": "0",
    "relative_monthyear": "(m.monthyear - a.cohort)",
    "relative_year": "floor((m.monthyear - a.cohort) / 12.0)",
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
        "--source",
        choices=(*SOURCES, "all"),
        default="byprov",
        help="Which published stack to extend.",
    )
    parser.add_argument(
        "--source-database",
        type=Path,
        default=None,
        help="Override the source DuckDB; only valid for a single --source.",
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=None,
        help="Master Parquet/CSV; defaults to INTERMEDIATE/0_master_dataset.parquet.",
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
        "--expected-cohorts",
        type=int,
        default=DEFAULT_EXPECTED_COHORTS,
        help="Cohorts that must survive the extension; 0 disables the check.",
    )
    parser.add_argument(
        "--prior-term-missing-policy",
        choices=("keep", "drop"),
        default="keep",
        help=(
            "How to treat a prior term whose raw self_profession is missing. "
            "Rarely useful here, because the prior term's profession no longer "
            "decides retention; kept for parity with the two-cycle builder."
        ),
    )
    parser.add_argument(
        "--allow-stale-source",
        action="store_true",
        help="Skip the check that the source stack is newer than the master.",
    )
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING"],
        default="INFO",
    )
    args = parser.parse_args(argv)
    if args.threads < 1:
        parser.error("--threads must be positive.")
    if args.expected_cohorts < 0:
        parser.error("--expected-cohorts cannot be negative.")
    if args.source == "all" and (
        args.source_database or args.output or args.database
    ):
        parser.error(
            "--source-database, --output and --database require a single --source."
        )
    return args


def selected_sources(args: argparse.Namespace) -> list[StackSource]:
    if args.source == "all":
        return list(SOURCES.values())
    return [SOURCES[args.source]]


def relation_schema(
    connection: duckdb.DuckDBPyConnection, relation: str
) -> list[tuple[str, str]]:
    """Column names and declared types, used to keep the UNION branches aligned."""

    return [
        (str(row[0]), str(row[1]))
        for row in connection.execute(f"DESCRIBE SELECT * FROM {relation}").fetchall()
    ]


def build_unit_windows(
    connection: duckdb.DuckDBPyConnection,
    source_relation: str,
    missing_policy: str,
    key_columns: Sequence[str],
) -> None:
    """Create ``unit_window``: the retention decision for each unit and cohort.

    This is the two-cycle rule minus its ``prior_term_agricultural`` branch: the
    prior term must exist, but it may be agricultural.
    """

    extra_keys = [column for column in key_columns if column != "cohort"]
    extra_select = "".join(
        f"max({qid(column)}) AS {qid(column)},\n            " for column in extra_keys
    )
    connection.execute(
        f"""
        CREATE TEMP TABLE unit_cohort_ac AS
        SELECT
            unique_small_grid_id,
            cohort,
            {extra_select}min(CAST(ac_uq_id AS BIGINT)) AS ac_uq_id,
            count(DISTINCT ac_uq_id) AS n_ac,
            max(treat) AS treat
        FROM {source_relation}
        GROUP BY unique_small_grid_id, cohort
        """
    )
    ambiguous = scalar(
        connection, "SELECT count(*) FROM unit_cohort_ac WHERE n_ac <> 1"
    )
    if ambiguous:
        raise ValueError(f"{ambiguous:,} unit-cohort pairs span more than one AC.")

    missing_case = (
        "WHEN w.prev_term_self_profession_missing THEN 'prior_term_missing'"
        if missing_policy == "drop"
        else ""
    )
    extra_projection = "".join(f"u.{qid(column)}, " for column in extra_keys)
    connection.execute(
        f"""
        CREATE TEMP TABLE unit_window AS
        WITH matched AS (
            SELECT
                u.unique_small_grid_id,
                u.cohort,
                {extra_projection}
                u.ac_uq_id,
                u.treat,
                t.term_start AS control_term_start,
                t.election_year AS control_term_election_year,
                t.agricultural AS control_term_agricultural,
                t.term_seq AS control_term_seq,
                t.prev_term_start,
                t.prev_term_election_year,
                t.prev_term_agricultural,
                t.prev_term_obs_months,
                t.prev_term_self_profession_missing
            FROM unit_cohort_ac AS u
            ASOF LEFT JOIN ac_terms_ranked AS t
              ON u.ac_uq_id = t.ac_uq_id
             AND u.cohort > t.term_start
        )
        SELECT
            w.*,
            CASE
                WHEN w.control_term_start IS NULL THEN 'no_control_term'
                WHEN w.control_term_agricultural = 1 THEN 'control_term_agricultural'
                WHEN w.prev_term_start IS NULL THEN 'prior_term_unobserved'
                {missing_case}
                ELSE 'kept'
            END AS status,
            w.prev_term_start AS pre_window_start_monthyear
        FROM matched AS w
        """
    )
    connection.execute(
        "CREATE TEMP VIEW kept_units AS SELECT * FROM unit_window WHERE status = 'kept'"
    )

    treated_without_term = scalar(
        connection,
        "SELECT count(*) FROM unit_window WHERE treat = 1 AND control_term_start IS NULL",
    )
    if treated_without_term:
        raise ValueError(
            f"{treated_without_term:,} treated unit-cohort pairs have no control term; "
            "the master electoral calendar does not cover their cohort."
        )
    treated_agricultural_control = scalar(
        connection,
        "SELECT count(*) FROM unit_window "
        "WHERE treat = 1 AND control_term_agricultural = 1",
    )
    if treated_agricultural_control:
        raise ValueError(
            f"{treated_agricultural_control:,} treated unit-cohort pairs have an "
            "agricultural control term, which contradicts the switch definition."
        )

    breakdown = connection.execute(
        """
        SELECT status, treat, count(*) AS units
        FROM unit_window
        GROUP BY status, treat
        ORDER BY status, treat
        """
    ).fetchall()
    for status, treat, units in breakdown:
        logging.info(
            "Units %s | %s: %s",
            "treated" if int(treat) == 1 else "control",
            status,
            f"{int(units):,}",
        )

    kept_agricultural = scalar(
        connection,
        "SELECT count(*) FROM kept_units WHERE prev_term_agricultural = 1",
    )
    logging.info(
        "Retained units whose prior term was agricultural: %s "
        "(these are the ones the two-cycle stack drops)",
        f"{int(kept_agricultural):,}",
    )


def build_unit_stack_attrs(
    connection: duckdb.DuckDBPyConnection,
    source_relation: str,
    unit_constant: Sequence[str],
) -> None:
    """Create ``unit_stack_attrs``: per unit-cohort window bounds and constants."""

    carried = [column for column in unit_constant if column != "cohort"]
    carried_sql = "".join(
        f"any_value(s.{qid(column)}) AS {qid(column)},\n            "
        for column in carried
    )
    connection.execute(
        f"""
        CREATE TEMP TABLE unit_stack_attrs AS
        SELECT
            s.unique_small_grid_id,
            s.cohort,
            {carried_sql}min(s.monthyear) AS stack_min_monthyear,
            max(s.monthyear) AS stack_max_monthyear,
            count(DISTINCT s.treat) AS n_treat
        FROM {source_relation} AS s
        JOIN kept_units AS w USING (unique_small_grid_id, cohort)
        GROUP BY s.unique_small_grid_id, s.cohort
        """
    )
    varying = scalar(
        connection, "SELECT count(*) FROM unit_stack_attrs WHERE n_treat <> 1"
    )
    if varying:
        raise ValueError(
            f"treat varies inside {varying:,} unit-cohort pairs of the source stack."
        )
    if "control_type" in carried:
        varying_type = scalar(
            connection,
            f"""
            SELECT count(*)
            FROM (
                SELECT unique_small_grid_id, cohort
                FROM {source_relation}
                JOIN kept_units AS w USING (unique_small_grid_id, cohort)
                GROUP BY unique_small_grid_id, cohort
                HAVING count(DISTINCT control_type) <> 1
            )
            """,
        )
        if varying_type:
            raise ValueError(
                f"control_type varies inside {varying_type:,} unit-cohort pairs."
            )


def backfill_expression(
    column: str,
    column_type: str,
    unit_constant: Sequence[str],
    master_columns: Sequence[str],
) -> str:
    """SQL for one output column of a row recovered from the master."""

    if column in BACKFILL_COMPUTED_SQL:
        expression = BACKFILL_COMPUTED_SQL[column]
    elif column in unit_constant:
        expression = f"a.{qid(column)}"
    elif column in master_columns:
        expression = f"m.{qid(column)}"
    else:
        raise ValueError(
            f"Cannot rebuild column {column!r} for a recovered row: it is neither "
            "derived, constant within a unit-cohort, nor present in the master. "
            "The source stack gained a column this builder does not understand."
        )
    return f"CAST({expression} AS {column_type}) AS {qid(column)}"


def extend_stack(
    connection: duckdb.DuckDBPyConnection,
    source_relation: str,
    source_schema: Sequence[tuple[str, str]],
    master_sql: str,
    master_columns: Sequence[str],
    unit_constant: Sequence[str],
    table: str,
) -> None:
    """Create the extended table: stack rows plus the months recovered from master."""

    source_columns = [name for name, _ in source_schema]
    stack_select = ", ".join(f"s.{qid(column)}" for column in source_columns)
    backfill_select = ",\n            ".join(
        backfill_expression(name, column_type, unit_constant, master_columns)
        for name, column_type in source_schema
    )

    # Bound the master scan: nothing before the earliest pre-window start, and
    # nothing at or after the latest stack start, can ever be recovered.
    earliest = scalar(
        connection, "SELECT min(pre_window_start_monthyear) FROM kept_units"
    )
    latest = scalar(connection, "SELECT max(stack_min_monthyear) FROM unit_stack_attrs")
    if earliest is None or latest is None:
        raise ValueError("No units survived the three-term requirement.")
    master_bounds = (
        f"AND m.monthyear >= {int(earliest)} AND m.monthyear < {int(latest)}"
    )

    diagnostic_select = """w.control_term_start,
            w.control_term_election_year,
            w.prev_term_start,
            w.prev_term_election_year,
            w.prev_term_agricultural,
            w.prev_term_obs_months,
            w.pre_window_start_monthyear,
            (r.term_seq - w.control_term_seq - 1)::INTEGER AS relative_term,
            c.row_source"""
    outer_select = ", ".join(f"c.{qid(column)}" for column in source_columns)

    connection.execute(
        f"""
        CREATE TABLE {qid(table)} AS
        WITH combined AS (
            SELECT
                {stack_select},
                'stack' AS row_source
            FROM {source_relation} AS s
            JOIN kept_units AS w USING (unique_small_grid_id, cohort)
            WHERE s.monthyear >= w.pre_window_start_monthyear

            UNION ALL

            SELECT
                {backfill_select},
                'master_backfill' AS row_source
            FROM {master_sql} AS m
            JOIN unit_stack_attrs AS a
              ON m.unique_small_grid_id = a.unique_small_grid_id
            JOIN kept_units AS w
              ON w.unique_small_grid_id = a.unique_small_grid_id
             AND w.cohort = a.cohort
            WHERE m.monthyear >= w.pre_window_start_monthyear
              AND m.monthyear < a.stack_min_monthyear
              {master_bounds}
        )
        SELECT
            {outer_select},
            {diagnostic_select}
        FROM combined AS c
        JOIN kept_units AS w USING (unique_small_grid_id, cohort)
        ASOF LEFT JOIN ac_terms_ranked AS r
          ON w.ac_uq_id = r.ac_uq_id
         AND c.monthyear >= r.term_start
        """
    )

    added = int(
        scalar(
            connection,
            f"SELECT count(*) FROM {qid(table)} WHERE row_source = 'master_backfill'",
        )
    )
    total = int(scalar(connection, f"SELECT count(*) FROM {qid(table)}"))
    logging.info(
        "Rows recovered from the master: %s of %s (%.1f%%)",
        f"{added:,}",
        f"{total:,}",
        100.0 * added / total if total else 0.0,
    )


def validate_extension(
    connection: duckdb.DuckDBPyConnection,
    source_relation: str,
    master_sql: str,
    table: str,
    expected_cohorts: int,
    key_columns: Sequence[str],
) -> None:
    quoted = qid(table)
    key_sql = ", ".join(qid(column) for column in key_columns)

    # Every output row must be a real master observation. This replaces the
    # two-cycle "output is a subset of the source" assertion, which cannot hold
    # once months are recovered.
    invented_rows = scalar(
        connection,
        f"""
        SELECT count(*)
        FROM (
            SELECT DISTINCT unique_small_grid_id, monthyear FROM {quoted}
            EXCEPT
            SELECT DISTINCT unique_small_grid_id, monthyear FROM {master_sql}
        )
        """,
    )
    if invented_rows:
        raise ValueError(
            f"{invented_rows:,} output grid-months are absent from the master."
        )

    # Nothing of the source may be lost inside the retained window.
    missing_source_rows = scalar(
        connection,
        f"""
        SELECT count(*)
        FROM (
            SELECT s.unique_small_grid_id, s.monthyear, s.cohort, s.treat
            FROM {source_relation} AS s
            JOIN kept_units AS w USING (unique_small_grid_id, cohort)
            WHERE s.monthyear >= w.pre_window_start_monthyear
            EXCEPT
            SELECT unique_small_grid_id, monthyear, cohort, treat FROM {quoted}
        )
        """,
    )
    if missing_source_rows:
        raise ValueError(
            f"{missing_source_rows:,} source rows of retained units are missing "
            "from the extended stack."
        )

    duplicate_keys = scalar(
        connection,
        f"""
        SELECT count(*)
        FROM (
            SELECT unique_small_grid_id, monthyear, cohort, treat
            FROM {quoted}
            GROUP BY ALL
            HAVING count(*) <> 1
        )
        """,
    )
    if duplicate_keys:
        raise ValueError(f"{duplicate_keys:,} duplicated keys in {table}.")

    bad_relative = scalar(
        connection,
        f"SELECT count(*) FROM {quoted} WHERE relative_monthyear <> monthyear - cohort",
    )
    if bad_relative:
        raise ValueError(
            f"relative_monthyear disagrees with monthyear - cohort on "
            f"{bad_relative:,} rows."
        )

    # Recovered rows are pre-treatment by construction.
    bad_backfill = scalar(
        connection,
        f"""
        SELECT count(*)
        FROM {quoted}
        WHERE row_source = 'master_backfill'
          AND (relative_monthyear >= 0 OR post <> 0)
        """,
    )
    if bad_backfill:
        raise ValueError(
            f"{bad_backfill:,} recovered rows are not pre-treatment."
        )

    gapped_units = scalar(
        connection,
        f"""
        SELECT count(*)
        FROM (
            SELECT unique_small_grid_id, cohort
            FROM {quoted}
            GROUP BY unique_small_grid_id, cohort
            HAVING max(monthyear) - min(monthyear) + 1 <> count(DISTINCT monthyear)
        )
        """,
    )
    if gapped_units:
        raise ValueError(
            f"{gapped_units:,} unit-cohort pairs have a gap between the recovered "
            "months and the original stack window."
        )

    post_mismatch = scalar(
        connection,
        f"""
        SELECT count(*)
        FROM (
            SELECT unique_small_grid_id, cohort, count(*) AS rows_kept
            FROM {quoted} WHERE relative_monthyear >= 0
            GROUP BY unique_small_grid_id, cohort
        ) AS extended
        FULL OUTER JOIN (
            SELECT s.unique_small_grid_id, s.cohort, count(*) AS rows_source
            FROM {source_relation} AS s
            JOIN kept_units AS w USING (unique_small_grid_id, cohort)
            WHERE s.relative_monthyear >= 0
            GROUP BY s.unique_small_grid_id, s.cohort
        ) AS source
        USING (unique_small_grid_id, cohort)
        WHERE extended.rows_kept IS DISTINCT FROM source.rows_source
        """,
    )
    if post_mismatch:
        raise ValueError(
            f"The post-treatment period changed for {post_mismatch:,} retained units."
        )

    short_units = scalar(
        connection,
        f"""
        SELECT count(*)
        FROM (
            SELECT unique_small_grid_id, cohort, min(relative_term) AS first_term
            FROM {quoted}
            GROUP BY unique_small_grid_id, cohort
            HAVING min(relative_term) > -2
        )
        """,
    )
    if short_units:
        raise ValueError(
            f"{short_units:,} retained units do not reach the prior term."
        )

    unbalanced = connection.execute(
        f"""
        SELECT {key_sql},
               count(DISTINCT unique_small_grid_id) FILTER (WHERE treat = 1),
               count(DISTINCT unique_small_grid_id) FILTER (WHERE treat = 0)
        FROM {quoted}
        GROUP BY {key_sql}
        HAVING count(DISTINCT unique_small_grid_id) FILTER (WHERE treat = 1) = 0
            OR count(DISTINCT unique_small_grid_id) FILTER (WHERE treat = 0) = 0
        """
    ).fetchall()
    if unbalanced:
        raise ValueError(
            "Every surviving cohort needs treated and control grids; "
            f"failed cohorts: {unbalanced}."
        )

    label_sql = key_sql if "cohort" in key_columns else f"{key_sql}, cohort"
    surviving_cohorts = connection.execute(
        f"SELECT DISTINCT {label_sql} FROM {quoted} ORDER BY cohort, {key_sql}"
    ).fetchall()
    surviving = len(surviving_cohorts)
    logging.info(
        "Surviving cohorts: %s (%s)",
        surviving,
        "; ".join(" ".join(str(value) for value in row) for row in surviving_cohorts)
        or "none",
    )
    if expected_cohorts and surviving != expected_cohorts:
        raise ValueError(
            f"{surviving} cohorts survived the extension; expected "
            f"{expected_cohorts}. Pass --expected-cohorts 0 to skip this check."
        )


def write_manifest(
    connection: duckdb.DuckDBPyConnection,
    source_relation: str,
    table: str,
    manifest_table: str,
    key_columns: Sequence[str],
    has_cohort_id: bool,
) -> None:
    key_sql = ", ".join(qid(column) for column in key_columns)
    label_sql = key_sql if "cohort" in key_columns else f"{key_sql}, cohort"
    keys = (
        "cohort_id, cohort_province, province, cohort" if has_cohort_id else "cohort"
    )
    order = "cohort_id" if has_cohort_id else "cohort"
    connection.execute(
        f"""
        CREATE TABLE {qid(manifest_table)} AS
        WITH kept AS (
            SELECT
                {keys},
                count(DISTINCT unique_small_grid_id) FILTER (WHERE treat = 1)
                    AS treated_grids,
                count(DISTINCT unique_small_grid_id) FILTER (WHERE treat = 0)
                    AS control_grids,
                count(DISTINCT unique_small_grid_id)
                    FILTER (WHERE prev_term_agricultural = 1)
                    AS grids_with_prior_agricultural,
                count(*) FILTER (WHERE treat = 1) AS treated_rows,
                count(*) FILTER (WHERE treat = 0) AS control_rows,
                count(*) FILTER (WHERE row_source = 'master_backfill') AS rows_added,
                count(*) AS rows_kept,
                min(relative_monthyear) AS relative_month_min,
                max(relative_monthyear) AS relative_month_max,
                min(relative_year) AS relative_year_min,
                max(relative_year) AS relative_year_max,
                min(relative_term) AS relative_term_min,
                max(relative_term) AS relative_term_max,
                min(prev_term_obs_months) AS prior_term_obs_months_min,
                max(prev_term_obs_months) AS prior_term_obs_months_max
            FROM {qid(table)}
            GROUP BY {keys}
        ),
        source AS (
            SELECT {key_sql}, count(*) AS source_rows,
                   count(DISTINCT unique_small_grid_id) AS source_grids
            FROM {source_relation}
            GROUP BY {key_sql}
        ),
        dropped AS (
            SELECT
                {key_sql},
                count(*) FILTER (WHERE status = 'prior_term_unobserved')
                    AS grids_dropped_prior_unobserved,
                count(*) FILTER (WHERE status NOT IN ('kept', 'prior_term_unobserved'))
                    AS grids_dropped_other
            FROM unit_window
            GROUP BY {key_sql}
        )
        SELECT
            kept.*,
            source.source_rows,
            source.source_grids,
            source.source_rows - (kept.rows_kept - kept.rows_added) AS rows_dropped,
            dropped.grids_dropped_prior_unobserved,
            dropped.grids_dropped_other
        FROM kept
        JOIN source USING ({key_sql})
        JOIN dropped USING ({key_sql})
        ORDER BY {order}
        """
    )
    connection.execute(
        f"""
        CREATE TABLE {qid(table + '_attrition')} AS
        SELECT {label_sql}, status, treat,
               count(*) AS grids,
               count(*) FILTER (WHERE prev_term_agricultural = 1)
                   AS grids_prior_agricultural,
               min(control_term_start) AS control_term_start_min,
               max(control_term_start) AS control_term_start_max
        FROM unit_window
        GROUP BY {label_sql}, status, treat
        ORDER BY cohort, status, treat
        """
    )


def extend_source(
    source: StackSource,
    master_path: Path,
    source_database: Path,
    output_path: Path,
    database_path: Path,
    manifest_path: Path,
    args: argparse.Namespace,
) -> None:
    if not source_database.is_file():
        raise FileNotFoundError(
            f"Source stack not found: {source_database}. Build it first."
        )
    check_source_freshness(master_path, source_database, args.allow_stale_source)

    existing = [
        path for path in (output_path, database_path, manifest_path) if path.exists()
    ]
    if existing and not args.overwrite:
        raise FileExistsError(
            "Outputs exist; pass --overwrite: " + ", ".join(map(str, existing))
        )

    output_temp = output_path.with_name(output_path.name + ".tmp")
    database_temp = database_path.with_name(database_path.name + ".tmp")
    manifest_temp = manifest_path.with_name(manifest_path.name + ".tmp")
    for temp_path in (output_temp, database_temp, manifest_temp):
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
        source_schema = relation_schema(connection, source_relation)
        source_columns = [name for name, _ in source_schema]
        require_columns(
            source_columns,
            (
                "unique_small_grid_id",
                "ac_uq_id",
                "monthyear",
                "treat",
                "post",
                "cohort",
                "relative_monthyear",
                "relative_year",
            ),
            f"source stack {source_database.name}",
        )
        collisions = [
            column for column in DIAGNOSTIC_COLUMNS if column in source_columns
        ]
        if collisions:
            raise ValueError(
                "Source stack already carries diagnostic columns: "
                + ", ".join(collisions)
            )
        master_columns = relation_columns(connection, master_sql)
        source_rows = int(scalar(connection, f"SELECT count(*) FROM {source_relation}"))
        logging.info(
            "Source %s: %s rows, %s columns",
            source_database.name,
            f"{source_rows:,}",
            len(source_columns),
        )

        key_columns = cohort_key(source_columns)
        logging.info("Cohort key: %s", ", ".join(key_columns))
        unit_constant = [
            column for column in UNIT_CONSTANT_CANDIDATES if column in source_columns
        ]

        build_ac_terms(connection, master_sql, args.prior_term_missing_policy)
        build_unit_windows(
            connection,
            source_relation,
            args.prior_term_missing_policy,
            key_columns,
        )
        build_unit_stack_attrs(connection, source_relation, unit_constant)
        extend_stack(
            connection,
            source_relation,
            source_schema,
            master_sql,
            master_columns,
            unit_constant,
            source.table,
        )
        validate_extension(
            connection,
            source_relation,
            master_sql,
            source.table,
            args.expected_cohorts,
            key_columns,
        )
        write_manifest(
            connection,
            source_relation,
            source.table,
            f"{source.table}_manifest",
            key_columns,
            has_cohort_id="cohort_id" in source_columns,
        )
        connection.execute(
            f"CREATE VIEW {qid(SOURCE_VIEW)} AS SELECT * FROM {qid(source.table)}"
        )
        connection.execute(
            f"""
            COPY (SELECT * FROM {qid(source.table)})
            TO {qstr(output_temp)} (FORMAT CSV, HEADER TRUE)
            """
        )
        connection.execute(
            f"""
            COPY (SELECT * FROM {qid(source.table + '_manifest')})
            TO {qstr(manifest_temp)} (FORMAT CSV, HEADER TRUE)
            """
        )
        kept_rows = int(scalar(connection, f"SELECT count(*) FROM {qid(source.table)}"))
        connection.execute("DETACH src")
        connection.execute("CHECKPOINT")
        succeeded = True
    except BaseException:
        succeeded = False
        raise
    finally:
        connection.close()
        if not succeeded:
            # A failed run must not leave a partial DuckDB behind; the next
            # attempt would otherwise start from a stale working file.
            for temp_path in (output_temp, database_temp, manifest_temp):
                if temp_path.exists():
                    temp_path.unlink()

    os.replace(database_temp, database_path)
    os.replace(output_temp, output_path)
    os.replace(manifest_temp, manifest_path)
    logging.info(
        "Completed %s: %s rows written from a %s row source (%.1f%%)",
        source.name,
        f"{kept_rows:,}",
        f"{source_rows:,}",
        100.0 * kept_rows / source_rows if source_rows else 0.0,
    )
    logging.info("CSV: %s", output_path)
    logging.info("DuckDB: %s", database_path)
    logging.info("Manifest: %s", manifest_path)


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
    if not master_path.is_file():
        raise FileNotFoundError(f"Master input not found: {master_path}")

    for source in selected_sources(args):
        source_database = (
            args.source_database.resolve()
            if args.source_database
            else intermediate / source.source_database
        )
        output_path = (
            args.output.resolve() if args.output else intermediate / source.output_csv
        )
        database_path = (
            args.database.resolve() if args.database else intermediate / source.database
        )
        manifest_path = output_path.with_name(source.manifest)
        logging.info("Extending the %s to three electoral terms", source.description)
        extend_source(
            source,
            master_path,
            source_database,
            output_path,
            database_path,
            manifest_path,
            args,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

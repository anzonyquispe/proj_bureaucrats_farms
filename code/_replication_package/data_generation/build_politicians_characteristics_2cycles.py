#!/usr/bin/env python3
"""Restrict a politician-characteristics stack to two clean electoral cycles.

The standard stacks keep, before the switch to an agricultural politician, the
whole clean spell of the treated grid. Because the engine truncates that spell
at the last agricultural month, a treated unit contributes exactly one clean
electoral cycle: the control term ``T-1``.

This builder writes an alternative stack that keeps only the units whose AC had
**two** consecutive non-agricultural terms before treatment, and trims their
pre-period to the start of the second one:

* ``T-1`` is the term in force just before the cohort month (the control term).
* ``T-2`` is the term immediately before it.
* A unit is retained only when ``T-2`` is observed in the panel and both ``T-1``
  and ``T-2`` were non-agricultural. Everything else is dropped in full,
  including its post-treatment rows.
* Retained rows start at the beginning of ``T-2``; the post period is untouched.

The rule is evaluated per unit, with each grid using the electoral history of
its own AC, so control grids must also show two clean terms before the cohort.

The new stack is always a row subset of its source: a treated row survives the
engine only when ``monthyear > d_pre`` (the last agricultural month), and
``d_pre`` precedes the start of ``T-2`` whenever ``T-2`` is non-agricultural.
The source stack is therefore filtered rather than re-estimated, which keeps
``cohort_id`` and ``control_type`` identical to the published datasets.
"""

from __future__ import annotations

import argparse
import logging
import os
from dataclasses import dataclass
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


TREATMENT_COLUMN = "self_profession_nomiss"
DEFAULT_EXPECTED_COHORTS = 4
SOURCE_VIEW = "final_stack"


@dataclass(frozen=True)
class StackSource:
    """One source stack and the artefacts its restricted variant writes."""

    name: str
    source_database: str
    output_csv: str
    database: str
    manifest: str
    table: str
    description: str


SOURCES: dict[str, StackSource] = {
    "byprov": StackSource(
        name="byprov",
        source_database="politicians_characteristics_byprov.db",
        output_csv="politicians_characteristics_byprov_2cycles.csv",
        database="politicians_characteristics_byprov_2cycles.db",
        manifest="politicians_characteristics_byprov_2cycles_manifest.csv",
        table="politicians_characteristics_byprov_2cycles",
        description="province-election politician stack",
    ),
    "pooled": StackSource(
        name="pooled",
        source_database="politicians_characteristics.db",
        output_csv="politicians_characteristics_2cycles.csv",
        database="politicians_characteristics_2cycles.db",
        manifest="politicians_characteristics_2cycles_manifest.csv",
        table="politicians_characteristics_2cycles",
        description="pooled calendar-cohort politician stack",
    ),
}

DIAGNOSTIC_COLUMNS = (
    "control_term_start",
    "control_term_election_year",
    "prev_term_start",
    "prev_term_election_year",
    "pre_window_start_monthyear",
    "relative_term",
)


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
        help="Which published stack to restrict.",
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
        help="Cohorts that must survive the restriction; 0 disables the check.",
    )
    parser.add_argument(
        "--prior-term-missing-policy",
        choices=("nonagricultural", "drop"),
        default="nonagricultural",
        help=(
            "How to treat a prior term whose raw self_profession is missing. "
            "The default matches self_profession_nomiss, which reads a blank "
            "profession as non-agricultural."
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


def cohort_key(source_columns: Sequence[str]) -> tuple[str, ...]:
    """Columns that identify a cohort in the source stack.

    The province-election stack reuses one calendar month for two provinces
    (Punjab and Uttar Pradesh both switch in 2022-04), so ``cohort`` alone
    merges them; ``cohort_id`` keeps them apart. The pooled stack has no
    ``cohort_id`` and pools provinces inside one calendar cohort on purpose, so
    there ``cohort`` is the identity.
    """

    if "cohort_id" in source_columns:
        return ("cohort_id",)
    return ("cohort",)


def selected_sources(args: argparse.Namespace) -> list[StackSource]:
    if args.source == "all":
        return list(SOURCES.values())
    return [SOURCES[args.source]]


def scalar(connection: duckdb.DuckDBPyConnection, query: str) -> object:
    return connection.execute(query).fetchone()[0]


def relation_columns(connection: duckdb.DuckDBPyConnection, relation: str) -> list[str]:
    return [
        str(row[0])
        for row in connection.execute(f"DESCRIBE SELECT * FROM {relation}").fetchall()
    ]


def require_columns(
    actual: Sequence[str], required: Sequence[str], label: str
) -> None:
    missing = [column for column in required if column not in actual]
    if missing:
        raise ValueError(f"{label} is missing: {', '.join(missing)}")


def check_source_freshness(
    master_path: Path, source_database: Path, allow_stale: bool
) -> None:
    if allow_stale:
        return
    if master_path.stat().st_mtime_ns > source_database.stat().st_mtime_ns:
        raise ValueError(
            f"The master {master_path} is newer than the source stack "
            f"{source_database}. Rebuild the stack, or pass --allow-stale-source."
        )


def build_ac_terms(
    connection: duckdb.DuckDBPyConnection,
    master_sql: str,
    missing_policy: str,
) -> None:
    """Create ``ac_terms_ranked``: one row per AC and electoral term."""

    master_columns = relation_columns(connection, master_sql)
    require_columns(
        master_columns,
        ("ac_uq_id", "year", "month", "year_take", "month_take", TREATMENT_COLUMN),
        "master input",
    )
    has_raw_profession = "self_profession" in master_columns
    if missing_policy == "drop" and not has_raw_profession:
        raise ValueError(
            "--prior-term-missing-policy drop needs the raw self_profession column."
        )
    missing_expression = (
        "count_if(self_profession IS NULL) > 0"
        if has_raw_profession
        else "FALSE"
    )

    connection.execute(
        f"""
        CREATE TEMP TABLE ac_terms AS
        SELECT
            CAST(ac_uq_id AS BIGINT) AS ac_uq_id,
            (CAST(year_take AS BIGINT) * 12 + CAST(month_take AS BIGINT))
                AS term_start,
            max(TRY_CAST(election_year AS INTEGER)) AS election_year,
            max(CAST({qid(TREATMENT_COLUMN)} AS TINYINT))::TINYINT AS agricultural,
            {missing_expression} AS self_profession_missing,
            min(CAST(year AS BIGINT) * 12 + CAST(month AS BIGINT)) AS term_obs_min,
            max(CAST(year AS BIGINT) * 12 + CAST(month AS BIGINT)) AS term_obs_max,
            count(DISTINCT CAST(year AS BIGINT) * 12 + CAST(month AS BIGINT))
                AS term_obs_months,
            count(DISTINCT {qid(TREATMENT_COLUMN)}) AS n_treatment_values,
            count(DISTINCT election_year) AS n_election_year_values
        FROM {master_sql}
        WHERE year_take IS NOT NULL AND month_take IS NOT NULL
        GROUP BY ac_uq_id, term_start
        """
    )

    inconsistent_treatment = scalar(
        connection, "SELECT count(*) FROM ac_terms WHERE n_treatment_values <> 1"
    )
    if inconsistent_treatment:
        raise ValueError(
            f"{TREATMENT_COLUMN} varies inside {inconsistent_treatment:,} AC terms; "
            "the treatment must be constant within an electoral term."
        )
    inconsistent_year = scalar(
        connection, "SELECT count(*) FROM ac_terms WHERE n_election_year_values > 1"
    )
    if inconsistent_year:
        raise ValueError(
            f"election_year varies inside {inconsistent_year:,} AC terms."
        )
    if "ym_take" in master_columns:
        mismatched = scalar(
            connection,
            f"""
            SELECT count(*)
            FROM {master_sql}
            WHERE ym_take IS DISTINCT FROM
                  CAST(year_take AS BIGINT) * 12 + CAST(month_take AS BIGINT)
            """,
        )
        if mismatched:
            raise ValueError(
                f"ym_take disagrees with year_take/month_take on {mismatched:,} rows."
            )

    connection.execute(
        """
        CREATE TEMP TABLE ac_terms_ranked AS
        SELECT
            *,
            row_number() OVER w AS term_seq,
            lag(term_start) OVER w AS prev_term_start,
            lag(election_year) OVER w AS prev_term_election_year,
            lag(agricultural) OVER w AS prev_term_agricultural,
            lag(term_obs_months) OVER w AS prev_term_obs_months,
            lag(self_profession_missing) OVER w AS prev_term_self_profession_missing
        FROM ac_terms
        WINDOW w AS (PARTITION BY ac_uq_id ORDER BY term_start)
        """
    )
    terms, acs = connection.execute(
        "SELECT count(*), count(DISTINCT ac_uq_id) FROM ac_terms_ranked"
    ).fetchone()
    logging.info("Electoral terms observed: %s across %s ACs", f"{terms:,}", f"{acs:,}")


def build_unit_windows(
    connection: duckdb.DuckDBPyConnection,
    source_relation: str,
    missing_policy: str,
    key_columns: Sequence[str],
) -> None:
    """Create ``unit_window``: the retention decision for each unit and cohort."""

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
        raise ValueError(
            f"{ambiguous:,} unit-cohort pairs span more than one AC."
        )

    missing_case = (
        "WHEN w.prev_term_self_profession_missing THEN 'prior_term_missing'"
        if missing_policy == "drop"
        else ""
    )
    connection.execute(
        f"""
        CREATE TEMP TABLE unit_window AS
        WITH matched AS (
            SELECT
                u.unique_small_grid_id,
                u.cohort,
                {"".join(f"u.{qid(column)}, " for column in extra_keys)}
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
                WHEN w.prev_term_agricultural = 1 THEN 'prior_term_agricultural'
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


def apply_restriction(
    connection: duckdb.DuckDBPyConnection,
    source_relation: str,
    source_columns: Sequence[str],
    table: str,
) -> None:
    """Create the restricted table: kept units, trimmed to two electoral cycles."""

    passthrough = ", ".join(f"s.{qid(column)}" for column in source_columns)
    connection.execute(
        f"""
        CREATE TABLE {qid(table)} AS
        SELECT
            {passthrough},
            w.control_term_start,
            w.control_term_election_year,
            w.prev_term_start,
            w.prev_term_election_year,
            w.pre_window_start_monthyear,
            (r.term_seq - w.control_term_seq - 1)::INTEGER AS relative_term
        FROM {source_relation} AS s
        JOIN kept_units AS w
          USING (unique_small_grid_id, cohort)
        ASOF LEFT JOIN ac_terms_ranked AS r
          ON w.ac_uq_id = r.ac_uq_id
         AND s.monthyear >= r.term_start
        WHERE s.monthyear >= w.pre_window_start_monthyear
        """
    )


def validate_restriction(
    connection: duckdb.DuckDBPyConnection,
    source_relation: str,
    table: str,
    expected_cohorts: int,
    key_columns: Sequence[str],
) -> None:
    quoted = qid(table)
    key_sql = ", ".join(qid(column) for column in key_columns)

    orphan_rows = scalar(
        connection,
        f"""
        SELECT count(*)
        FROM (
            SELECT unique_small_grid_id, monthyear, cohort, treat FROM {quoted}
            EXCEPT
            SELECT unique_small_grid_id, monthyear, cohort, treat
            FROM {source_relation}
        )
        """,
    )
    if orphan_rows:
        raise ValueError(
            f"{orphan_rows:,} restricted rows are absent from the source stack."
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

    post_mismatch = scalar(
        connection,
        f"""
        SELECT count(*)
        FROM (
            SELECT unique_small_grid_id, cohort, count(*) AS rows_kept
            FROM {quoted} WHERE relative_monthyear >= 0
            GROUP BY unique_small_grid_id, cohort
        ) AS restricted
        FULL OUTER JOIN (
            SELECT s.unique_small_grid_id, s.cohort, count(*) AS rows_source
            FROM {source_relation} AS s
            JOIN kept_units AS w USING (unique_small_grid_id, cohort)
            WHERE s.relative_monthyear >= 0
            GROUP BY s.unique_small_grid_id, s.cohort
        ) AS source
        USING (unique_small_grid_id, cohort)
        WHERE restricted.rows_kept IS DISTINCT FROM source.rows_source
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
            f"{short_units:,} retained units do not reach the second prior term."
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
        "; ".join(
            " ".join(str(value) for value in row) for row in surviving_cohorts
        )
        or "none",
    )
    if expected_cohorts and surviving != expected_cohorts:
        raise ValueError(
            f"{surviving} cohorts survived the restriction; expected "
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
                count(*) FILTER (WHERE treat = 1) AS treated_rows,
                count(*) FILTER (WHERE treat = 0) AS control_rows,
                count(*) AS rows_kept,
                min(relative_monthyear) AS relative_month_min,
                max(relative_monthyear) AS relative_month_max,
                min(relative_year) AS relative_year_min,
                max(relative_year) AS relative_year_max,
                min(relative_term) AS relative_term_min,
                max(relative_term) AS relative_term_max
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
                count(*) FILTER (WHERE status = 'prior_term_agricultural')
                    AS grids_dropped_prior_agricultural,
                count(*) FILTER (WHERE status = 'prior_term_unobserved')
                    AS grids_dropped_prior_unobserved,
                count(*) FILTER (WHERE status NOT IN
                    ('kept', 'prior_term_agricultural', 'prior_term_unobserved'))
                    AS grids_dropped_other
            FROM unit_window
            GROUP BY {key_sql}
        )
        SELECT
            kept.*,
            source.source_rows,
            source.source_grids,
            source.source_rows - kept.rows_kept AS rows_dropped,
            dropped.grids_dropped_prior_agricultural,
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
               min(control_term_start) AS control_term_start_min,
               max(control_term_start) AS control_term_start_max
        FROM unit_window
        GROUP BY {label_sql}, status, treat
        ORDER BY cohort, status, treat
        """
    )


def restrict_stack(
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
        source_columns = relation_columns(connection, source_relation)
        require_columns(
            source_columns,
            (
                "unique_small_grid_id",
                "ac_uq_id",
                "monthyear",
                "treat",
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
        source_rows = int(scalar(connection, f"SELECT count(*) FROM {source_relation}"))
        logging.info(
            "Source %s: %s rows, %s columns",
            source_database.name,
            f"{source_rows:,}",
            len(source_columns),
        )

        key_columns = cohort_key(source_columns)
        logging.info("Cohort key: %s", ", ".join(key_columns))

        build_ac_terms(connection, master_sql, args.prior_term_missing_policy)
        build_unit_windows(
            connection,
            source_relation,
            args.prior_term_missing_policy,
            key_columns,
        )
        apply_restriction(connection, source_relation, source_columns, source.table)
        validate_restriction(
            connection,
            source_relation,
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
        "Completed %s: %s of %s rows retained (%.1f%%)",
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
        logging.info("Restricting the %s", source.description)
        restrict_stack(
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

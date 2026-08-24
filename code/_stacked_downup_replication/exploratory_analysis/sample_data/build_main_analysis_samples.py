#!/usr/bin/env python3
"""Create small, reproducible samples of every main-analysis stacked CSV.

For each dataset, the script samples complete analytical units separately
within every cohort and treatment arm.  The default rate is 0.5 percent.
Every row belonging to a selected unit-cohort is retained, so the resulting
files can be passed to the existing Stata dofiles with ``$sample = "_sample"``.
"""

from __future__ import annotations

import argparse
import logging
import sys
from dataclasses import dataclass
from pathlib import Path

import duckdb


@dataclass(frozen=True)
class DatasetSpec:
    filename: str
    cohort_col: str
    unit_cols: tuple[str, ...]


DATASETS = (
    DatasetSpec("combined_dt.csv", "cohort", ("unique_small_grid_id",)),
    DatasetSpec("combined_dt_pop.csv", "cohort", ("unique_small_grid_id",)),
    DatasetSpec(
        "politicians_characteristics_byprov.csv",
        "cohort_id",
        ("unique_small_grid_id",),
    ),
    DatasetSpec(
        "stacked_data_protest5km_election_sameterm.csv",
        "cohort_id",
        ("unique_small_grid_id",),
    ),
    DatasetSpec("stacked_downup_neigh.csv", "cohort", ("unique_pair",)),
)


def sql_string(value: str | Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def qid(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def output_path(input_path: Path) -> Path:
    return input_path.with_name(f"{input_path.stem}_sample.csv")


def source_sql(path: Path) -> str:
    # all_varchar avoids expensive or unstable whole-file type inference. The
    # CSV text is preserved; only treat is cast temporarily for validation.
    return (
        f"read_csv_auto({sql_string(path)}, header=true, all_varchar=true, "
        "null_padding=true)"
    )


def describe_columns(con: duckdb.DuckDBPyConnection, path: Path) -> set[str]:
    return {
        row[0]
        for row in con.execute(
            f"DESCRIBE SELECT * FROM {source_sql(path)}"
        ).fetchall()
    }


def build_one(
    con: duckdb.DuckDBPyConnection,
    spec: DatasetSpec,
    intermediate: Path,
    rate: float,
    minimum_units: int,
    seed: int,
    overwrite: bool,
) -> None:
    input_csv = intermediate / spec.filename
    sample_csv = output_path(input_csv)
    if not input_csv.is_file():
        raise FileNotFoundError(f"Required main-analysis input is absent: {input_csv}")
    if sample_csv.exists() and not overwrite:
        raise FileExistsError(
            f"Sample already exists: {sample_csv}. Pass --overwrite to replace it."
        )

    columns = describe_columns(con, input_csv)
    required = {spec.cohort_col, "treat", *spec.unit_cols}
    missing = sorted(required - columns)
    if missing:
        raise ValueError(f"{spec.filename} is missing required columns: {missing}")

    cohort = qid(spec.cohort_col)
    units = [qid(col) for col in spec.unit_cols]
    keys = [cohort, *units]
    key_csv = ", ".join(keys)
    source = source_sql(input_csv)

    logging.info("START %s", spec.filename)
    con.execute("DROP TABLE IF EXISTS unit_arms")
    con.execute("DROP TABLE IF EXISTS sampled_units")

    # One scan of the large source establishes the analytical units, confirms
    # treatment is constant within each unit-cohort, and records source rows.
    con.execute(
        f"""
        CREATE TEMP TABLE unit_arms AS
        SELECT
            {key_csv},
            MIN(TRY_CAST(treat AS INTEGER))::INTEGER AS treat,
            COUNT(*)::BIGINT AS unit_rows,
            COUNT(DISTINCT TRY_CAST(treat AS INTEGER))::INTEGER AS arm_count,
            COUNT(*) FILTER (
                WHERE TRY_CAST(treat AS INTEGER) IS NULL
                   OR TRY_CAST(treat AS INTEGER) NOT IN (0, 1)
            )::BIGINT AS invalid_treat_rows
        FROM {source}
        GROUP BY {key_csv}
        """
    )

    invalid_units, invalid_rows, mixed_units = con.execute(
        """
        SELECT
            COUNT(*) FILTER (WHERE invalid_treat_rows > 0),
            COALESCE(SUM(invalid_treat_rows), 0),
            COUNT(*) FILTER (WHERE arm_count <> 1)
        FROM unit_arms
        """
    ).fetchone()
    if invalid_units or mixed_units:
        raise ValueError(
            f"{spec.filename}: invalid treatment structure: "
            f"units_with_invalid_treat={invalid_units:,}, "
            f"invalid_rows={invalid_rows:,}, mixed_arm_units={mixed_units:,}"
        )

    hash_args = ", ".join(
        [str(seed), sql_string(spec.filename), *keys, "treat"]
    )
    con.execute(
        f"""
        CREATE TEMP TABLE sampled_units AS
        WITH ranked AS (
            SELECT *,
                ROW_NUMBER() OVER (
                    PARTITION BY {cohort}, treat
                    ORDER BY hash({hash_args}), {', '.join(units)}
                ) AS sample_rank,
                COUNT(*) OVER (PARTITION BY {cohort}, treat) AS stratum_units
            FROM unit_arms
        )
        SELECT {key_csv}, treat, unit_rows, stratum_units
        FROM ranked
        WHERE sample_rank <= GREATEST(
            {minimum_units}, CEIL(stratum_units * {rate})
        )
        """
    )

    source_cohorts, sampled_cohorts, source_strata, sampled_strata = con.execute(
        f"""
        SELECT
            (SELECT COUNT(DISTINCT {cohort}) FROM unit_arms),
            (SELECT COUNT(DISTINCT {cohort}) FROM sampled_units),
            (SELECT COUNT(*) FROM (
                SELECT {cohort}, treat FROM unit_arms GROUP BY ALL
            )),
            (SELECT COUNT(*) FROM (
                SELECT {cohort}, treat FROM sampled_units GROUP BY ALL
            ))
        """
    ).fetchone()
    if source_cohorts != sampled_cohorts or source_strata != sampled_strata:
        raise AssertionError(
            f"{spec.filename}: sampling lost cohorts or treatment strata: "
            f"cohorts={sampled_cohorts}/{source_cohorts}, "
            f"strata={sampled_strata}/{source_strata}"
        )

    join_terms = [
        f"p.{key} IS NOT DISTINCT FROM u.{key}" for key in keys
    ]
    sample_csv.parent.mkdir(parents=True, exist_ok=True)
    copy_result = con.execute(
        f"""
        COPY (
            SELECT p.*
            FROM {source} AS p
            SEMI JOIN sampled_units AS u
              ON {' AND '.join(join_terms)}
        ) TO {sql_string(sample_csv)}
        (FORMAT CSV, HEADER TRUE)
        """
    ).fetchone()
    output_rows = int(copy_result[0]) if copy_result else -1

    source_rows, source_units = con.execute(
        "SELECT SUM(unit_rows), COUNT(*) FROM unit_arms"
    ).fetchone()
    sample_units, expected_rows = con.execute(
        "SELECT COUNT(*), SUM(unit_rows) FROM sampled_units"
    ).fetchone()
    if output_rows != expected_rows:
        raise AssertionError(
            f"{spec.filename}: output rows {output_rows:,} != expected {expected_rows:,}"
        )

    arm_summary = con.execute(
        """
        SELECT source.treat,
               source.source_units,
               sampled.sampled_units
        FROM (
            SELECT treat, COUNT(*) AS source_units
            FROM unit_arms
            GROUP BY treat
        ) AS source
        JOIN (
            SELECT treat, COUNT(*) AS sampled_units
            FROM sampled_units
            GROUP BY treat
        ) AS sampled USING (treat)
        ORDER BY source.treat
        """
    ).fetchall()
    logging.info(
        "DONE %s -> %s | rows=%s/%s | units=%s/%s | cohorts=%s | strata=%s",
        spec.filename,
        sample_csv.name,
        f"{output_rows:,}",
        f"{source_rows:,}",
        f"{sample_units:,}",
        f"{source_units:,}",
        f"{sampled_cohorts:,}",
        f"{sampled_strata:,}",
    )
    for arm, denominator, selected in arm_summary:
        logging.info(
            "  treat=%s sampled unit-cohorts=%s/%s",
            arm,
            f"{selected:,}",
            f"{denominator:,}",
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sample 0.5% of treated and control units in every cohort."
    )
    parser.add_argument("--intermediate", type=Path, required=True)
    parser.add_argument("--rate", type=float, default=0.005)
    parser.add_argument(
        "--minimum-units",
        type=int,
        default=30,
        help=(
            "Minimum complete analytical units retained in each cohort x "
            "treatment-arm stratum; all units are kept when fewer exist."
        ),
    )
    parser.add_argument("--seed", type=int, default=20260824)
    parser.add_argument("--threads", type=int, default=8)
    parser.add_argument("--memory-limit", default="48GB")
    parser.add_argument("--temp-directory", type=Path, default=None)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument(
        "--dataset",
        action="append",
        choices=[spec.filename for spec in DATASETS],
        help="Generate only selected inputs; repeat the option as needed.",
    )
    args = parser.parse_args()
    if not 0 < args.rate <= 1:
        parser.error("--rate must be greater than zero and at most one")
    if args.minimum_units < 1:
        parser.error("--minimum-units must be at least one")
    return args


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    args.intermediate = args.intermediate.resolve()
    temp_directory = (
        args.temp_directory.resolve()
        if args.temp_directory
        else args.intermediate / "main_analysis_sample_duckdb_tmp"
    )
    temp_directory.mkdir(parents=True, exist_ok=True)

    selected = [
        spec for spec in DATASETS
        if not args.dataset or spec.filename in set(args.dataset)
    ]
    con = duckdb.connect()
    con.execute(f"SET threads={int(args.threads)}")
    con.execute(f"SET memory_limit={sql_string(args.memory_limit)}")
    con.execute(f"SET temp_directory={sql_string(temp_directory)}")
    con.execute("SET preserve_insertion_order=false")
    try:
        for spec in selected:
            build_one(
                con,
                spec,
                args.intermediate,
                args.rate,
                args.minimum_units,
                args.seed,
                args.overwrite,
            )
    finally:
        con.close()
    logging.info("All %s main-analysis samples completed.", len(selected))
    return 0


if __name__ == "__main__":
    sys.exit(main())

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
    duckdb_table: str = "final_stack"


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
    DatasetSpec("stacked_downup_13kmpl.csv", "cohort", ("unique_small_grid_id",)),
    DatasetSpec("stacked_downup_neigh.csv", "cohort", ("unique_pair",)),
)


def sql_string(value: str | Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def qid(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def output_path(input_path: Path) -> Path:
    return input_path.with_name(f"{input_path.stem}_sample.csv")


def source_sql(path: Path, duckdb_alias: str | None = None, table: str = "final_stack") -> str:
    if path.suffix.lower() in {".db", ".duckdb"}:
        if not duckdb_alias:
            raise ValueError(f"A DuckDB alias is required for database source {path}")
        return f"{qid(duckdb_alias)}.{qid(table)}"
    # all_varchar avoids expensive or unstable whole-file type inference. The
    # CSV text is preserved; only treat is cast temporarily for validation.
    return (
        f"read_csv_auto({sql_string(path)}, header=true, all_varchar=true, "
        "null_padding=true)"
    )


def describe_columns(
    con: duckdb.DuckDBPyConnection,
    path: Path,
    duckdb_alias: str | None = None,
    table: str = "final_stack",
) -> set[str]:
    return {
        row[0]
        for row in con.execute(
            f"DESCRIBE SELECT * FROM {source_sql(path, duckdb_alias, table)}"
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
    source_override: Path | None,
) -> None:
    input_path = source_override or (intermediate / spec.filename)
    sample_csv = output_path(intermediate / spec.filename)
    if not input_path.is_file():
        raise FileNotFoundError(f"Required main-analysis input is absent: {input_path}")
    if sample_csv.exists() and not overwrite:
        raise FileExistsError(
            f"Sample already exists: {sample_csv}. Pass --overwrite to replace it."
        )

    duckdb_alias = None
    if input_path.suffix.lower() in {".db", ".duckdb"}:
        duckdb_alias = "sample_source"
        con.execute(f"DETACH {qid(duckdb_alias)}") if duckdb_alias in {
            row[0]
            for row in con.execute(
                "SELECT database_name FROM duckdb_databases()"
            ).fetchall()
        } else None
        con.execute(
            f"ATTACH {sql_string(input_path)} AS {qid(duckdb_alias)} (READ_ONLY)"
        )

    columns = describe_columns(con, input_path, duckdb_alias, spec.duckdb_table)
    required = {spec.cohort_col, "treat", *spec.unit_cols}
    missing = sorted(required - columns)
    if missing:
        raise ValueError(f"{spec.filename} is missing required columns: {missing}")

    cohort = qid(spec.cohort_col)
    units = [qid(col) for col in spec.unit_cols]
    keys = [cohort, *units]
    key_csv = ", ".join(keys)
    source = source_sql(input_path, duckdb_alias, spec.duckdb_table)

    logging.info("START %s | source=%s", spec.filename, input_path)
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
    if duckdb_alias:
        con.execute(f"DETACH {qid(duckdb_alias)}")


def build_master_attachment(
    con: duckdb.DuckDBPyConnection,
    intermediate: Path,
    overwrite: bool,
) -> None:
    """Retain master rows needed by either sampled main stacked dataset."""
    area_sample = intermediate / "combined_dt_sample.csv"
    pop_sample = intermediate / "combined_dt_pop_sample.csv"
    master_parquet = intermediate / "0_master_dataset.parquet"
    output_csv = intermediate / "0_master_dataset_sample.csv"
    for required in (area_sample, pop_sample, master_parquet):
        if not required.is_file():
            raise FileNotFoundError(
                f"Required master-attachment input is absent: {required}"
            )
    if output_csv.exists() and not overwrite:
        raise FileExistsError(
            f"Sample already exists: {output_csv}. Pass --overwrite to replace it."
        )

    logging.info("START 0_master_dataset.parquet attachment sample")
    con.execute("DROP TABLE IF EXISTS sampled_master_keys")
    con.execute(
        f"""
        CREATE TEMP TABLE sampled_master_keys AS
        SELECT DISTINCT
            CAST(unique_small_grid_id AS VARCHAR) AS unique_small_grid_id,
            TRY_CAST(year AS INTEGER) AS year,
            TRY_CAST(month AS INTEGER) AS month
        FROM (
            SELECT unique_small_grid_id, year, month
            FROM {source_sql(area_sample)}
            UNION ALL
            SELECT unique_small_grid_id, year, month
            FROM {source_sql(pop_sample)}
        )
        """
    )
    key_count = con.execute(
        "SELECT COUNT(*) FROM sampled_master_keys"
    ).fetchone()[0]
    copy_result = con.execute(
        f"""
        COPY (
            SELECT m.*
            FROM read_parquet({sql_string(master_parquet)}) AS m
            SEMI JOIN sampled_master_keys AS k
              ON CAST(m.unique_small_grid_id AS VARCHAR) = k.unique_small_grid_id
             AND TRY_CAST(m.year AS INTEGER) = k.year
             AND TRY_CAST(m.month AS INTEGER) = k.month
        ) TO {sql_string(output_csv)}
        (FORMAT CSV, HEADER TRUE)
        """
    ).fetchone()
    output_rows = int(copy_result[0]) if copy_result else -1
    if output_rows != key_count:
        raise AssertionError(
            "0_master_dataset_sample.csv does not match the union of sampled "
            f"stacked keys: rows={output_rows:,}, keys={key_count:,}"
        )
    logging.info(
        "DONE 0_master_dataset.parquet -> %s | rows=%s",
        output_csv.name,
        f"{output_rows:,}",
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
        "--master-attachment-only",
        action="store_true",
        help=(
            "Only create 0_master_dataset_sample.csv from the grid-month keys "
            "already present in the two sampled main stacks."
        ),
    )
    parser.add_argument(
        "--dataset",
        action="append",
        choices=[spec.filename for spec in DATASETS],
        help="Generate only selected inputs; repeat the option as needed.",
    )
    parser.add_argument(
        "--source-override",
        action="append",
        default=[],
        metavar="FILENAME=PATH",
        help=(
            "Override a dataset source. PATH may be a CSV or a DuckDB database; "
            "database sources are read from final_stack. Repeat as needed."
        ),
    )
    args = parser.parse_args()
    if not 0 < args.rate <= 1:
        parser.error("--rate must be greater than zero and at most one")
    if args.minimum_units < 1:
        parser.error("--minimum-units must be at least one")
    overrides: dict[str, Path] = {}
    valid_names = {spec.filename for spec in DATASETS}
    for raw in args.source_override:
        if "=" not in raw:
            parser.error("--source-override must have the form FILENAME=PATH")
        filename, raw_path = raw.split("=", 1)
        if filename not in valid_names:
            parser.error(f"Unknown override dataset: {filename}")
        overrides[filename] = Path(raw_path).expanduser().resolve()
    args.source_overrides = overrides
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

    selected = [] if args.master_attachment_only else [
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
                args.source_overrides.get(spec.filename),
            )
        if args.master_attachment_only or not args.dataset:
            build_master_attachment(con, args.intermediate, args.overwrite)
    finally:
        con.close()
    logging.info("All %s stacked samples and master attachment completed.", len(selected))
    return 0


if __name__ == "__main__":
    sys.exit(main())

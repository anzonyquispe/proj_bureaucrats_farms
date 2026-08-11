#!/usr/bin/env python3
"""Build the politician-characteristics stack within province-election cohorts.

The source treatment is ``self_profession_nomiss``. Each province is processed
separately by the standard clean-spell stacking engine, which guarantees that a
treated grid and its eligible controls belong to the same province and switch
date. The province-specific results are combined into one CSV with both the
calendar switching month (``cohort``) and a unique province-election identifier
(``cohort_id`` / ``cohort_province``).

The standard run accepts switching cohorts through December 2022. This yields
the eight requested province-election cohorts while retaining the full master
panel, including later observations, in their post-treatment windows.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import shutil
import sys
from pathlib import Path
from typing import Sequence

import duckdb

from _stacked_duckdb_core import (
    configure_connection,
    main as run_stack_engine,
    qid,
    qstr,
    source_expression,
)
from build_all_stacked_datasets_duckdb import (
    CLUSTER_INTERMEDIATE,
    LOCAL_INTERMEDIATE,
    SPEC_BY_NAME,
    columns_for,
    preflight_input,
)


TREATMENT_COLUMN = "self_profession_nomiss"
OUTPUT_NAME = "politicians_characteristics_byprov.csv"
DATABASE_NAME = "politicians_characteristics_byprov.db"
MANIFEST_NAME = "politicians_characteristics_byprov_manifest.csv"
WORK_DIRECTORY_NAME = "politicians_characteristics_byprov_work"
DEFAULT_LAST_COHORT_YEAR = 2022
DEFAULT_LAST_COHORT_MONTH = 12
DEFAULT_EXPECTED_COHORTS = 8
SPECIFICATION = SPEC_BY_NAME[TREATMENT_COLUMN]


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
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument(
        "--database",
        type=Path,
        default=None,
        help="Final DuckDB containing the combined stack and cohort manifest.",
    )
    parser.add_argument("--work-directory", type=Path, default=None)
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument("--memory-limit", default="90GB")
    parser.add_argument("--checkpoint-every", type=int, default=1)
    parser.add_argument("--csv-sample-size", type=int, default=100_000)
    parser.add_argument("--last-cohort-year", type=int, default=DEFAULT_LAST_COHORT_YEAR)
    parser.add_argument("--last-cohort-month", type=int, default=DEFAULT_LAST_COHORT_MONTH)
    parser.add_argument("--expected-cohorts", type=int, default=DEFAULT_EXPECTED_COHORTS)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING"],
        default="INFO",
    )
    return parser.parse_args(argv)


def safe_slug(value: str) -> str:
    slug = "".join(character.lower() if character.isalnum() else "_" for character in value)
    return "_".join(part for part in slug.split("_") if part)


def remove_work_directory(path: Path, intermediate: Path) -> None:
    resolved = path.resolve()
    parent = intermediate.resolve()
    if resolved.parent != parent:
        raise ValueError(f"Refusing to remove unexpected work directory: {resolved}")
    if resolved.exists():
        shutil.rmtree(resolved)


def cohort_limit(args: argparse.Namespace) -> int:
    if not 1 <= args.last_cohort_month <= 12:
        raise ValueError("--last-cohort-month must be between 1 and 12.")
    if args.expected_cohorts < 1:
        raise ValueError("--expected-cohorts must be positive.")
    if args.threads < 1:
        raise ValueError("--threads must be positive.")
    return args.last_cohort_year * 12 + args.last_cohort_month


def pipeline_config(
    input_path: Path,
    selected_columns: Sequence[str],
    maximum_cohort: int,
    expected_cohorts: int,
) -> dict[str, object]:
    stat = input_path.stat()
    return {
        "schema_version": 1,
        "input": str(input_path.resolve()),
        "input_size": stat.st_size,
        "input_mtime_ns": stat.st_mtime_ns,
        "treatment": TREATMENT_COLUMN,
        "selected_columns": list(selected_columns),
        "maximum_cohort": maximum_cohort,
        "expected_cohorts": expected_cohorts,
    }


def inspect_cohorts(
    input_path: Path,
    csv_sample_size: int,
    maximum_cohort: int,
    expected_cohorts: int,
) -> list[tuple[str, int, int]]:
    connection = duckdb.connect()
    try:
        source_sql = source_expression(input_path, csv_sample_size)
        missing_province, missing_treatment, changing_province = connection.execute(
            f"""
            WITH unit_provinces AS (
                SELECT
                    unique_small_grid_id,
                    count(DISTINCT province) AS province_count
                FROM {source_sql}
                GROUP BY unique_small_grid_id
            )
            SELECT
                (SELECT count(*) FROM {source_sql} WHERE province IS NULL),
                (SELECT count(*) FROM {source_sql}
                 WHERE {qid(TREATMENT_COLUMN)} IS NULL),
                (SELECT count(*) FROM unit_provinces WHERE province_count <> 1)
            """
        ).fetchone()
        if missing_province:
            raise ValueError(f"Master input has {missing_province:,} missing provinces.")
        if missing_treatment:
            raise ValueError(
                f"Master input has {missing_treatment:,} missing {TREATMENT_COLUMN} values."
            )
        if changing_province:
            raise ValueError(
                f"Province changes within {changing_province:,} grid histories."
            )

        rows = connection.execute(
            f"""
            WITH histories AS (
                SELECT
                    unique_small_grid_id,
                    province,
                    year::INTEGER * 12 + month::INTEGER AS monthyear,
                    year_take,
                    month_take,
                    {qid(TREATMENT_COLUMN)} AS treatment,
                    lag({qid(TREATMENT_COLUMN)}) OVER (
                        PARTITION BY unique_small_grid_id
                        ORDER BY year, month
                    ) AS treatment_lag
                FROM {source_sql}
            ),
            switch_pairs AS (
                SELECT
                    province,
                    monthyear AS cohort,
                    count(DISTINCT unique_small_grid_id) AS switching_grids
                FROM histories
                WHERE treatment_lag = 0
                  AND treatment = 1
                  AND monthyear <= {maximum_cohort}
                GROUP BY province, monthyear
            )
            SELECT
                switch_pairs.province,
                switch_pairs.cohort,
                switch_pairs.switching_grids,
                count_if(
                    histories.year_take IS NULL
                    OR histories.month_take IS NULL
                    OR try_cast(histories.year_take AS INTEGER) * 12
                       + try_cast(histories.month_take AS INTEGER)
                       <> switch_pairs.cohort
                ) AS election_date_mismatches
            FROM switch_pairs
            JOIN histories
              ON histories.province = switch_pairs.province
             AND histories.monthyear = switch_pairs.cohort
            GROUP BY
                switch_pairs.province,
                switch_pairs.cohort,
                switch_pairs.switching_grids
            ORDER BY switch_pairs.cohort, switch_pairs.province
            """
        ).fetchall()
    finally:
        connection.close()

    mismatch_rows = sum(int(row[3]) for row in rows)
    if mismatch_rows:
        raise ValueError(
            f"{mismatch_rows:,} province-cohort rows do not match "
            "year_take/month_take."
        )
    cohorts = [
        (str(province), int(cohort), int(grids))
        for province, cohort, grids, _ in rows
    ]
    if len(cohorts) != expected_cohorts:
        details = ", ".join(
            f"{province}:{(cohort - 1) // 12:04d}-{(cohort - 1) % 12 + 1:02d}"
            for province, cohort, _ in cohorts
        )
        raise ValueError(
            f"Expected {expected_cohorts} province-election cohorts through "
            f"{(maximum_cohort - 1) // 12:04d}-{(maximum_cohort - 1) % 12 + 1:02d}, "
            f"but found {len(cohorts)}: {details}."
        )
    return cohorts


def create_province_source(
    input_path: Path,
    output_path: Path,
    province: str,
    selected_columns: Sequence[str],
    csv_sample_size: int,
    memory_limit: str,
    threads: int,
    temp_directory: Path,
) -> None:
    output_temp = output_path.with_name(output_path.name + ".tmp")
    if output_temp.exists():
        output_temp.unlink()
    connection = duckdb.connect()
    try:
        configure_connection(
            connection,
            memory_limit=memory_limit,
            threads=threads,
            temp_directory=temp_directory,
        )
        source_sql = source_expression(input_path, csv_sample_size)
        selection = ", ".join(qid(column) for column in selected_columns)
        connection.execute(
            f"""
            COPY (
                SELECT {selection}
                FROM {source_sql}
                WHERE province = {qstr(province)}
            )
            TO {qstr(output_temp)}
            (FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 262144)
            """
        )
    finally:
        connection.close()
    os.replace(output_temp, output_path)


def run_province_stack(
    args: argparse.Namespace,
    province: str,
    source_path: Path,
    work_directory: Path,
    selected_columns: Sequence[str],
    maximum_cohort: int,
) -> Path:
    slug = safe_slug(province)
    output_path = work_directory / f"stack_{slug}.csv"
    database_path = work_directory / f"stack_{slug}.db"
    engine_args = [
        "--input",
        str(source_path),
        "--output",
        str(output_path),
        "--database",
        str(database_path),
        "--temp-directory",
        str(work_directory / f"duckdb_tmp_{slug}"),
        "--treatment-col",
        TREATMENT_COLUMN,
        "--keep-cols",
        *selected_columns,
        "--cohort-max",
        str(maximum_cohort),
        "--threads",
        str(args.threads),
        "--memory-limit",
        args.memory_limit,
        "--checkpoint-every",
        str(args.checkpoint_every),
        "--csv-sample-size",
        str(args.csv_sample_size),
        "--log-level",
        args.log_level,
    ]
    if args.overwrite:
        engine_args.append("--overwrite")
    if SPECIFICATION.year_level_controls:
        engine_args.append("--year-level-controls")
    result = run_stack_engine(engine_args)
    if result:
        raise RuntimeError(f"Province stack failed for {province} with status {result}.")
    # The combined export reads final_stack directly from the province DuckDB.
    # The engine's intermediate province CSV is therefore redundant and can be
    # removed to avoid keeping a second full copy of the stacked observations.
    if output_path.exists():
        output_path.unlink()
    return database_path


def combined_union(database_aliases: Sequence[str]) -> str:
    return "\nUNION ALL\n".join(
        f"SELECT * FROM {qid(alias)}.final_stack" for alias in database_aliases
    )


def combine_stacks(
    database_paths: Sequence[tuple[str, Path]],
    output_path: Path,
    database_path: Path,
    manifest_path: Path,
    expected_pairs: set[tuple[str, int]],
    expected_cohorts: int,
    memory_limit: str,
    threads: int,
    temp_directory: Path,
) -> None:
    output_temp = output_path.with_name(output_path.name + ".tmp")
    database_temp = database_path.with_name(database_path.name + ".tmp")
    manifest_temp = manifest_path.with_name(manifest_path.name + ".tmp")
    for temp_path in (output_temp, database_temp, manifest_temp):
        if temp_path.exists():
            temp_path.unlink()
    connection = duckdb.connect(str(database_temp))
    try:
        configure_connection(
            connection,
            memory_limit=memory_limit,
            threads=threads,
            temp_directory=temp_directory,
        )
        aliases: list[str] = []
        for index, (_, province_database_path) in enumerate(database_paths):
            alias = f"province_{index}"
            connection.execute(
                f"ATTACH {qstr(province_database_path)} AS {qid(alias)} (READ_ONLY)"
            )
            aliases.append(alias)

        union_sql = combined_union(aliases)
        connection.execute(
            f"""
            CREATE TEMP TABLE cohort_map AS
            SELECT
                province,
                cohort,
                row_number() OVER (ORDER BY cohort, province)::INTEGER AS cohort_id
            FROM (
                SELECT DISTINCT province, cohort
                FROM ({union_sql})
            )
            """
        )
        connection.execute(
            f"""
            CREATE TABLE politicians_characteristics_byprov AS
            SELECT
                stacks.*,
                cohort_map.cohort_id,
                cast(floor((stacks.cohort - 1) / 12.0) AS INTEGER)
                    AS cohort_year,
                cast(((stacks.cohort - 1) % 12) + 1 AS INTEGER)
                    AS cohort_month,
                concat(
                    stacks.province,
                    '_',
                    cast(floor((stacks.cohort - 1) / 12.0) AS INTEGER),
                    '_',
                    lpad(cast(((stacks.cohort - 1) % 12) + 1 AS VARCHAR), 2, '0')
                ) AS cohort_province
            FROM ({union_sql}) AS stacks
            JOIN cohort_map USING (province, cohort)
            """
        )

        summary = connection.execute(
            """
            SELECT
                province,
                cohort,
                count(DISTINCT unique_small_grid_id) FILTER (WHERE treat = 1)
                    AS treated_grids,
                count(DISTINCT unique_small_grid_id) FILTER (WHERE treat = 0)
                    AS control_grids
            FROM politicians_characteristics_byprov
            GROUP BY province, cohort
            ORDER BY cohort, province
            """
        ).fetchall()
        actual_pairs = {(str(row[0]), int(row[1])) for row in summary}
        if len(summary) != expected_cohorts or actual_pairs != expected_pairs:
            raise ValueError(
                "Final province-election cohorts differ from the preflight cohorts."
            )
        without_comparison = [row for row in summary if not row[2] or not row[3]]
        if without_comparison:
            raise ValueError(
                "Every province-election cohort must contain treated and control grids; "
                f"failed cohorts: {without_comparison}."
            )

        connection.execute(
            f"""
            COPY (SELECT * FROM politicians_characteristics_byprov)
            TO {qstr(output_temp)}
            (FORMAT CSV, HEADER TRUE)
            """
        )
        connection.execute(
            f"""
            CREATE TABLE politicians_characteristics_byprov_manifest AS
            SELECT
                cohort_id,
                cohort_province,
                province,
                cohort,
                cast(floor((cohort - 1) / 12.0) AS INTEGER) AS cohort_year,
                cast(((cohort - 1) % 12) + 1 AS INTEGER) AS cohort_month,
                count(DISTINCT unique_small_grid_id)
                    FILTER (WHERE treat = 1) AS treated_grids,
                count(DISTINCT unique_small_grid_id)
                    FILTER (WHERE treat = 0) AS control_grids,
                count(*) FILTER (WHERE treat = 1) AS treated_rows,
                count(*) FILTER (WHERE treat = 0) AS control_rows,
                min(relative_monthyear) AS relative_month_min,
                max(relative_monthyear) AS relative_month_max
            FROM politicians_characteristics_byprov
            GROUP BY
                cohort_id, cohort_province, province, cohort
            ORDER BY cohort_id
            """
        )
        connection.execute(
            """
            CREATE VIEW final_stack AS
            SELECT * FROM politicians_characteristics_byprov
            """
        )
        connection.execute(
            f"""
            COPY (
                SELECT
                    *
                FROM politicians_characteristics_byprov_manifest
            )
            TO {qstr(manifest_temp)}
            (FORMAT CSV, HEADER TRUE)
            """
        )
        connection.execute("CHECKPOINT")
    finally:
        connection.close()

    os.replace(database_temp, database_path)
    os.replace(output_temp, output_path)
    os.replace(manifest_temp, manifest_path)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s | %(levelname)s | %(message)s",
    )
    maximum_cohort = cohort_limit(args)
    intermediate = args.intermediate.resolve()
    input_path = (
        args.input.resolve()
        if args.input
        else intermediate / "0_master_dataset.parquet"
    )
    output_path = args.output.resolve() if args.output else intermediate / OUTPUT_NAME
    database_path = (
        args.database.resolve()
        if args.database
        else intermediate / DATABASE_NAME
    )
    manifest_path = output_path.with_name(MANIFEST_NAME)
    work_directory = (
        args.work_directory.resolve()
        if args.work_directory
        else intermediate / WORK_DIRECTORY_NAME
    )
    selected_columns = columns_for(SPECIFICATION)

    source_columns = preflight_input(
        input_path,
        [SPECIFICATION],
        args.csv_sample_size,
    )
    missing_election_date = [
        column for column in ("year_take", "month_take")
        if column not in source_columns
    ]
    if missing_election_date:
        raise ValueError(
            "Master input is missing election-date columns: "
            + ", ".join(missing_election_date)
        )
    cohorts = inspect_cohorts(
        input_path,
        args.csv_sample_size,
        maximum_cohort,
        args.expected_cohorts,
    )
    logging.info("Input: %s", input_path)
    logging.info("Output: %s", output_path)
    logging.info("Database: %s", database_path)
    logging.info("Detected province-election cohorts: %s", len(cohorts))
    for province, cohort, switching_grids in cohorts:
        logging.info(
            "Cohort %s | %04d-%02d | switching grids=%s",
            province,
            (cohort - 1) // 12,
            (cohort - 1) % 12 + 1,
            f"{switching_grids:,}",
        )
    if args.dry_run:
        logging.info("Dry run completed; no outputs were written.")
        return 0

    intermediate.mkdir(parents=True, exist_ok=True)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    database_path.parent.mkdir(parents=True, exist_ok=True)
    if args.overwrite:
        remove_work_directory(work_directory, intermediate)
    work_directory.mkdir(parents=True, exist_ok=True)

    config_path = work_directory / "pipeline_config.json"
    expected_config = pipeline_config(
        input_path,
        selected_columns,
        maximum_cohort,
        args.expected_cohorts,
    )
    if config_path.exists():
        stored_config = json.loads(config_path.read_text(encoding="utf-8"))
        if stored_config != expected_config:
            raise RuntimeError(
                "Existing province work files were built from different settings; "
                "rerun with --overwrite."
            )
    else:
        config_path.write_text(
            json.dumps(expected_config, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    provinces = list(dict.fromkeys(province for province, _, _ in cohorts))
    database_paths: list[tuple[str, Path]] = []
    for index, province in enumerate(provinces, start=1):
        slug = safe_slug(province)
        source_path = work_directory / f"source_{slug}.parquet"
        if not source_path.exists():
            logging.info(
                "Preparing province %s/%s: %s",
                index,
                len(provinces),
                province,
            )
            create_province_source(
                input_path,
                source_path,
                province,
                selected_columns,
                args.csv_sample_size,
                args.memory_limit,
                args.threads,
                work_directory / f"source_tmp_{slug}",
            )
        logging.info("Stacking province: %s", province)
        province_database_path = run_province_stack(
            args,
            province,
            source_path,
            work_directory,
            selected_columns,
            maximum_cohort,
        )
        database_paths.append((province, province_database_path))

    combine_stacks(
        database_paths,
        output_path,
        database_path,
        manifest_path,
        {(province, cohort) for province, cohort, _ in cohorts},
        args.expected_cohorts,
        args.memory_limit,
        args.threads,
        work_directory / "combine_tmp",
    )
    logging.info("Completed province-election politician stack")
    logging.info("CSV: %s", output_path)
    logging.info("DuckDB: %s", database_path)
    logging.info("Manifest: %s", manifest_path)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        logging.error("Interrupted. Re-run without --overwrite to resume.")
        raise SystemExit(130)
    except Exception as exc:
        logging.exception("Province-election stack failed: %s", exc)
        raise SystemExit(1)

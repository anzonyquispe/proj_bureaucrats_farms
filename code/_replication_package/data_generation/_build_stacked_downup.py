#!/usr/bin/env python3
"""Build the area-based stacked downwind/upwind panel with DuckDB.

The implementation reproduces the clean-spell rules in the former R builder,
uses ``downup_ac_area`` as treatment, and restricts all cohort detection and
stacked observations to January 2012--August 2022. It writes a compressed
Parquet working file and the combined Stata file used by the regressions.
"""

from __future__ import annotations

import argparse
import logging
import os
import shutil
import sys
from pathlib import Path

try:
    import duckdb
    import pandas as pd
except ImportError as exc:  # pragma: no cover
    raise SystemExit("This script requires duckdb, pandas, and pyarrow.") from exc


CLUSTER_INTERMEDIATE = Path(
    "/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate"
)
LOCAL_INTERMEDIATE = Path(
    r"C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms"
    r"\data_output\intermediate"
)


def default_intermediate() -> Path:
    return LOCAL_INTERMEDIATE if LOCAL_INTERMEDIATE.exists() else CLUSTER_INTERMEDIATE


def sql_string(value: str | Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def remove_exact_path(path: Path, allowed_parent: Path) -> None:
    resolved = path.resolve()
    parent = allowed_parent.resolve()
    if resolved.parent != parent:
        raise ValueError(f"Refusing to remove path outside {parent}: {resolved}")
    if resolved.is_dir():
        shutil.rmtree(resolved)
    elif resolved.exists():
        resolved.unlink()


def parse_args(
    default_treatment: str = "downup_ac_area",
    default_treatment_output_name: str = "downup_ac",
    default_output_stem: str = "combined_dt",
) -> argparse.Namespace:
    intermediate = default_intermediate()
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--intermediate", type=Path, default=intermediate)
    parser.add_argument("--input", type=Path, default=None)
    parser.add_argument("--treatment", default=default_treatment)
    parser.add_argument(
        "--treatment-output-name",
        default=default_treatment_output_name,
    )
    parser.add_argument("--output-stem", default=default_output_stem)
    parser.add_argument("--cutoff-year", type=int, default=2022)
    parser.add_argument("--cutoff-month", type=int, default=8)
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument("--memory-limit", default="90GB")
    parser.add_argument("--database", type=Path, default=None)
    parser.add_argument("--temp-directory", type=Path, default=None)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument(
        "--skip-dta",
        action="store_true",
        help="Write Parquet and manifest only (useful for diagnostics).",
    )
    return parser.parse_args()


def configure_paths(args: argparse.Namespace) -> dict[str, Path]:
    intermediate = args.intermediate.resolve()
    stem = args.output_stem
    return {
        "intermediate": intermediate,
        "input": (
            args.input.resolve()
            if args.input
            else intermediate / "0_master_dataset.parquet"
        ),
        "parquet": intermediate / f"{stem}.parquet",
        "dta": intermediate / f"{stem}.dta",
        "manifest": intermediate / f"{stem}_manifest.csv",
        "database": (
            args.database.resolve()
            if args.database
            else intermediate / f"{stem}.duckdb"
        ),
        "temp_directory": (
            args.temp_directory.resolve()
            if args.temp_directory
            else intermediate / f"{stem}_duckdb_tmp"
        ),
    }


def describe_columns(
    connection: duckdb.DuckDBPyConnection, input_sql: str
) -> set[str]:
    return {
        row[0]
        for row in connection.execute(
            f"DESCRIBE SELECT * FROM read_parquet({input_sql})"
        ).fetchall()
    }


def write_stata(parquet_path: Path, output_path: Path) -> None:
    """Write one regression-ready Stata 14+ file atomically."""
    temporary = output_path.with_name(output_path.name + ".tmp")
    if temporary.exists():
        remove_exact_path(temporary, temporary.parent)
    logging.info("Reading combined Parquet into memory for Stata export")
    frame = pd.read_parquet(parquet_path)
    for column in frame.select_dtypes(include=["string"]).columns:
        frame[column] = frame[column].astype(object)
    logging.info("Writing combined Stata file (%s rows)", f"{len(frame):,}")
    frame.to_stata(
        temporary,
        write_index=False,
        version=118,
        compression=None,
    )
    os.replace(temporary, output_path)


def run(
    default_treatment: str = "downup_ac_area",
    default_treatment_output_name: str = "downup_ac",
    default_output_stem: str = "combined_dt",
) -> int:
    args = parse_args(
        default_treatment,
        default_treatment_output_name,
        default_output_stem,
    )
    paths = configure_paths(args)
    if not paths["input"].is_file():
        raise FileNotFoundError(f"Missing master Parquet: {paths['input']}")
    paths["intermediate"].mkdir(parents=True, exist_ok=True)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    outputs = [paths["parquet"], paths["manifest"]]
    if not args.skip_dta:
        outputs.append(paths["dta"])
    existing = [path for path in outputs if path.exists()]
    if existing and not args.overwrite:
        raise FileExistsError(
            "Output exists; pass --overwrite: " + ", ".join(map(str, existing))
        )

    parquet_temp = paths["parquet"].with_name(paths["parquet"].name + ".tmp")
    manifest_temp = paths["manifest"].with_name(paths["manifest"].name + ".tmp")
    cleanup = [
        parquet_temp,
        manifest_temp,
        paths["database"],
        paths["temp_directory"],
    ]
    for path in cleanup:
        if path.exists():
            remove_exact_path(path, path.parent)
    paths["temp_directory"].mkdir(parents=True)

    connection = duckdb.connect(str(paths["database"]))
    try:
        connection.execute(f"SET threads = {max(1, args.threads)}")
        connection.execute(f"SET memory_limit = {sql_string(args.memory_limit)}")
        connection.execute(
            f"SET temp_directory = {sql_string(paths['temp_directory'])}"
        )
        connection.execute("SET preserve_insertion_order = false")

        source = sql_string(paths["input"])
        required = {
            "unique_small_grid_id",
            "month",
            "year",
            "monthyear",
            "province",
            "ac_uq_id",
            args.treatment,
            "count",
            "av_wind_speed",
            "wind_direction",
            "rice_prod_aclvl_ahigh",
        }
        missing = sorted(required.difference(describe_columns(connection, source)))
        if missing:
            raise KeyError(f"Master dataset is missing columns: {missing}")
        if not args.treatment.replace("_", "").isalnum():
            raise ValueError("Unsafe treatment column name.")
        if not args.treatment_output_name.replace("_", "").isalnum():
            raise ValueError("Unsafe treatment output name.")

        cutoff = args.cutoff_year * 12 + args.cutoff_month
        treatment = f'"{args.treatment}"'
        output_treatment = f'"{args.treatment_output_name}"'
        logging.info(
            "Loading panel through %04d-%02d using %s",
            args.cutoff_year,
            args.cutoff_month,
            args.treatment,
        )
        connection.execute(
            f"""
            CREATE TABLE panel AS
            SELECT
                unique_small_grid_id::BIGINT AS unique_small_grid_id,
                month::TINYINT AS month,
                year::SMALLINT AS year,
                monthyear::INTEGER AS monthyear,
                province,
                ac_uq_id::BIGINT AS ac_uq_id,
                {treatment}::TINYINT AS treatment,
                "count"::BIGINT AS "count",
                av_wind_speed::DOUBLE AS av_wind_speed,
                wind_direction::DOUBLE AS wind_direction,
                rice_prod_aclvl_ahigh::TINYINT AS rice_prod_aclvl_ahigh
            FROM read_parquet({source})
            WHERE monthyear <= {cutoff}
            """
        )
        rows, keys, invalid = connection.execute(
            """
            SELECT
                count(*),
                count(DISTINCT (unique_small_grid_id, monthyear)),
                count_if(treatment NOT IN (0, 1))
            FROM panel
            """
        ).fetchone()
        if rows != keys:
            raise ValueError("Filtered master is not unique by grid and month.")
        if invalid:
            raise ValueError(f"Treatment has {invalid:,} values outside 0/1.")

        # Each row stores the boundaries of its current zero/one spell. The
        # switch row also directly carries the treated grid's clean bounds.
        connection.execute(
            """
            CREATE TABLE panel_windows AS
            SELECT
                *,
                lag(treatment) OVER grid_time AS treatment_lag,
                max(CASE WHEN treatment = 1 THEN monthyear END) OVER (
                    PARTITION BY unique_small_grid_id
                    ORDER BY monthyear
                    ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                ) AS previous_one,
                min(CASE WHEN treatment = 1 THEN monthyear END) OVER (
                    PARTITION BY unique_small_grid_id
                    ORDER BY monthyear
                    ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
                ) AS next_one,
                min(CASE WHEN treatment = 0 THEN monthyear END) OVER (
                    PARTITION BY unique_small_grid_id
                    ORDER BY monthyear
                    ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
                ) AS next_zero
            FROM panel
            WINDOW grid_time AS (
                PARTITION BY unique_small_grid_id ORDER BY monthyear
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE switches AS
            SELECT
                unique_small_grid_id,
                monthyear AS cohort,
                previous_one AS treated_previous_one,
                next_zero AS treated_next_zero
            FROM panel_windows
            WHERE treatment_lag = 0 AND treatment = 1
            """
        )
        cohorts = connection.execute(
            "SELECT count(DISTINCT cohort) FROM switches"
        ).fetchone()[0]
        switch_count = connection.execute("SELECT count(*) FROM switches").fetchone()[0]
        if not cohorts:
            raise ValueError("No 0-to-1 treatment switches were found.")
        logging.info(
            "Input rows: %s; switches: %s; cohorts: %s",
            f"{rows:,}",
            f"{switch_count:,}",
            f"{cohorts:,}",
        )

        connection.execute(
            """
            CREATE TABLE cohort_windows AS
            SELECT
                s.cohort,
                min(p.monthyear) FILTER (WHERE p.treatment = 0) AS t_min,
                max(p.monthyear) FILTER (WHERE p.treatment = 1) AS t_max
            FROM switches AS s
            JOIN panel AS p USING (unique_small_grid_id)
            GROUP BY s.cohort
            HAVING t_min IS NOT NULL AND t_max IS NOT NULL
            """
        )

        columns = f"""
            p.unique_small_grid_id,
            p.month,
            p.year,
            p.monthyear,
            p.province,
            p.ac_uq_id,
            p.treatment AS {output_treatment},
            p."count",
            p.av_wind_speed,
            p.wind_direction,
            p.rice_prod_aclvl_ahigh
        """
        stacked_query = f"""
        WITH treated AS (
            SELECT
                {columns},
                1::TINYINT AS treat,
                s.cohort::INTEGER AS cohort,
                (p.monthyear - s.cohort)::INTEGER AS relative_monthyear
            FROM switches AS s
            JOIN cohort_windows AS w USING (cohort)
            JOIN panel AS p USING (unique_small_grid_id)
            WHERE p.monthyear BETWEEN w.t_min AND w.t_max
              AND (
                    s.treated_previous_one IS NULL
                    OR p.monthyear > s.treated_previous_one
              )
              AND (
                    s.treated_next_zero IS NULL
                    OR p.monthyear < s.treated_next_zero
              )
        ),
        controls AS (
            SELECT
                {columns},
                0::TINYINT AS treat,
                w.cohort::INTEGER AS cohort,
                (p.monthyear - w.cohort)::INTEGER AS relative_monthyear
            FROM panel_windows AS p
            JOIN cohort_windows AS w
              ON p.monthyear BETWEEN w.t_min AND w.t_max
             AND p.treatment = 0
             AND (p.previous_one IS NULL OR w.cohort > p.previous_one)
             AND (p.next_one IS NULL OR w.cohort < p.next_one)
        )
        SELECT * FROM treated
        UNION ALL
        SELECT * FROM controls
        """

        logging.info("Writing combined stacked Parquet")
        connection.execute(
            f"""
            COPY ({stacked_query})
            TO {sql_string(parquet_temp)}
            (FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 262144)
            """
        )
        os.replace(parquet_temp, paths["parquet"])

        final_source = sql_string(paths["parquet"])
        final_rows, final_cohorts, duplicate_keys = connection.execute(
            f"""
            SELECT
                count(*),
                count(DISTINCT cohort),
                count(*) - count(DISTINCT (
                    unique_small_grid_id, monthyear, cohort
                ))
            FROM read_parquet({final_source})
            """
        ).fetchone()
        if duplicate_keys:
            raise ValueError(
                f"Stacked output has {duplicate_keys:,} duplicate panel keys."
            )
        connection.execute(
            f"""
            COPY (
                SELECT
                    cohort,
                    count(*) AS rows,
                    count_if(treat = 1) AS treated_rows,
                    count_if(treat = 0) AS control_rows,
                    count(DISTINCT unique_small_grid_id) AS grids
                FROM read_parquet({final_source})
                GROUP BY cohort
                ORDER BY cohort
            )
            TO {sql_string(manifest_temp)}
            (FORMAT CSV, HEADER TRUE)
            """
        )
        os.replace(manifest_temp, paths["manifest"])
        logging.info(
            "Stacked rows: %s across %s cohorts",
            f"{final_rows:,}",
            f"{final_cohorts:,}",
        )

        if not args.skip_dta:
            # Release the materialized DuckDB panel before pandas allocates the
            # combined frame needed by Stata's non-streaming file writer.
            for table in (
                "cohort_windows",
                "switches",
                "panel_windows",
                "panel",
            ):
                connection.execute(f"DROP TABLE {table}")
            connection.execute("CHECKPOINT")
            write_stata(paths["parquet"], paths["dta"])

        logging.info("Parquet: %s", paths["parquet"])
        if not args.skip_dta:
            logging.info("Stata: %s", paths["dta"])
        logging.info("Manifest: %s", paths["manifest"])
        return 0
    finally:
        connection.close()
        for path in (parquet_temp, manifest_temp):
            if path.exists():
                remove_exact_path(path, path.parent)
        if paths["database"].exists():
            remove_exact_path(paths["database"], paths["database"].parent)
        if paths["temp_directory"].exists():
            remove_exact_path(paths["temp_directory"], paths["temp_directory"].parent)


if __name__ == "__main__":
    sys.exit(run())

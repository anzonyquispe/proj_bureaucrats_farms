#!/usr/bin/env python3
"""Aggregate raw fire detections to grid-year-month with DuckDB Spatial.

This replaces ``_3_fire_grid.R``. Fire CSV rows are converted to point
geometries, spatially joined to the raw grid polygons, and aggregated to
``unique_small_grid_id x year x month``. The output contains fire counts and
the arithmetic mean of the nonmissing ``brightness`` observations, matching
the R producer.
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path
from typing import Sequence

import duckdb

from _duckdb_spatial_utils import (
    cleanup_work_files,
    configure_duckdb,
    create_grid_table,
    default_sa_root,
    load_spatial,
    prepare_outputs,
    qid,
    relation_columns,
    require_columns,
    sql_string,
)


def defaults() -> dict[str, Path]:
    root = default_sa_root()
    intermediate = root / "proj_bureaucrats_farms" / "data_output" / "intermediate"
    return {
        "fires": root / "data" / "input" / "fires" / "1-fires20002024.csv",
        "grid": intermediate / "1-grid-generation.shp",
        "output": intermediate / "_3_fire_grid.csv",
    }


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    paths = defaults()
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--fires", type=Path, default=paths["fires"])
    parser.add_argument("--grid-shapefile", type=Path, default=paths["grid"])
    parser.add_argument("--output", type=Path, default=paths["output"])
    parser.add_argument("--database", type=Path, default=None)
    parser.add_argument("--temp-directory", type=Path, default=None)
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument("--memory-limit", default="90GB")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--keep-work-files", action="store_true")
    return parser.parse_args(argv)


def derive_work_paths(args: argparse.Namespace) -> tuple[Path, Path, Path]:
    output = args.output.resolve()
    database = (
        args.database.resolve()
        if args.database
        else output.with_suffix(".duckdb")
    )
    temp_directory = (
        args.temp_directory.resolve()
        if args.temp_directory
        else output.with_name(output.stem + "_duckdb_tmp")
    )
    return output, database, temp_directory


def build_fire_grid(
    connection: duckdb.DuckDBPyConnection,
    *,
    fires_path: Path,
    grid_path: Path,
) -> tuple[int, int]:
    create_grid_table(connection, grid_path)
    fire_relation = (
        "read_csv_auto("
        f"{sql_string(fires_path.resolve())}, header=true, sample_size=-1, "
        "all_varchar=true, ignore_errors=false)"
    )
    fire_columns = [name for name, _ in relation_columns(connection, fire_relation)]
    require_columns(
        fire_columns,
        ("longitude", "latitude", "acq_date", "brightness"),
        "raw fire CSV",
    )

    logging.info("Importing and validating raw fire detections")
    connection.execute(
        f"""
        CREATE TABLE fire_points AS
        SELECT
            TRY_CAST(longitude AS DOUBLE) AS longitude,
            TRY_CAST(latitude AS DOUBLE) AS latitude,
            TRY_CAST(acq_date AS DATE) AS acq_date,
            TRY_CAST(brightness AS DOUBLE) AS brightness,
            ST_Point(
                TRY_CAST(longitude AS DOUBLE),
                TRY_CAST(latitude AS DOUBLE)
            ) AS geometry
        FROM {fire_relation}
        WHERE TRY_CAST(longitude AS DOUBLE) BETWEEN -180.0 AND 180.0
          AND TRY_CAST(latitude AS DOUBLE) BETWEEN -90.0 AND 90.0
          AND TRY_CAST(acq_date AS DATE) IS NOT NULL
        """
    )
    raw_rows = int(
        connection.execute(f"SELECT count(*) FROM {fire_relation}").fetchone()[0]
    )
    valid_rows = int(connection.execute("SELECT count(*) FROM fire_points").fetchone()[0])
    logging.info("Raw fire rows: %s", f"{raw_rows:,}")
    logging.info("Valid dated/located fire rows: %s", f"{valid_rows:,}")
    logging.info("Dropped invalid fire rows: %s", f"{raw_rows - valid_rows:,}")
    connection.execute("ANALYZE fire_points")

    logging.info("Running DuckDB Spatial point-in-polygon join")
    connection.execute(
        """
        CREATE TABLE fire_grid AS
        SELECT
            g.unique_small_grid_id,
            year(f.acq_date)::SMALLINT AS year,
            month(f.acq_date)::TINYINT AS month,
            count(*)::BIGINT AS "count",
            avg(f.brightness)::DOUBLE AS mean_brightness
        FROM grids AS g
        JOIN fire_points AS f
          ON ST_Intersects(g.geometry, f.geometry)
        GROUP BY g.unique_small_grid_id, year(f.acq_date), month(f.acq_date)
        """
    )
    output_rows, output_keys, missing_brightness = connection.execute(
        """
        SELECT
            count(*),
            count(DISTINCT (unique_small_grid_id, year, month)),
            count_if(mean_brightness IS NULL)
        FROM fire_grid
        """
    ).fetchone()
    if output_rows != output_keys:
        raise ValueError("Fire output grid-year-month key is not unique.")
    if missing_brightness:
        raise ValueError(
            f"{missing_brightness:,} aggregated fire rows have no nonmissing brightness."
        )
    return int(output_rows), valid_rows


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    for source in (args.fires, args.grid_shapefile):
        if not source.is_file():
            raise FileNotFoundError(source)

    output, database, temp_directory = derive_work_paths(args)
    output_temp = prepare_outputs(
        output=output,
        database=database,
        temp_directory=temp_directory,
        overwrite=args.overwrite,
    )
    connection = duckdb.connect(str(database))
    try:
        configure_duckdb(
            connection,
            threads=args.threads,
            memory_limit=args.memory_limit,
            temp_directory=temp_directory,
        )
        load_spatial(connection)
        output_rows, valid_fire_rows = build_fire_grid(
            connection,
            fires_path=args.fires.resolve(),
            grid_path=args.grid_shapefile.resolve(),
        )
        connection.execute(
            f"""
            COPY (
                SELECT
                    unique_small_grid_id,
                    year,
                    month,
                    "count",
                    mean_brightness
                FROM fire_grid
                ORDER BY unique_small_grid_id, year, month
            ) TO {sql_string(output_temp)}
            (FORMAT CSV, HEADER TRUE)
            """
        )
        os.replace(output_temp, output)
        logging.info("Completed fire grid: %s", output)
        logging.info("Output grid-month rows: %s", f"{output_rows:,}")
        logging.info("Valid raw fire detections considered: %s", f"{valid_fire_rows:,}")
    finally:
        connection.close()
        if output_temp.exists():
            output_temp.unlink()
        if not args.keep_work_files:
            cleanup_work_files(database=database, temp_directory=temp_directory)
    return 0


if __name__ == "__main__":
    sys.exit(main())


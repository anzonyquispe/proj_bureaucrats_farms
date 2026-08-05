#!/usr/bin/env python3
"""Build monthly grid-level wind measures from the original raw wind files.

This combines the active calculations from ``1-clean-wind.R`` and
``_2_wind_direction_grid.R`` in one Python-native pipeline:

1. Read the 1990-2021 and 2022 ERA5-Land NetCDF files in bounded time chunks.
2. Read the 2023-2024 ERA5-Land CSV directly with DuckDB.
3. Calculate speed and retain the East/North vector components. Direction is
   always ``atan2(v10, u10)``: degrees counterclockwise from East.
4. Round longitude and latitude to two decimals before monthly aggregation.
5. Calculate monthly and trailing 10-observation mean directions from averaged
   vector components, avoiding invalid arithmetic averages of degree values.
6. Assign wind coordinates to raw grid polygons with DuckDB Spatial.

Only the final ``_2_wind_direction_grid.parquet`` and its DuckDB database are
retained. No RDS object or cleaned-hourly intermediate is created.
"""

from __future__ import annotations

import argparse
import logging
import math
import os
import sys
from pathlib import Path
from typing import Sequence

import duckdb
import numpy as np
import pandas as pd
from netCDF4 import Dataset, num2date

from _duckdb_spatial_utils import (
    configure_duckdb,
    create_grid_table,
    default_sa_root,
    load_spatial,
    prepare_outputs,
    qid,
    relation_columns,
    remove_exact_path,
    require_columns,
    sql_string,
)


def defaults() -> dict[str, Path]:
    root = default_sa_root()
    wind_directory = root / "data" / "input" / "wind" / "ecmwf"
    intermediate = root / "proj_bureaucrats_farms" / "data_output" / "intermediate"
    return {
        "historical": wind_directory / "era5-land-19902021-wind.nc",
        "year_2022": wind_directory / "era5-land-2022-wind.nc",
        "years_2023_2024": wind_directory / "era5-land-2023-2024.csv",
        "grid": intermediate / "1-grid-generation.shp",
        "output": intermediate / "_2_wind_direction_grid.parquet",
    }


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    paths = defaults()
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--historical-netcdf",
        type=Path,
        default=paths["historical"],
        help="ERA5-Land 1990-2021 u10/v10 NetCDF.",
    )
    parser.add_argument(
        "--year-2022-netcdf",
        type=Path,
        default=paths["year_2022"],
        help="ERA5-Land 2022 u10/v10 NetCDF.",
    )
    parser.add_argument(
        "--years-2023-2024-csv",
        type=Path,
        default=paths["years_2023_2024"],
        help="ERA5-Land 2023-2024 CSV containing u10, v10, year, and month.",
    )
    parser.add_argument("--grid-shapefile", type=Path, default=paths["grid"])
    parser.add_argument("--output", type=Path, default=paths["output"])
    parser.add_argument("--database", type=Path, default=None)
    parser.add_argument("--temp-directory", type=Path, default=None)
    parser.add_argument(
        "--netcdf-chunk-rows",
        type=int,
        default=2_000_000,
        help="Approximate maximum expanded rows loaded from NetCDF at once.",
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument("--memory-limit", default="120GB")
    parser.add_argument("--overwrite", action="store_true")
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


def find_netcdf_variable(
    dataset: Dataset,
    candidates: Sequence[str],
) -> str:
    lookup = {name.lower(): name for name in dataset.variables}
    for candidate in candidates:
        if candidate.lower() in lookup:
            return lookup[candidate.lower()]
    raise KeyError(
        f"None of {list(candidates)} exists in NetCDF variables "
        f"{list(dataset.variables)}."
    )


def numeric_array(values: object) -> np.ndarray:
    if np.ma.isMaskedArray(values):
        return np.asarray(np.ma.filled(values, np.nan), dtype=np.float64)
    return np.asarray(values, dtype=np.float64)


def broadcast_axis(
    values: np.ndarray,
    *,
    axis: int,
    shape: Sequence[int],
) -> np.ndarray:
    reshape = [1] * len(shape)
    reshape[axis] = len(values)
    return np.broadcast_to(values.reshape(reshape), shape).reshape(-1)


def initialize_monthly_accumulator(
    connection: duckdb.DuckDBPyConnection,
) -> None:
    connection.execute(
        """
        CREATE TABLE wind_monthly_parts (
            latitude DOUBLE,
            longitude DOUBLE,
            year SMALLINT,
            month TINYINT,
            wind_speed_sum DOUBLE,
            wind_speed_count BIGINT,
            eastward_wind_sum DOUBLE,
            northward_wind_sum DOUBLE,
            component_count BIGINT
        )
        """
    )


def append_chunk(
    connection: duckdb.DuckDBPyConnection,
    frame: pd.DataFrame,
) -> None:
    connection.register("_wind_chunk", frame)
    try:
        connection.execute(
            """
            INSERT INTO wind_monthly_parts
            SELECT
                latitude::DOUBLE,
                longitude::DOUBLE,
                year::SMALLINT,
                month::TINYINT,
                sum(wind_speed)::DOUBLE,
                count(wind_speed)::BIGINT,
                sum(u10)::DOUBLE,
                sum(v10)::DOUBLE,
                count(u10)::BIGINT
            FROM _wind_chunk
            GROUP BY latitude, longitude, year, month
            """
        )
    finally:
        connection.unregister("_wind_chunk")


def import_netcdf(
    connection: duckdb.DuckDBPyConnection,
    path: Path,
    *,
    target_chunk_rows: int,
) -> int:
    logging.info("Reading NetCDF in bounded chunks: %s", path)
    with Dataset(path, mode="r") as dataset:
        u_name = find_netcdf_variable(dataset, ("u10",))
        v_name = find_netcdf_variable(dataset, ("v10",))
        time_name = find_netcdf_variable(dataset, ("time", "valid_time"))
        latitude_name = find_netcdf_variable(dataset, ("latitude", "lat"))
        longitude_name = find_netcdf_variable(dataset, ("longitude", "lon"))

        u_variable = dataset.variables[u_name]
        v_variable = dataset.variables[v_name]
        if u_variable.dimensions != v_variable.dimensions:
            raise ValueError(
                f"u10 dimensions {u_variable.dimensions} do not match "
                f"v10 dimensions {v_variable.dimensions} in {path}."
            )
        dimensions = list(u_variable.dimensions)
        time_variable = dataset.variables[time_name]
        latitude_variable = dataset.variables[latitude_name]
        longitude_variable = dataset.variables[longitude_name]
        if not (
            len(time_variable.dimensions) == 1
            and len(latitude_variable.dimensions) == 1
            and len(longitude_variable.dimensions) == 1
        ):
            raise ValueError("Time, latitude, and longitude coordinates must be 1-D.")

        time_dimension = time_variable.dimensions[0]
        latitude_dimension = latitude_variable.dimensions[0]
        longitude_dimension = longitude_variable.dimensions[0]
        for dimension in (time_dimension, latitude_dimension, longitude_dimension):
            if dimension not in dimensions:
                raise ValueError(
                    f"Coordinate dimension {dimension!r} is absent from "
                    f"u10 dimensions {dimensions}."
                )
        time_axis = dimensions.index(time_dimension)
        latitude_axis = dimensions.index(latitude_dimension)
        longitude_axis = dimensions.index(longitude_dimension)

        time_count = len(dataset.dimensions[time_dimension])
        expanded_rows_per_time = math.prod(
            len(dataset.dimensions[dimension])
            for index, dimension in enumerate(dimensions)
            if index != time_axis
        )
        times_per_chunk = max(1, target_chunk_rows // expanded_rows_per_time)
        latitude_values = numeric_array(latitude_variable[:])
        longitude_values = numeric_array(longitude_variable[:])
        time_units = getattr(time_variable, "units", None)
        if not time_units:
            raise ValueError(f"NetCDF time variable in {path} has no units.")
        calendar = getattr(time_variable, "calendar", "standard")

        imported_rows = 0
        chunk_number = 0
        for start in range(0, time_count, times_per_chunk):
            stop = min(start + times_per_chunk, time_count)
            selection = [slice(None)] * len(dimensions)
            selection[time_axis] = slice(start, stop)
            u_values = numeric_array(u_variable[tuple(selection)])
            v_values = numeric_array(v_variable[tuple(selection)])
            if u_values.shape != v_values.shape:
                raise ValueError("u10 and v10 chunk shapes disagree.")

            decoded_dates = num2date(
                time_variable[start:stop],
                units=time_units,
                calendar=calendar,
                only_use_cftime_datetimes=True,
            )
            years = np.fromiter(
                (value.year for value in decoded_dates),
                dtype=np.int16,
                count=stop - start,
            )
            months = np.fromiter(
                (value.month for value in decoded_dates),
                dtype=np.int8,
                count=stop - start,
            )
            shape = u_values.shape
            latitude = np.round(
                broadcast_axis(latitude_values, axis=latitude_axis, shape=shape),
                2,
            )
            longitude = np.round(
                broadcast_axis(longitude_values, axis=longitude_axis, shape=shape),
                2,
            )
            year = broadcast_axis(years, axis=time_axis, shape=shape)
            month = broadcast_axis(months, axis=time_axis, shape=shape)
            u_flat = u_values.reshape(-1)
            v_flat = v_values.reshape(-1)
            valid_components = np.isfinite(u_flat) & np.isfinite(v_flat)
            paired_u = np.where(valid_components, u_flat, np.nan)
            paired_v = np.where(valid_components, v_flat, np.nan)
            frame = pd.DataFrame(
                {
                    "latitude": latitude,
                    "longitude": longitude,
                    "year": year,
                    "month": month,
                    "u10": paired_u,
                    "v10": paired_v,
                    "wind_speed": np.hypot(paired_u, paired_v),
                }
            )
            valid_coordinates = (
                frame["latitude"].between(-90.0, 90.0)
                & frame["longitude"].between(-180.0, 360.0)
            )
            frame = frame.loc[valid_coordinates]
            append_chunk(connection, frame)
            imported_rows += len(frame)
            chunk_number += 1
            if chunk_number == 1 or chunk_number % 25 == 0 or stop == time_count:
                logging.info(
                    "%s | chunk=%s | time=%s/%s | expanded_rows=%s",
                    path.name,
                    f"{chunk_number:,}",
                    f"{stop:,}",
                    f"{time_count:,}",
                    f"{imported_rows:,}",
                )
            del frame, u_values, v_values

    connection.execute("CHECKPOINT")
    return imported_rows


def import_recent_csv(
    connection: duckdb.DuckDBPyConnection,
    path: Path,
) -> int:
    logging.info("Reading 2023-2024 wind CSV with DuckDB: %s", path)
    relation = (
        "read_csv_auto("
        f"{sql_string(path.resolve())}, header=true, sample_size=-1, "
        "all_varchar=false, ignore_errors=false)"
    )
    columns = [name for name, _ in relation_columns(connection, relation)]
    require_columns(
        columns,
        ("longitude", "latitude", "year", "month", "u10", "v10"),
        "2023-2024 wind CSV",
    )
    before = int(
        connection.execute("SELECT count(*) FROM wind_monthly_parts").fetchone()[0]
    )
    connection.execute(
        f"""
        INSERT INTO wind_monthly_parts
        WITH cleaned AS (
            SELECT
                round(TRY_CAST(latitude AS DOUBLE), 2) AS latitude,
                round(TRY_CAST(longitude AS DOUBLE), 2) AS longitude,
                TRY_CAST(year AS SMALLINT) AS year,
                TRY_CAST(month AS TINYINT) AS month,
                TRY_CAST(u10 AS DOUBLE) AS u10,
                TRY_CAST(v10 AS DOUBLE) AS v10
            FROM {relation}
        ), calculated AS (
            SELECT
                latitude,
                longitude,
                year,
                month,
                u10,
                v10,
                sqrt(u10 * u10 + v10 * v10) AS wind_speed
            FROM cleaned
            WHERE latitude BETWEEN -90.0 AND 90.0
              AND longitude BETWEEN -180.0 AND 360.0
              AND year IS NOT NULL
              AND month BETWEEN 1 AND 12
              AND u10 IS NOT NULL
              AND v10 IS NOT NULL
              AND isfinite(u10)
              AND isfinite(v10)
        )
        SELECT
            latitude,
            longitude,
            year,
            month,
            sum(wind_speed)::DOUBLE,
            count(wind_speed)::BIGINT,
            sum(u10)::DOUBLE,
            sum(v10)::DOUBLE,
            count(u10)::BIGINT
        FROM calculated
        GROUP BY latitude, longitude, year, month
        """
    )
    after = int(
        connection.execute("SELECT count(*) FROM wind_monthly_parts").fetchone()[0]
    )
    connection.execute("CHECKPOINT")
    return after - before


def build_monthly_wind(
    connection: duckdb.DuckDBPyConnection,
) -> tuple[int, int]:
    connection.execute(
        """
        CREATE TABLE wind_monthly AS
        SELECT
            latitude,
            longitude,
            year,
            month,
            sum(wind_speed_sum) / nullif(sum(wind_speed_count), 0)
                AS wind_speed_av_cellid_month,
            sum(eastward_wind_sum) / nullif(sum(component_count), 0)
                AS eastward_wind_av_cellid_month,
            sum(northward_wind_sum) / nullif(sum(component_count), 0)
                AS northward_wind_av_cellid_month,
            degrees(atan2(
                sum(northward_wind_sum),
                sum(eastward_wind_sum)
            )) AS wind_direction_av_cellid_month
        FROM wind_monthly_parts
        GROUP BY latitude, longitude, year, month
        """
    )
    monthly_rows = int(connection.execute("SELECT count(*) FROM wind_monthly").fetchone()[0])
    connection.execute(
        """
        CREATE TABLE wind_monthly_rolling AS
        SELECT
            latitude,
            longitude,
            year,
            month,
            wind_speed_av_cellid_month,
            wind_direction_av_cellid_month,
            eastward_wind_av_cellid_month,
            northward_wind_av_cellid_month,
            CASE
                WHEN count(*) OVER rolling_window = 10
                 AND count(wind_speed_av_cellid_month) OVER rolling_window = 10
                THEN avg(wind_speed_av_cellid_month) OVER rolling_window
            END::DOUBLE AS rollav_wind_speed_cellid_month,
            CASE
                WHEN count(*) OVER rolling_window = 10
                 AND count(eastward_wind_av_cellid_month)
                     OVER rolling_window = 10
                 AND count(northward_wind_av_cellid_month)
                     OVER rolling_window = 10
                THEN degrees(atan2(
                    sum(northward_wind_av_cellid_month) OVER rolling_window,
                    sum(eastward_wind_av_cellid_month) OVER rolling_window
                ))
            END::DOUBLE AS rollav_wind_direction_cellid_month
        FROM wind_monthly
        WINDOW rolling_window AS (
            PARTITION BY latitude, longitude, month
            ORDER BY year
            ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
        )
        """
    )
    wind_cells = int(
        connection.execute(
            "SELECT count(DISTINCT (longitude, latitude)) FROM wind_monthly"
        ).fetchone()[0]
    )
    connection.execute("ANALYZE wind_monthly_rolling")
    return monthly_rows, wind_cells


def build_grid_crosswalk(
    connection: duckdb.DuckDBPyConnection,
    grid_path: Path,
) -> list[str]:
    grid_attributes = create_grid_table(connection, grid_path)
    connection.execute(
        """
        CREATE TABLE wind_cells AS
        SELECT
            row_number() OVER (ORDER BY latitude, longitude)::BIGINT
                AS cellid_wind,
            longitude,
            latitude,
            ST_Point(longitude, latitude) AS geometry
        FROM (
            SELECT DISTINCT latitude, longitude
            FROM wind_monthly_rolling
        )
        """
    )

    attributes_sql = ""
    if grid_attributes:
        attributes_sql = ",\n            ".join(
            f"g.{qid(column)}" for column in grid_attributes
        )
        attributes_sql += ",\n            "
    connection.execute(
        f"""
        CREATE TABLE grid_wind_crosswalk AS
        SELECT
            w.cellid_wind,
            {attributes_sql}
            g.unique_small_grid_id,
            w.longitude,
            w.latitude
        FROM grids AS g
        JOIN wind_cells AS w
          ON ST_Intersects(g.geometry, w.geometry)
        """
    )
    missing_grids, multi_cell_grids = connection.execute(
        """
        SELECT
            (
                SELECT count(*)
                FROM grids AS g
                LEFT JOIN grid_wind_crosswalk AS x
                  USING (unique_small_grid_id)
                WHERE x.unique_small_grid_id IS NULL
            ),
            (
                SELECT count(*)
                FROM (
                    SELECT unique_small_grid_id
                    FROM grid_wind_crosswalk
                    GROUP BY unique_small_grid_id
                    HAVING count(*) <> 1
                )
            )
        """
    ).fetchone()
    if missing_grids or multi_cell_grids:
        raise ValueError(
            "The wind-grid crosswalk must contain exactly one wind point per grid: "
            f"missing grids={missing_grids:,}, multi-cell grids={multi_cell_grids:,}."
        )
    connection.execute("ANALYZE grid_wind_crosswalk")
    return grid_attributes


def build_output_table(
    connection: duckdb.DuckDBPyConnection,
    grid_attributes: Sequence[str],
) -> int:
    attributes_sql = ""
    if grid_attributes:
        attributes_sql = ",\n            ".join(
            f"x.{qid(column)}" for column in grid_attributes
        )
        attributes_sql += ",\n            "
    connection.execute(
        f"""
        CREATE TABLE wind_grid AS
        SELECT
            x.cellid_wind,
            {attributes_sql}
            x.unique_small_grid_id,
            x.longitude,
            x.latitude,
            w.year,
            w.month,
            w.wind_speed_av_cellid_month,
            w.wind_direction_av_cellid_month,
            w.rollav_wind_speed_cellid_month,
            w.rollav_wind_direction_cellid_month
        FROM grid_wind_crosswalk AS x
        JOIN wind_monthly_rolling AS w
          USING (longitude, latitude)
        """
    )
    rows, keys, invalid_direction = connection.execute(
        """
        SELECT
            count(*),
            count(DISTINCT (unique_small_grid_id, year, month)),
            count_if(
                (
                    wind_direction_av_cellid_month IS NOT NULL
                    AND NOT wind_direction_av_cellid_month BETWEEN -180.0 AND 180.0
                ) OR (
                    rollav_wind_direction_cellid_month IS NOT NULL
                    AND NOT rollav_wind_direction_cellid_month BETWEEN -180.0 AND 180.0
                )
            )
        FROM wind_grid
        """
    ).fetchone()
    if rows != keys:
        raise ValueError("Wind output grid-year-month key is not unique.")
    if invalid_direction:
        raise ValueError(
            f"Wind output has {invalid_direction:,} East-referenced angles "
            "outside [-180, 180]."
        )
    return int(rows)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    if args.netcdf_chunk_rows <= 0:
        raise ValueError("--netcdf-chunk-rows must be positive.")
    sources = (
        args.historical_netcdf,
        args.year_2022_netcdf,
        args.years_2023_2024_csv,
        args.grid_shapefile,
    )
    for source in sources:
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
        initialize_monthly_accumulator(connection)
        historical_rows = import_netcdf(
            connection,
            args.historical_netcdf.resolve(),
            target_chunk_rows=args.netcdf_chunk_rows,
        )
        year_2022_rows = import_netcdf(
            connection,
            args.year_2022_netcdf.resolve(),
            target_chunk_rows=args.netcdf_chunk_rows,
        )
        recent_parts = import_recent_csv(
            connection, args.years_2023_2024_csv.resolve()
        )
        logging.info("Historical expanded rows: %s", f"{historical_rows:,}")
        logging.info("2022 expanded rows: %s", f"{year_2022_rows:,}")
        logging.info("2023-2024 monthly coordinate parts: %s", f"{recent_parts:,}")

        monthly_rows, wind_cells = build_monthly_wind(connection)
        logging.info("Monthly wind-coordinate rows: %s", f"{monthly_rows:,}")
        logging.info("Distinct wind coordinates: %s", f"{wind_cells:,}")
        logging.info(
            "Direction convention: atan2(northward, eastward), "
            "counterclockwise from East"
        )
        grid_attributes = build_grid_crosswalk(
            connection, args.grid_shapefile.resolve()
        )
        output_rows = build_output_table(connection, grid_attributes)

        output_columns = [
            "cellid_wind",
            *grid_attributes,
            "unique_small_grid_id",
            "longitude",
            "latitude",
            "year",
            "month",
            "wind_speed_av_cellid_month",
            "wind_direction_av_cellid_month",
            "rollav_wind_speed_cellid_month",
            "rollav_wind_direction_cellid_month",
        ]
        select_sql = ", ".join(qid(column) for column in output_columns)
        connection.execute(
            f"""
            COPY (
                SELECT {select_sql}
                FROM wind_grid
                ORDER BY unique_small_grid_id, year, month
            ) TO {sql_string(output_temp)}
            (FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 262144)
            """
        )
        os.replace(output_temp, output)
        connection.execute("CHECKPOINT")
        logging.info("Completed grid wind panel: %s", output)
        logging.info("Retained DuckDB database: %s", database)
        logging.info("Output grid-month rows: %s", f"{output_rows:,}")
    finally:
        connection.close()
        if output_temp.exists():
            output_temp.unlink()
        for path in (Path(str(database) + ".wal"), temp_directory):
            if path.exists():
                remove_exact_path(path, output.parent)
    return 0


if __name__ == "__main__":
    sys.exit(main())

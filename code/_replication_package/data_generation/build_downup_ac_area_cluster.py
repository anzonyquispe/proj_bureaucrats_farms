#!/usr/bin/env python3
"""Generate exact downwind/upwind AC areas in parallel.

Input is the population-stage Parquet produced by
``build_downup_ac_pop_cluster.py``. Every grid-year-month observation with a
nonmissing rolling wind direction is calculated separately; wind-direction
floats are never rounded, grouped, cached, or deduplicated. Each worker
constructs the downwind half-plane through the focal-grid centroid and
intersects it with the assigned AC polygon using vectorized Shapely 2
operations.

This is geometrically equivalent to splitting the AC with a line perpendicular
to the wind direction, but avoids Python-level ``split`` calls for every row.
The final Parquet contains exactly the requested 16 analysis columns.
"""

from __future__ import annotations

import argparse
import logging
import multiprocessing as mp
import os
import shutil
import sys
from concurrent.futures import (
    ALL_COMPLETED,
    FIRST_COMPLETED,
    ProcessPoolExecutor,
    wait,
)
from pathlib import Path
from typing import Any


def configure_geospatial_data_paths() -> None:
    """Override stale inherited PROJ/GDAL paths with this Python environment."""
    prefix = Path(sys.prefix)
    proj_candidates = [
        prefix / "share" / "proj",
        *prefix.glob(
            "lib/python*/site-packages/pyproj/proj_dir/share/proj"
        ),
    ]
    for candidate in proj_candidates:
        if (candidate / "proj.db").is_file():
            os.environ["PROJ_DATA"] = str(candidate)
            # PROJ_LIB supports older PROJ releases used on some cluster nodes.
            os.environ["PROJ_LIB"] = str(candidate)
            break
    else:
        raise RuntimeError(
            f"Cannot find proj.db inside Python environment {prefix}."
        )

    gdal_candidate = prefix / "share" / "gdal"
    if gdal_candidate.is_dir():
        os.environ["GDAL_DATA"] = str(gdal_candidate)


configure_geospatial_data_paths()

try:
    import duckdb
    import geopandas as gpd
    import numpy as np
    import pandas as pd
    import pyarrow as pa
    import pyarrow.parquet as pq
    import shapely
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "The area stage requires duckdb, geopandas, numpy, pandas, pyarrow, "
        "and shapely>=2."
    ) from exc


ROOT = Path("/groups/sgulzar/sa_fires/proj_bureaucrats_farms")
INTERMEDIATE = ROOT / "data_output" / "intermediate"
DEFAULT_POP_INPUT = (
    INTERMEDIATE / "data_2012_2024_grid_ac_downup_pop.parquet"
)
DEFAULT_GRID_POPULATION = INTERMEDIATE / "small_grid_population_2010.parquet"
DEFAULT_AC_SHAPEFILE = INTERMEDIATE / "_0_2_3_ACs_right_shapefile.shp"
DEFAULT_OUTPUT = INTERMEDIATE / "data_2012_2024_grid_ac_downup.parquet"

_WORKER_AC_GEOMETRIES: dict[int, Any] = {}
_WORKER_AC_BOUNDS: dict[int, tuple[float, float, float, float]] = {}
_WORKER_AC_AREAS: dict[int, float] = {}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--population-input", type=Path, default=DEFAULT_POP_INPUT)
    parser.add_argument(
        "--grid-population", type=Path, default=DEFAULT_GRID_POPULATION
    )
    parser.add_argument("--ac-shapefile", type=Path, default=DEFAULT_AC_SHAPEFILE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--database", type=Path, default=None)
    parser.add_argument("--area-keys", type=Path, default=None)
    parser.add_argument("--area-results", type=Path, default=None)
    parser.add_argument("--temp-directory", type=Path, default=None)
    parser.add_argument("--metric-crs", default="EPSG:7755")
    parser.add_argument(
        "--workers",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
        help="DuckDB threads used before and after the parallel geometry phase.",
    )
    parser.add_argument("--memory-limit", default="90GB")
    parser.add_argument(
        "--area-chunk-rows",
        type=int,
        default=5_000,
        help="Grid-year-month observations per worker task.",
    )
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--keep-work-files", action="store_true")
    return parser.parse_args()


def sql_string(value: str | Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def derive_paths(
    args: argparse.Namespace,
) -> tuple[Path, Path, Path, Path, Path]:
    output = args.output.resolve()
    database = (
        args.database.resolve()
        if args.database
        else output.with_suffix(".duckdb")
    )
    area_keys = (
        args.area_keys.resolve()
        if args.area_keys
        else output.with_name(output.stem + "_area_keys.parquet")
    )
    area_results = (
        args.area_results.resolve()
        if args.area_results
        else output.with_name(output.stem + "_area_results.parquet")
    )
    temp_directory = (
        args.temp_directory.resolve()
        if args.temp_directory
        else output.with_name(output.stem + "_duckdb_tmp")
    )
    return output, database, area_keys, area_results, temp_directory


def remove_exact_path(path: Path, allowed_parent: Path) -> None:
    resolved = path.resolve()
    parent = allowed_parent.resolve()
    if resolved == parent or parent not in resolved.parents:
        raise ValueError(f"Refusing to remove unsafe path: {resolved}")
    if resolved.is_dir():
        shutil.rmtree(resolved)
    elif resolved.exists():
        resolved.unlink()


def validate_paths(
    args: argparse.Namespace,
    output: Path,
    database: Path,
    area_keys: Path,
    area_results: Path,
    temp_directory: Path,
) -> None:
    for source in (
        args.population_input,
        args.grid_population,
        args.ac_shapefile,
    ):
        if not source.is_file():
            raise FileNotFoundError(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    targets = [
        output,
        database,
        Path(str(database) + ".wal"),
        area_keys,
        area_results,
        temp_directory,
    ]
    existing = [path for path in targets if path.exists()]
    if existing and not args.overwrite:
        raise FileExistsError(
            "Output/work paths exist; use --overwrite:\n"
            + "\n".join(f"  {path}" for path in existing)
        )
    if args.overwrite:
        for path in existing:
            remove_exact_path(path, output.parent)
    temp_directory.mkdir(parents=True, exist_ok=True)


def configure(
    connection: duckdb.DuckDBPyConnection,
    args: argparse.Namespace,
    temp_directory: Path,
) -> None:
    connection.execute(f"SET threads = {int(args.threads)}")
    connection.execute(f"SET memory_limit = {sql_string(args.memory_limit)}")
    connection.execute(
        f"SET temp_directory = {sql_string(temp_directory.resolve())}"
    )
    connection.execute("SET preserve_insertion_order = false")


def relation_columns(
    connection: duckdb.DuckDBPyConnection, relation: str
) -> set[str]:
    return {
        str(row[0])
        for row in connection.execute(
            f"DESCRIBE SELECT * FROM {relation}"
        ).fetchall()
    }


def prepare_area_keys(
    args: argparse.Namespace,
    database: Path,
    area_keys: Path,
    temp_directory: Path,
) -> tuple[int, int]:
    connection = duckdb.connect(str(database))
    try:
        configure(connection, args, temp_directory)
        pop_relation = (
            f"read_parquet({sql_string(args.population_input.resolve())})"
        )
        grid_relation = (
            f"read_parquet({sql_string(args.grid_population.resolve())})"
        )
        required_pop = {
            "unique_small_grid_id",
            "ac_uq_id",
            "calculation_wind_direction",
            "province",
            "district",
            "month",
            "year",
            "wind_speed_av_cellid_month",
            "wind_direction_av_cellid_month",
            "rollav_wind_speed_cellid_month",
            "rollav_wind_direction_cellid_month",
            "downup_dummy",
            "downup_ac_pop",
            "downwind_pop",
            "upwind_pop",
        }
        missing = sorted(required_pop - relation_columns(connection, pop_relation))
        if missing:
            raise KeyError(
                "Population-stage Parquet is missing: " + ", ".join(missing)
            )
        missing_grid = sorted(
            {"unique_small_grid_id", "centroid_x", "centroid_y"}
            - relation_columns(connection, grid_relation)
        )
        if missing_grid:
            raise KeyError(
                "Grid-population Parquet is missing: "
                + ", ".join(missing_grid)
            )

        population_rows = int(
            connection.execute(
                f"SELECT count(*) FROM {pop_relation}"
            ).fetchone()[0]
        )
        duplicate_keys = int(
            connection.execute(
                f"""
                SELECT count(*)
                FROM (
                    SELECT unique_small_grid_id, year, month
                    FROM {pop_relation}
                    GROUP BY ALL
                    HAVING count(*) <> 1
                )
                """
            ).fetchone()[0]
        )
        if duplicate_keys:
            raise ValueError(
                f"Population input has {duplicate_keys:,} duplicate panel keys."
            )

        logging.info("Writing one geometry task per nonmissing-wind panel row")
        connection.execute(
            f"""
            COPY (
                SELECT
                    CAST(pop.unique_small_grid_id AS BIGINT)
                        AS unique_small_grid_id,
                    CAST(pop.ac_uq_id AS BIGINT) AS ac_uq_id,
                    CAST(pop.year AS SMALLINT) AS year,
                    CAST(pop.month AS TINYINT) AS month,
                    CAST(pop.calculation_wind_direction AS DOUBLE)
                        AS calculation_wind_direction,
                    CAST(grid.centroid_x AS DOUBLE) AS centroid_x,
                    CAST(grid.centroid_y AS DOUBLE) AS centroid_y
                FROM {pop_relation} AS pop
                INNER JOIN {grid_relation} AS grid
                    ON CAST(pop.unique_small_grid_id AS BIGINT)
                       = CAST(grid.unique_small_grid_id AS BIGINT)
                WHERE pop.calculation_wind_direction IS NOT NULL
            )
            TO {sql_string(area_keys)}
            (FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 250000)
            """
        )
        area_key_rows = int(
            connection.execute(
                f"SELECT count(*) FROM read_parquet({sql_string(area_keys)})"
            ).fetchone()[0]
        )
        expected_area_rows = int(
            connection.execute(
                f"""
                SELECT count(*)
                FROM {pop_relation}
                WHERE calculation_wind_direction IS NOT NULL
                """
            ).fetchone()[0]
        )
        if area_key_rows != expected_area_rows:
            raise ValueError(
                f"Area task file has {area_key_rows:,} rows; expected "
                f"{expected_area_rows:,} nonmissing-wind panel rows."
            )
    finally:
        connection.close()

    logging.info("Population rows: %s", f"{population_rows:,}")
    logging.info(
        "Nonmissing-wind panel rows sent to geometry workers: %s",
        f"{area_key_rows:,}",
    )
    return population_rows, area_key_rows


def largest_polygon(geometry: Any) -> Any:
    geometry = shapely.make_valid(geometry)
    pending = [geometry]
    polygons: list[Any] = []
    while pending:
        part = pending.pop()
        type_id = shapely.get_type_id(part)
        if type_id == 3:
            polygons.append(part)
        elif type_id in (6, 7):
            pending.extend(shapely.get_parts(part))
    if not polygons:
        raise ValueError("AC geometry has no polygon component.")
    return max(polygons, key=lambda polygon: float(polygon.area))


def load_ac_wkb(ac_path: Path, metric_crs: str) -> dict[int, bytes]:
    acs = gpd.read_file(ac_path)
    if acs.crs is None:
        raise ValueError("AC shapefile has no CRS.")
    if "ac_uq_id" not in acs.columns:
        raise KeyError("AC shapefile does not contain ac_uq_id.")
    if acs["ac_uq_id"].isna().any() or acs["ac_uq_id"].duplicated().any():
        raise ValueError("AC ac_uq_id must be nonmissing and unique.")
    acs = acs.to_crs(metric_crs)
    return {
        int(row.ac_uq_id): shapely.to_wkb(largest_polygon(row.geometry))
        for row in acs[["ac_uq_id", "geometry"]].itertuples(index=False)
    }


def initialize_worker(ac_wkb: dict[int, bytes]) -> None:
    global _WORKER_AC_GEOMETRIES, _WORKER_AC_BOUNDS, _WORKER_AC_AREAS
    _WORKER_AC_GEOMETRIES = {
        ac_id: shapely.from_wkb(value) for ac_id, value in ac_wkb.items()
    }
    _WORKER_AC_BOUNDS = {
        ac_id: tuple(map(float, geometry.bounds))
        for ac_id, geometry in _WORKER_AC_GEOMETRIES.items()
    }
    _WORKER_AC_AREAS = {
        ac_id: float(geometry.area)
        for ac_id, geometry in _WORKER_AC_GEOMETRIES.items()
    }


def scalar_halfplane_area(
    polygon: Any,
    bounds: tuple[float, float, float, float],
    total_area: float,
    focal_x: float,
    focal_y: float,
    wind_degrees: float,
) -> tuple[float, float]:
    """Robust scalar fallback for a failed vectorized GEOS batch."""
    theta = np.radians(wind_degrees)
    vx, vy = float(np.sin(theta)), float(np.cos(theta))
    tx, ty = float(np.cos(theta)), float(-np.sin(theta))
    minx, miny, maxx, maxy = bounds
    radius = (
        np.hypot(
            max(abs(focal_x - minx), abs(focal_x - maxx)),
            max(abs(focal_y - miny), abs(focal_y - maxy)),
        )
        + 10.0
    )
    coordinates = np.array(
        [
            [focal_x - tx * radius, focal_y - ty * radius],
            [focal_x + tx * radius, focal_y + ty * radius],
            [
                focal_x + tx * radius + vx * 2.0 * radius,
                focal_y + ty * radius + vy * 2.0 * radius,
            ],
            [
                focal_x - tx * radius + vx * 2.0 * radius,
                focal_y - ty * radius + vy * 2.0 * radius,
            ],
            [focal_x - tx * radius, focal_y - ty * radius],
        ]
    )
    halfplane = shapely.polygons(coordinates)
    down = float(shapely.area(shapely.intersection(polygon, halfplane)))
    down = min(max(down, 0.0), total_area)
    return down / 1_000_000.0, (total_area - down) / 1_000_000.0


def calculate_area_chunk(frame: pd.DataFrame) -> pd.DataFrame:
    """Vectorized exact half-plane intersections for one worker batch."""
    ac_ids = frame["ac_uq_id"].to_numpy(dtype=np.int64)
    x = frame["centroid_x"].to_numpy(dtype=np.float64)
    y = frame["centroid_y"].to_numpy(dtype=np.float64)
    wind = frame["calculation_wind_direction"].to_numpy(dtype=np.float64)
    count = len(frame)

    polygons = np.empty(count, dtype=object)
    minx = np.empty(count, dtype=np.float64)
    miny = np.empty(count, dtype=np.float64)
    maxx = np.empty(count, dtype=np.float64)
    maxy = np.empty(count, dtype=np.float64)
    total = np.empty(count, dtype=np.float64)
    for ac_id in np.unique(ac_ids):
        if int(ac_id) not in _WORKER_AC_GEOMETRIES:
            raise KeyError(f"AC {int(ac_id)} is absent from the shapefile.")
        mask = ac_ids == ac_id
        indices = np.flatnonzero(mask)
        polygon = _WORKER_AC_GEOMETRIES[int(ac_id)]
        for index in indices:
            polygons[index] = polygon
        bounds = _WORKER_AC_BOUNDS[int(ac_id)]
        minx[mask], miny[mask], maxx[mask], maxy[mask] = bounds
        total[mask] = _WORKER_AC_AREAS[int(ac_id)]

    theta = np.radians(wind)
    vx, vy = np.sin(theta), np.cos(theta)
    tx, ty = np.cos(theta), -np.sin(theta)
    radius = (
        np.hypot(
            np.maximum(np.abs(x - minx), np.abs(x - maxx)),
            np.maximum(np.abs(y - miny), np.abs(y - maxy)),
        )
        + 10.0
    )

    point_a = np.column_stack((x - tx * radius, y - ty * radius))
    point_b = np.column_stack((x + tx * radius, y + ty * radius))
    point_c = np.column_stack(
        (
            x + tx * radius + vx * 2.0 * radius,
            y + ty * radius + vy * 2.0 * radius,
        )
    )
    point_d = np.column_stack(
        (
            x - tx * radius + vx * 2.0 * radius,
            y - ty * radius + vy * 2.0 * radius,
        )
    )
    coordinates = np.stack(
        (point_a, point_b, point_c, point_d, point_a), axis=1
    )
    halfplanes = shapely.polygons(coordinates)

    try:
        intersections = shapely.intersection(polygons, halfplanes)
        down_square_metres = np.asarray(
            shapely.area(intersections), dtype=np.float64
        )
        down_square_metres = np.clip(down_square_metres, 0.0, total)
        up_square_metres = np.maximum(total - down_square_metres, 0.0)
    except Exception:
        down_square_metres = np.empty(count, dtype=np.float64)
        up_square_metres = np.empty(count, dtype=np.float64)
        for index in range(count):
            down_km2, up_km2 = scalar_halfplane_area(
                polygons[index],
                (minx[index], miny[index], maxx[index], maxy[index]),
                total[index],
                x[index],
                y[index],
                wind[index],
            )
            down_square_metres[index] = down_km2 * 1_000_000.0
            up_square_metres[index] = up_km2 * 1_000_000.0

    result = frame[
        [
            "unique_small_grid_id",
            "year",
            "month",
        ]
    ].copy()
    result["downwind_area"] = down_square_metres / 1_000_000.0
    result["upwind_area"] = up_square_metres / 1_000_000.0
    result["downup_ac_area"] = (
        result["downwind_area"] > result["upwind_area"]
    ).astype("int8")
    return result


def write_result(
    result: pd.DataFrame,
    writer: pq.ParquetWriter | None,
    output: Path,
) -> tuple[pq.ParquetWriter, int]:
    table = pa.Table.from_pandas(result, preserve_index=False)
    if writer is None:
        writer = pq.ParquetWriter(str(output), table.schema, compression="zstd")
    writer.write_table(table)
    return writer, len(result)


def calculate_areas_parallel(
    area_keys: Path,
    area_results: Path,
    ac_wkb: dict[int, bytes],
    args: argparse.Namespace,
) -> int:
    parquet = pq.ParquetFile(area_keys)
    batches = parquet.iter_batches(batch_size=args.area_chunk_rows)
    writer: pq.ParquetWriter | None = None
    completed_rows = 0

    try:
        if args.workers == 1:
            initialize_worker(ac_wkb)
            for batch in batches:
                result = calculate_area_chunk(batch.to_pandas())
                writer, added = write_result(result, writer, area_results)
                completed_rows += added
        else:
            context = mp.get_context("spawn")
            pending: set[Any] = set()
            with ProcessPoolExecutor(
                max_workers=args.workers,
                mp_context=context,
                initializer=initialize_worker,
                initargs=(ac_wkb,),
            ) as executor:
                for batch in batches:
                    pending.add(
                        executor.submit(calculate_area_chunk, batch.to_pandas())
                    )
                    if len(pending) >= max(2, args.workers * 2):
                        done, pending = wait(
                            pending, return_when=FIRST_COMPLETED
                        )
                        pending = set(pending)
                        for future in done:
                            writer, added = write_result(
                                future.result(), writer, area_results
                            )
                            completed_rows += added
                if pending:
                    done, _ = wait(pending, return_when=ALL_COMPLETED)
                    for future in done:
                        writer, added = write_result(
                            future.result(), writer, area_results
                        )
                        completed_rows += added
    finally:
        if writer is not None:
            writer.close()

    if writer is None:
        empty_schema = pa.schema(
            [
                ("unique_small_grid_id", pa.int64()),
                ("year", pa.int16()),
                ("month", pa.int8()),
                ("downwind_area", pa.float64()),
                ("upwind_area", pa.float64()),
                ("downup_ac_area", pa.int8()),
            ]
        )
        pq.write_table(
            pa.Table.from_batches([], schema=empty_schema),
            area_results,
            compression="zstd",
        )
    logging.info("Area panel rows completed: %s", f"{completed_rows:,}")
    return completed_rows


def merge_final_output(
    args: argparse.Namespace,
    database: Path,
    area_results: Path,
    output: Path,
    temp_directory: Path,
    expected_rows: int,
) -> dict[str, int]:
    connection = duckdb.connect(str(database))
    try:
        configure(connection, args, temp_directory)
        pop_relation = (
            f"read_parquet({sql_string(args.population_input.resolve())})"
        )
        area_relation = f"read_parquet({sql_string(area_results)})"
        final_query = f"""
            SELECT
                pop.unique_small_grid_id,
                pop.province,
                pop.district,
                pop.month,
                pop.year,
                pop.wind_speed_av_cellid_month,
                pop.wind_direction_av_cellid_month,
                pop.rollav_wind_speed_cellid_month,
                pop.rollav_wind_direction_cellid_month,
                pop.downup_dummy,
                pop.downup_ac_pop,
                area.downup_ac_area,
                pop.downwind_pop,
                pop.upwind_pop,
                area.downwind_area,
                area.upwind_area
            FROM {pop_relation} AS pop
            LEFT JOIN {area_relation} AS area
                ON pop.unique_small_grid_id = area.unique_small_grid_id
               AND pop.year = area.year
               AND pop.month = area.month
        """
        connection.execute(
            f"""
            COPY ({final_query})
            TO {sql_string(output)}
            (FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 250000)
            """
        )
        summary = connection.execute(
            f"""
            SELECT
                count(*) AS row_count,
                count(DISTINCT unique_small_grid_id) AS grids,
                count(DISTINCT (year, month)) AS months,
                count(*) FILTER (
                    WHERE rollav_wind_direction_cellid_month IS NULL
                ) AS missing_wind,
                count(*) FILTER (
                    WHERE rollav_wind_direction_cellid_month IS NOT NULL
                      AND downwind_area IS NULL
                ) AS missing_area_with_wind
            FROM ({final_query})
            """
        ).fetchone()
        duplicate_keys = int(
            connection.execute(
                f"""
                SELECT count(*)
                FROM (
                    SELECT unique_small_grid_id, year, month
                    FROM ({final_query})
                    GROUP BY ALL
                    HAVING count(*) <> 1
                )
                """
            ).fetchone()[0]
        )
        if int(summary[0]) != expected_rows or duplicate_keys:
            raise ValueError(
                f"Final output has {summary[0]:,} rows and "
                f"{duplicate_keys:,} duplicate keys; expected "
                f"{expected_rows:,} rows."
            )
        if int(summary[4]):
            raise ValueError(
                f"{summary[4]:,} rows have wind direction but no area result."
            )
    finally:
        connection.close()
    return {
        "rows": int(summary[0]),
        "grids": int(summary[1]),
        "months": int(summary[2]),
        "missing_wind": int(summary[3]),
        "missing_area_with_wind": int(summary[4]),
    }


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    output, database, area_keys, area_results, temp_directory = derive_paths(args)
    validate_paths(
        args,
        output,
        database,
        area_keys,
        area_results,
        temp_directory,
    )

    expected_rows, expected_area_rows = prepare_area_keys(
        args, database, area_keys, temp_directory
    )
    ac_wkb = load_ac_wkb(args.ac_shapefile.resolve(), args.metric_crs)
    logging.info(
        "Computing exact half-plane intersections with %d workers",
        args.workers,
    )
    completed_area_rows = calculate_areas_parallel(
        area_keys, area_results, ac_wkb, args
    )
    if completed_area_rows != expected_area_rows:
        raise ValueError(
            f"Completed {completed_area_rows:,} area rows; expected "
            f"{expected_area_rows:,}."
        )
    summary = merge_final_output(
        args,
        database,
        area_results,
        output,
        temp_directory,
        expected_rows,
    )

    if not args.keep_work_files:
        for path in (
            database,
            Path(str(database) + ".wal"),
            area_keys,
            area_results,
            temp_directory,
        ):
            if path.exists():
                remove_exact_path(path, output.parent)

    logging.info("Completed area stage: %s", output)
    for key, value in summary.items():
        logging.info("%s: %s", key, f"{value:,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

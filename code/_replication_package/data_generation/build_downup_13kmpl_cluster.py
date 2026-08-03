#!/usr/bin/env python3
"""Generate 13 km placebo downwind/upwind area and population measures.

The focal grid and AC assignment come from the existing population-stage
panel. For every focal grid, all other small-grid centroids within 13,000
metres are found in EPSG:7755 coordinates. Their 2010 populations are then
classified by the half-plane pointing in the rolling wind direction, exactly
as in the AC population stage. Wind-direction floats are never rounded,
grouped, or deduplicated.

The 13 km geometry is a circle centred on the focal grid. A perpendicular
line through its centre is a diameter, so its exact downwind and upwind areas
are both pi * radius^2 / 2. Missing wind directions produce missing measures.
"""

from __future__ import annotations

import argparse
import logging
import math
import os
import shutil
import sys
from pathlib import Path

try:
    import duckdb
except ImportError as exc:  # pragma: no cover
    raise SystemExit("DuckDB is required in the cluster environment.") from exc


ROOT = Path("/groups/sgulzar/sa_fires/proj_bureaucrats_farms")
INTERMEDIATE = ROOT / "data_output" / "intermediate"
DEFAULT_PANEL = INTERMEDIATE / "data_2012_2024_grid_ac_downup_pop.parquet"
DEFAULT_POPULATION = INTERMEDIATE / "small_grid_population_2010.parquet"
DEFAULT_OUTPUT = INTERMEDIATE / "data_2012_2024_grid_ac_13kmpl.parquet"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--panel", type=Path, default=DEFAULT_PANEL)
    parser.add_argument(
        "--grid-population",
        type=Path,
        default=DEFAULT_POPULATION,
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--database", type=Path, default=None)
    parser.add_argument("--temp-directory", type=Path, default=None)
    parser.add_argument("--radius-metres", type=float, default=13_000.0)
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument("--memory-limit", default="90GB")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--keep-work-files", action="store_true")
    return parser.parse_args()


def sql_string(value: str | Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def derive_paths(args: argparse.Namespace) -> tuple[Path, Path, Path]:
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
    temp_directory: Path,
) -> None:
    if args.radius_metres <= 0:
        raise ValueError("--radius-metres must be positive.")
    for source in (args.panel, args.grid_population):
        if not source.is_file():
            raise FileNotFoundError(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    targets = [
        output,
        output.with_name(output.name + ".tmp"),
        database,
        Path(str(database) + ".wal"),
        temp_directory,
    ]
    existing = [path for path in targets if path.exists()]
    if existing and not args.overwrite:
        raise FileExistsError(
            "Output/work paths exist; pass --overwrite:\n"
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
    connection.execute(f"SET threads = {max(1, int(args.threads))}")
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


def require_columns(actual: set[str], required: set[str], label: str) -> None:
    missing = sorted(required - actual)
    if missing:
        raise KeyError(f"{label} is missing: {', '.join(missing)}")


def import_inputs(
    connection: duckdb.DuckDBPyConnection,
    args: argparse.Namespace,
) -> tuple[int, int]:
    panel_relation = f"read_parquet({sql_string(args.panel.resolve())})"
    population_relation = (
        f"read_parquet({sql_string(args.grid_population.resolve())})"
    )
    require_columns(
        relation_columns(connection, panel_relation),
        {
            "unique_small_grid_id",
            "ac_uq_id",
            "year",
            "month",
            "calculation_wind_direction",
        },
        "panel",
    )
    require_columns(
        relation_columns(connection, population_relation),
        {
            "unique_small_grid_id",
            "population_2010",
            "centroid_x",
            "centroid_y",
        },
        "grid-population Parquet",
    )

    logging.info("Importing panel keys and grid population centroids")
    connection.execute(
        f"""
        CREATE TABLE panel AS
        SELECT
            unique_small_grid_id::BIGINT AS unique_small_grid_id,
            ac_uq_id::BIGINT AS ac_uq_id,
            year::SMALLINT AS year,
            month::TINYINT AS month,
            CASE
                WHEN calculation_wind_direction IS NULL THEN NULL
                ELSE fmod(
                    fmod(calculation_wind_direction, 360.0) + 360.0,
                    360.0
                )
            END::DOUBLE AS calculation_wind_direction
        FROM {panel_relation}
        """
    )
    connection.execute(
        f"""
        CREATE TABLE grid_population AS
        SELECT
            unique_small_grid_id::BIGINT AS unique_small_grid_id,
            coalesce(population_2010::DOUBLE, 0.0) AS population_2010,
            centroid_x::DOUBLE AS centroid_x,
            centroid_y::DOUBLE AS centroid_y
        FROM {population_relation}
        """
    )
    for table, key_sql in (
        ("panel", "unique_small_grid_id, year, month"),
        ("grid_population", "unique_small_grid_id"),
    ):
        duplicates = int(
            connection.execute(
                f"""
                SELECT count(*)
                FROM (
                    SELECT {key_sql}
                    FROM {table}
                    GROUP BY ALL
                    HAVING count(*) <> 1
                )
                """
            ).fetchone()[0]
        )
        if duplicates:
            raise ValueError(f"{table} has {duplicates:,} duplicate keys.")

    panel_rows, panel_grids, missing_wind = connection.execute(
        """
        SELECT
            count(*),
            count(DISTINCT unique_small_grid_id),
            count_if(calculation_wind_direction IS NULL)
        FROM panel
        """
    ).fetchone()
    connection.execute(
        """
        CREATE TABLE focal_grids AS
        WITH membership AS (
            SELECT
                unique_small_grid_id,
                min(ac_uq_id) AS ac_uq_id,
                count(DISTINCT ac_uq_id) AS ac_count
            FROM panel
            GROUP BY unique_small_grid_id
        )
        SELECT
            membership.unique_small_grid_id,
            membership.ac_uq_id,
            population.centroid_x,
            population.centroid_y
        FROM membership
        INNER JOIN grid_population AS population
            USING (unique_small_grid_id)
        WHERE membership.ac_count = 1
        """
    )
    focal_count = int(
        connection.execute("SELECT count(*) FROM focal_grids").fetchone()[0]
    )
    if focal_count != int(panel_grids):
        raise ValueError(
            f"Only {focal_count:,} of {panel_grids:,} panel grids have one "
            "AC and a population-centroid record."
        )
    logging.info("Panel rows: %s", f"{panel_rows:,}")
    logging.info("Focal grids: %s", f"{panel_grids:,}")
    logging.info("Rows missing rolling direction: %s", f"{missing_wind:,}")
    connection.execute("ANALYZE panel")
    connection.execute("ANALYZE focal_grids")
    connection.execute("ANALYZE grid_population")
    return int(panel_rows), int(missing_wind)


def build_radius_lookup(
    connection: duckdb.DuckDBPyConnection,
    radius_metres: float,
) -> tuple[int, int]:
    radius = repr(float(radius_metres))
    radius_squared = repr(float(radius_metres * radius_metres))
    logging.info("Building exact centroid neighbors within %.3f metres", radius_metres)
    connection.execute(
        f"""
        CREATE TABLE population_bins AS
        SELECT
            *,
            floor(centroid_x / {radius})::BIGINT AS bin_x,
            floor(centroid_y / {radius})::BIGINT AS bin_y
        FROM grid_population
        """
    )
    connection.execute(
        f"""
        CREATE TABLE focal_bins AS
        SELECT
            *,
            floor(centroid_x / {radius})::BIGINT AS bin_x,
            floor(centroid_y / {radius})::BIGINT AS bin_y
        FROM focal_grids
        """
    )
    connection.execute("ANALYZE population_bins")
    connection.execute("ANALYZE focal_bins")
    connection.execute(
        f"""
        CREATE TABLE radius_intervals AS
        WITH candidates AS (
            SELECT
                focal.unique_small_grid_id AS focal_grid_id,
                comparison.unique_small_grid_id AS comparison_grid_id,
                comparison.population_2010 AS comparison_population,
                comparison.centroid_x - focal.centroid_x AS dx,
                comparison.centroid_y - focal.centroid_y AS dy
            FROM focal_bins AS focal
            CROSS JOIN range(-1, 2) AS x_offset(offset_x)
            CROSS JOIN range(-1, 2) AS y_offset(offset_y)
            INNER JOIN population_bins AS comparison
                ON comparison.bin_x = focal.bin_x + x_offset.offset_x
               AND comparison.bin_y = focal.bin_y + y_offset.offset_y
            WHERE comparison.unique_small_grid_id
                      <> focal.unique_small_grid_id
              AND power(comparison.centroid_x - focal.centroid_x, 2)
                  + power(comparison.centroid_y - focal.centroid_y, 2)
                  <= {radius_squared}
        ),
        bearings AS (
            SELECT
                focal_grid_id,
                comparison_grid_id,
                comparison_population,
                fmod(degrees(atan2(dx, dy)) + 360.0, 360.0) AS bearing
            FROM candidates
        )
        SELECT
            focal_grid_id,
            comparison_grid_id,
            comparison_population,
            fmod(bearing + 270.0, 360.0) AS start_angle,
            fmod(bearing + 90.0, 360.0) AS end_angle
        FROM bearings
        """
    )
    neighbor_pairs = int(
        connection.execute("SELECT count(*) FROM radius_intervals").fetchone()[0]
    )
    covered_grids = int(
        connection.execute(
            "SELECT count(DISTINCT focal_grid_id) FROM radius_intervals"
        ).fetchone()[0]
    )
    focal_grids = int(
        connection.execute("SELECT count(*) FROM focal_grids").fetchone()[0]
    )
    if covered_grids != focal_grids:
        raise ValueError(
            f"Only {covered_grids:,} of {focal_grids:,} focal grids have a "
            "non-focal centroid within the radius."
        )
    logging.info("Ordered focal-neighbor pairs: %s", f"{neighbor_pairs:,}")

    connection.execute(
        """
        CREATE TABLE radius_totals AS
        SELECT
            focal_grid_id,
            sum(comparison_population) AS total_population_13kmpl,
            count(*) AS neighbor_grids_13kmpl
        FROM radius_intervals
        GROUP BY focal_grid_id
        """
    )
    connection.execute(
        """
        CREATE TABLE angle_events AS
        WITH raw_events AS (
            SELECT
                unique_small_grid_id AS focal_grid_id,
                0.0::DOUBLE AS event_angle,
                0.0::DOUBLE AS delta_population
            FROM focal_grids

            UNION ALL
            SELECT focal_grid_id, start_angle + 1e-10,
                   comparison_population
            FROM radius_intervals WHERE start_angle < end_angle

            UNION ALL
            SELECT focal_grid_id, end_angle, -comparison_population
            FROM radius_intervals WHERE start_angle < end_angle

            UNION ALL
            SELECT focal_grid_id, 0.0, comparison_population
            FROM radius_intervals WHERE start_angle > end_angle

            UNION ALL
            SELECT focal_grid_id, end_angle, -comparison_population
            FROM radius_intervals WHERE start_angle > end_angle

            UNION ALL
            SELECT focal_grid_id, start_angle + 1e-10,
                   comparison_population
            FROM radius_intervals WHERE start_angle > end_angle
        ),
        collapsed AS (
            SELECT
                focal_grid_id,
                event_angle,
                sum(delta_population) AS delta_population
            FROM raw_events
            GROUP BY ALL
        )
        SELECT
            focal_grid_id,
            event_angle,
            sum(delta_population) OVER (
                PARTITION BY focal_grid_id
                ORDER BY event_angle
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS downwind_pop
        FROM collapsed
        """
    )
    connection.execute("ANALYZE angle_events")
    connection.execute("ANALYZE radius_totals")
    connection.execute("DROP TABLE radius_intervals")
    connection.execute("DROP TABLE population_bins")
    connection.execute("DROP TABLE focal_bins")
    connection.execute("CHECKPOINT")
    return neighbor_pairs, covered_grids


def calculate_and_export(
    connection: duckdb.DuckDBPyConnection,
    output: Path,
    radius_metres: float,
    expected_rows: int,
    expected_missing_wind: int,
) -> dict[str, int]:
    half_circle_km2 = math.pi * radius_metres * radius_metres / 2.0 / 1_000_000.0
    half_area = repr(float(half_circle_km2))
    final_query = f"""
        WITH directional AS (
            SELECT
                panel.unique_small_grid_id,
                panel.year,
                panel.month,
                event.downwind_pop
            FROM panel
            ASOF LEFT JOIN angle_events AS event
                ON panel.unique_small_grid_id = event.focal_grid_id
               AND panel.calculation_wind_direction >= event.event_angle
        ),
        measures AS (
            SELECT
                panel.*,
                CASE
                    WHEN panel.calculation_wind_direction IS NULL THEN NULL
                    ELSE {half_area}
                END::DOUBLE AS downwind_area_13kmpl,
                CASE
                    WHEN panel.calculation_wind_direction IS NULL THEN NULL
                    ELSE {half_area}
                END::DOUBLE AS upwind_area_13kmpl,
                CASE
                    WHEN panel.calculation_wind_direction IS NULL THEN NULL
                    ELSE greatest(0.0, directional.downwind_pop)
                END::DOUBLE AS downwind_pop_13kmpl,
                CASE
                    WHEN panel.calculation_wind_direction IS NULL THEN NULL
                    ELSE greatest(
                        0.0,
                        totals.total_population_13kmpl
                            - directional.downwind_pop
                    )
                END::DOUBLE AS upwind_pop_13kmpl
            FROM panel
            INNER JOIN directional
                USING (unique_small_grid_id, year, month)
            INNER JOIN radius_totals AS totals
                ON panel.unique_small_grid_id = totals.focal_grid_id
        )
        SELECT
            unique_small_grid_id,
            ac_uq_id,
            year,
            month,
            calculation_wind_direction,
            downwind_area_13kmpl,
            upwind_area_13kmpl,
            downwind_pop_13kmpl,
            upwind_pop_13kmpl,
            CASE
                WHEN downwind_pop_13kmpl IS NULL
                  OR upwind_pop_13kmpl IS NULL THEN NULL
                WHEN downwind_pop_13kmpl > upwind_pop_13kmpl THEN 1::TINYINT
                ELSE 0::TINYINT
            END AS downup_13kmpl
        FROM measures
    """
    temporary = output.with_name(output.name + ".tmp")
    logging.info("Applying the directional population lookup")
    connection.execute(
        f"""
        COPY ({final_query})
        TO {sql_string(temporary)}
        (FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 250000)
        """
    )
    summary = connection.execute(
        f"""
        SELECT
            count(*),
            count(DISTINCT (unique_small_grid_id, year, month)),
            count(DISTINCT unique_small_grid_id),
            count(DISTINCT (year, month)),
            count_if(downup_13kmpl IS NULL),
            count_if(
                abs(downwind_area_13kmpl - upwind_area_13kmpl) > 1e-9
            ),
            count_if(
                downwind_pop_13kmpl < -1e-8
                OR upwind_pop_13kmpl < -1e-8
            )
        FROM read_parquet({sql_string(temporary)})
        """
    ).fetchone()
    if int(summary[0]) != expected_rows or int(summary[1]) != expected_rows:
        raise ValueError(
            f"Output has {summary[0]:,} rows and {summary[1]:,} unique keys; "
            f"expected {expected_rows:,}."
        )
    if int(summary[4]) != expected_missing_wind:
        raise ValueError(
            f"Output has {summary[4]:,} missing treatments; expected "
            f"{expected_missing_wind:,} missing-wind rows."
        )
    if int(summary[5]) or int(summary[6]):
        raise ValueError("Area symmetry or nonnegative-population check failed.")
    os.replace(temporary, output)
    return {
        "rows": int(summary[0]),
        "grids": int(summary[2]),
        "months": int(summary[3]),
        "missing_wind": int(summary[4]),
    }


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    output, database, temp_directory = derive_paths(args)
    validate_paths(args, output, database, temp_directory)
    connection = duckdb.connect(str(database))
    success = False
    try:
        configure(connection, args, temp_directory)
        panel_rows, missing_wind = import_inputs(connection, args)
        neighbor_pairs, covered_grids = build_radius_lookup(
            connection,
            args.radius_metres,
        )
        summary = calculate_and_export(
            connection,
            output,
            args.radius_metres,
            panel_rows,
            missing_wind,
        )
        connection.execute("CHECKPOINT")
        success = True
    finally:
        connection.close()

    if success and not args.keep_work_files:
        for path in (
            database,
            Path(str(database) + ".wal"),
            temp_directory,
        ):
            if path.exists():
                remove_exact_path(path, output.parent)

    logging.info("Completed 13 km placebo stage: %s", output)
    logging.info("ordered neighbor pairs: %s", f"{neighbor_pairs:,}")
    logging.info("covered focal grids: %s", f"{covered_grids:,}")
    for key, value in summary.items():
        logging.info("%s: %s", key, f"{value:,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Generate same-AC downwind/upwind population measures with DuckDB.

This is the fast, non-geometric first stage of the downwind/upwind pipeline.
It merges the 2012-2024 grid panel with monthly wind data and classifies every
other small grid in the focal grid's AC from centroid bearings. Every angle in
the calculation uses one Cartesian convention: degrees counterclockwise from
East, with East=0, North=90, West=180, and South=270 after normalization. The
focal grid is excluded because its centroid lies on the dividing line.

Output includes the requested panel/wind fields, the population measures, and
two internal fields needed by the area stage: ``ac_uq_id`` and normalized,
East-referenced ``calculation_wind_direction``.
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
except ImportError as exc:  # pragma: no cover
    raise SystemExit("DuckDB is required in the cluster Python environment.") from exc


ROOT = Path("/groups/sgulzar/sa_fires/proj_bureaucrats_farms")
INTERMEDIATE = ROOT / "data_output" / "intermediate"
DEFAULT_PANEL = INTERMEDIATE / "data_2012_2024_grid_ac.parquet"
DEFAULT_WIND = INTERMEDIATE / "_2_wind_direction_grid.parquet"
DEFAULT_POPULATION = INTERMEDIATE / "small_grid_population_2010.parquet"
DEFAULT_OUTPUT = INTERMEDIATE / "data_2012_2024_grid_ac_downup_pop.parquet"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--panel", type=Path, default=DEFAULT_PANEL)
    parser.add_argument(
        "--wind-input",
        "--wind-csv",
        dest="wind_input",
        type=Path,
        default=DEFAULT_WIND,
        help="Grid-month wind panel in Parquet (preferred) or CSV format.",
    )
    parser.add_argument("--grid-population", type=Path, default=DEFAULT_POPULATION)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
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
    return parser.parse_args()


def sql_string(value: str | Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def wind_relation(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix in {".parquet", ".pq"}:
        return f"read_parquet({sql_string(path.resolve())})"
    if suffix in {".csv", ".gz"}:
        return (
            "read_csv_auto("
            f"{sql_string(path.resolve())}, "
            "header=true, sample_size=1000000, all_varchar=false)"
        )
    raise ValueError(
        f"Unsupported wind input format {path.suffix!r}; use Parquet or CSV."
    )


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
    for source in (args.panel, args.wind_input, args.grid_population):
        if not source.is_file():
            raise FileNotFoundError(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    targets = [
        output,
        database,
        Path(str(database) + ".wal"),
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


def require_columns(
    actual: set[str], required: set[str], label: str
) -> None:
    missing = sorted(required - actual)
    if missing:
        raise KeyError(f"{label} is missing: {', '.join(missing)}")


def import_inputs(
    connection: duckdb.DuckDBPyConnection, args: argparse.Namespace
) -> int:
    panel_relation = f"read_parquet({sql_string(args.panel.resolve())})"
    wind_input_relation = wind_relation(args.wind_input)
    population_relation = (
        f"read_parquet({sql_string(args.grid_population.resolve())})"
    )

    require_columns(
        relation_columns(connection, panel_relation),
        {
            "unique_grid_id",
            "ac_uq_id",
            "province",
            "distr_id",
            "district",
            "month",
            "year",
            "downup_dummy",
        },
        "panel",
    )
    require_columns(
        relation_columns(connection, wind_input_relation),
        {
            "unique_small_grid_id",
            "month",
            "year",
            "wind_speed_av_cellid_month",
            "wind_direction_av_cellid_month",
            "rollav_wind_speed_cellid_month",
            "rollav_wind_direction_cellid_month",
        },
        "wind input",
    )
    require_columns(
        relation_columns(connection, population_relation),
        {
            "unique_small_grid_id",
            "population_2010",
            "centroid_x",
            "centroid_y",
        },
        "population Parquet",
    )

    logging.info("Importing panel, wind, and population columns")
    connection.execute(
        f"""
        CREATE TABLE panel AS
        SELECT
            CAST(unique_grid_id AS BIGINT) AS unique_small_grid_id,
            CAST(ac_uq_id AS BIGINT) AS ac_uq_id,
            CAST(province AS VARCHAR) AS province,
            CAST(distr_id AS SMALLINT) AS distr_id,
            CAST(district AS VARCHAR) AS district,
            CAST(month AS TINYINT) AS month,
            CAST(year AS SMALLINT) AS year,
            TRY_CAST(downup_dummy AS TINYINT) AS downup_dummy
        FROM {panel_relation}
        """
    )
    connection.execute(
        f"""
        CREATE TABLE wind AS
        SELECT
            CAST(unique_small_grid_id AS BIGINT) AS unique_small_grid_id,
            CAST(month AS TINYINT) AS month,
            CAST(year AS SMALLINT) AS year,
            TRY_CAST(wind_speed_av_cellid_month AS DOUBLE)
                AS wind_speed_av_cellid_month,
            TRY_CAST(wind_direction_av_cellid_month AS DOUBLE)
                AS wind_direction_av_cellid_month,
            TRY_CAST(rollav_wind_speed_cellid_month AS DOUBLE)
                AS rollav_wind_speed_cellid_month,
            TRY_CAST(rollav_wind_direction_cellid_month AS DOUBLE)
                AS rollav_wind_direction_cellid_month
        FROM {wind_input_relation}
        """
    )
    connection.execute(
        f"""
        CREATE TABLE grid_population AS
        SELECT
            CAST(unique_small_grid_id AS BIGINT) AS unique_small_grid_id,
            CAST(population_2010 AS DOUBLE) AS population_2010,
            CAST(centroid_x AS DOUBLE) AS centroid_x,
            CAST(centroid_y AS DOUBLE) AS centroid_y
        FROM {population_relation}
        """
    )

    for table, key_sql in (
        ("panel", "unique_small_grid_id, year, month"),
        ("wind", "unique_small_grid_id, year, month"),
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
            raise ValueError(
                f"{table} has {duplicates:,} duplicated key combinations."
            )

    connection.execute(
        """
        CREATE TABLE panel_wind AS
        SELECT
            p.*,
            w.wind_speed_av_cellid_month,
            w.wind_direction_av_cellid_month,
            w.rollav_wind_speed_cellid_month,
            w.rollav_wind_direction_cellid_month,
            CASE
                WHEN w.rollav_wind_direction_cellid_month IS NULL THEN NULL
                -- The source is atan2(v, u): counterclockwise from East.
                -- Normalize only its range; never reinterpret it as a
                -- clockwise-from-North compass bearing.
                ELSE fmod(
                    fmod(w.rollav_wind_direction_cellid_month, 360.0) + 360.0,
                    360.0
                )
            END AS calculation_wind_direction
        FROM panel AS p
        LEFT JOIN wind AS w USING (unique_small_grid_id, year, month)
        """
    )
    rows = int(connection.execute("SELECT count(*) FROM panel_wind").fetchone()[0])
    missing = int(
        connection.execute(
            """
            SELECT count(*) FROM panel_wind
            WHERE calculation_wind_direction IS NULL
            """
        ).fetchone()[0]
    )
    invalid_direction = int(
        connection.execute(
            """
            SELECT count(*) FROM panel_wind
            WHERE calculation_wind_direction IS NOT NULL
              AND NOT (
                  calculation_wind_direction >= 0.0
                  AND calculation_wind_direction < 360.0
              )
            """
        ).fetchone()[0]
    )
    if invalid_direction:
        raise ValueError(
            f"The normalized East-referenced direction has "
            f"{invalid_direction:,} values outside [0, 360)."
        )
    logging.info("Panel rows: %s", f"{rows:,}")
    logging.info("Rows missing rolling direction: %s", f"{missing:,}")
    logging.info(
        "Direction convention: counterclockwise from East, normalized [0, 360)"
    )
    connection.execute("ANALYZE panel_wind")
    connection.execute("ANALYZE grid_population")
    return rows


def build_lookup(connection: duckdb.DuckDBPyConnection) -> None:
    connection.execute(
        """
        CREATE TABLE grid_ac AS
        SELECT
            membership.ac_uq_id,
            membership.unique_small_grid_id,
            population.population_2010,
            population.centroid_x,
            population.centroid_y
        FROM (
            SELECT
                unique_small_grid_id,
                min(ac_uq_id) AS ac_uq_id
            FROM panel
            GROUP BY unique_small_grid_id
            HAVING count(DISTINCT ac_uq_id) = 1
        ) AS membership
        INNER JOIN grid_population AS population USING (unique_small_grid_id)
        """
    )
    panel_grids, lookup_grids = connection.execute(
        """
        SELECT
            (SELECT count(DISTINCT unique_small_grid_id) FROM panel),
            (SELECT count(*) FROM grid_ac)
        """
    ).fetchone()
    if panel_grids != lookup_grids:
        raise ValueError(
            f"Only {lookup_grids:,} of {panel_grids:,} panel grids have "
            "one AC and a population/centroid record."
        )
    connection.execute("ANALYZE grid_ac")
    connection.execute(
        """
        CREATE TABLE ac_totals AS
        SELECT
            ac_uq_id,
            sum(population_2010) AS total_population_2010,
            count(*) AS number_grids
        FROM grid_ac
        GROUP BY ac_uq_id
        """
    )
    expected_pairs = int(
        connection.execute(
            """
            SELECT sum(
                CAST(number_grids AS HUGEINT)
                * CAST(number_grids - 1 AS HUGEINT)
            )
            FROM ac_totals
            """
        ).fetchone()[0]
        or 0
    )
    logging.info("Ordered same-AC pairs: %s", f"{expected_pairs:,}")

    connection.execute(
        """
        CREATE TABLE pair_intervals AS
        WITH bearings AS (
            SELECT
                focal.ac_uq_id,
                focal.unique_small_grid_id AS focal_grid_id,
                comparison.population_2010 AS comparison_population,
                -- Cartesian bearing, counterclockwise from East. This is the
                -- same reference axis and rotation used by atan2(v10, u10).
                fmod(
                    degrees(
                        atan2(
                            comparison.centroid_y - focal.centroid_y,
                            comparison.centroid_x - focal.centroid_x
                        )
                    ) + 360.0,
                    360.0
                ) AS bearing
            FROM grid_ac AS focal
            INNER JOIN grid_ac AS comparison
                ON focal.ac_uq_id = comparison.ac_uq_id
               AND focal.unique_small_grid_id
                   <> comparison.unique_small_grid_id
        )
        SELECT
            ac_uq_id,
            focal_grid_id,
            comparison_population,
            fmod(bearing + 270.0, 360.0) AS start_angle,
            fmod(bearing + 90.0, 360.0) AS end_angle
        FROM bearings
        """
    )
    connection.execute(
        """
        CREATE TABLE angle_events AS
        WITH raw_events AS (
            SELECT
                ac_uq_id,
                unique_small_grid_id AS focal_grid_id,
                0.0::DOUBLE AS event_angle,
                0.0::DOUBLE AS delta_population
            FROM grid_ac

            UNION ALL
            SELECT ac_uq_id, focal_grid_id, start_angle + 1e-10,
                   comparison_population
            FROM pair_intervals WHERE start_angle < end_angle

            UNION ALL
            SELECT ac_uq_id, focal_grid_id, end_angle,
                   -comparison_population
            FROM pair_intervals WHERE start_angle < end_angle

            UNION ALL
            SELECT ac_uq_id, focal_grid_id, 0.0,
                   comparison_population
            FROM pair_intervals WHERE start_angle > end_angle

            UNION ALL
            SELECT ac_uq_id, focal_grid_id, end_angle,
                   -comparison_population
            FROM pair_intervals WHERE start_angle > end_angle

            UNION ALL
            SELECT ac_uq_id, focal_grid_id, start_angle + 1e-10,
                   comparison_population
            FROM pair_intervals WHERE start_angle > end_angle
        ),
        collapsed AS (
            SELECT
                ac_uq_id,
                focal_grid_id,
                event_angle,
                sum(delta_population) AS delta_population
            FROM raw_events
            GROUP BY ALL
        )
        SELECT
            ac_uq_id,
            focal_grid_id,
            event_angle,
            sum(delta_population) OVER (
                PARTITION BY ac_uq_id, focal_grid_id
                ORDER BY event_angle
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS downwind_pop
        FROM collapsed
        """
    )
    connection.execute("DROP TABLE pair_intervals")
    connection.execute("ANALYZE angle_events")


def calculate_and_export(
    connection: duckdb.DuckDBPyConnection,
    output: Path,
    expected_rows: int,
) -> dict[str, int]:
    logging.info("Applying the directional population lookup")
    final_query = """
        WITH directional AS (
            SELECT
                p.unique_small_grid_id,
                p.year,
                p.month,
                event.downwind_pop
            FROM panel_wind AS p
            ASOF LEFT JOIN angle_events AS event
                ON p.ac_uq_id = event.ac_uq_id
               AND p.unique_small_grid_id = event.focal_grid_id
               AND p.calculation_wind_direction >= event.event_angle
        ),
        measures AS (
            SELECT
                p.*,
                CASE
                    WHEN p.calculation_wind_direction IS NULL THEN NULL
                    ELSE greatest(0.0, directional.downwind_pop)
                END AS downwind_pop,
                CASE
                    WHEN p.calculation_wind_direction IS NULL THEN NULL
                    ELSE greatest(
                        0.0,
                        totals.total_population_2010
                        - focal.population_2010
                        - directional.downwind_pop
                    )
                END AS upwind_pop
            FROM panel_wind AS p
            INNER JOIN directional USING (unique_small_grid_id, year, month)
            INNER JOIN grid_ac AS focal
                USING (unique_small_grid_id, ac_uq_id)
            INNER JOIN ac_totals AS totals USING (ac_uq_id)
        )
        SELECT
            unique_small_grid_id,
            ac_uq_id,
            province,
            distr_id,
            district,
            month,
            year,
            wind_speed_av_cellid_month,
            wind_direction_av_cellid_month,
            rollav_wind_speed_cellid_month,
            rollav_wind_direction_cellid_month,
            calculation_wind_direction,
            downup_dummy,
            CASE
                WHEN downwind_pop IS NULL OR upwind_pop IS NULL THEN NULL
                WHEN downwind_pop > upwind_pop THEN 1::TINYINT
                ELSE 0::TINYINT
            END AS downup_ac_pop,
            downwind_pop,
            upwind_pop
        FROM measures
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
                WHERE calculation_wind_direction IS NULL
            ) AS missing_wind
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
            f"Output has {summary[0]:,} rows and {duplicate_keys:,} duplicate "
            f"keys; expected {expected_rows:,} rows."
        )
    return {
        "rows": int(summary[0]),
        "grids": int(summary[1]),
        "months": int(summary[2]),
        "missing_wind": int(summary[3]),
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
        panel_rows = import_inputs(connection, args)
        build_lookup(connection)
        summary = calculate_and_export(connection, output, panel_rows)
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

    logging.info("Completed population stage: %s", output)
    for key, value in summary.items():
        logging.info("%s: %s", key, f"{value:,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

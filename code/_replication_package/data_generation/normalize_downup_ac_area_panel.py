#!/usr/bin/env python3
"""Convert the legacy wide AC-area panel to its canonical narrow schema.

This is a one-time, streaming DuckDB migration.  It reuses the already
calculated area values, attaches ``ac_uq_id`` from the authoritative
population panel, and atomically replaces the old area Parquet.  Geometry is
not recalculated.
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

import duckdb


ROOT = Path("/groups/sgulzar/sa_fires/proj_bureaucrats_farms")
INTERMEDIATE = ROOT / "data_output" / "intermediate"
DEFAULT_POPULATION = INTERMEDIATE / "data_2012_2024_grid_ac_downup_pop.parquet"
DEFAULT_AREA = INTERMEDIATE / "data_2012_2024_grid_ac_downup.parquet"
CANONICAL_COLUMNS = (
    "unique_small_grid_id",
    "ac_uq_id",
    "year",
    "month",
    "downup_ac_area",
    "downwind_area",
    "upwind_area",
)


def sql_string(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def columns(connection: duckdb.DuckDBPyConnection, relation: str) -> tuple[str, ...]:
    return tuple(
        row[0]
        for row in connection.execute(f"DESCRIBE SELECT * FROM {relation}").fetchall()
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--population", type=Path, default=DEFAULT_POPULATION)
    parser.add_argument("--area", type=Path, default=DEFAULT_AREA)
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--threads", type=int, default=10)
    parser.add_argument("--memory-limit", default="120GB")
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
    )
    population = args.population.resolve()
    area = args.area.resolve()
    output = (args.output or args.area).resolve()
    if not population.exists() or not area.exists():
        raise FileNotFoundError("Population and area Parquet files must both exist.")
    if output.exists() and output != area and not args.overwrite:
        raise FileExistsError(f"Output already exists: {output}")

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + f".tmp-{os.getpid()}.parquet")
    pop_relation = f"read_parquet({sql_string(population)})"
    area_relation = f"read_parquet({sql_string(area)})"
    connection = duckdb.connect()
    try:
        connection.execute(f"SET threads = {max(1, args.threads)}")
        connection.execute(f"SET memory_limit = {sql_string(args.memory_limit)}")
        connection.execute(
            f"SET temp_directory = {sql_string(output.parent / '.duckdb_tmp')}"
        )
        pop_columns = set(columns(connection, pop_relation))
        area_columns_ordered = columns(connection, area_relation)
        area_columns = set(area_columns_ordered)
        required_population = {
            "unique_small_grid_id",
            "ac_uq_id",
            "year",
            "month",
            "rollav_wind_direction_cellid_month",
        }
        required_area = {
            "unique_small_grid_id",
            "year",
            "month",
            "downup_ac_area",
            "downwind_area",
            "upwind_area",
        }
        if missing := sorted(required_population - pop_columns):
            raise KeyError("Population panel is missing: " + ", ".join(missing))
        if missing := sorted(required_area - area_columns):
            raise KeyError("Area panel is missing: " + ", ".join(missing))

        pop_rows, pop_keys = connection.execute(
            f"""
            SELECT count(*), count(DISTINCT (unique_small_grid_id, year, month))
            FROM {pop_relation}
            """
        ).fetchone()
        area_rows, area_keys = connection.execute(
            f"""
            SELECT count(*), count(DISTINCT (unique_small_grid_id, year, month))
            FROM {area_relation}
            """
        ).fetchone()
        if pop_rows != pop_keys or area_rows != area_keys:
            raise ValueError("Population and legacy area panel keys must be unique.")

        overlap = connection.execute(
            f"""
            WITH p AS (
                SELECT unique_small_grid_id, year, month FROM {pop_relation}
            ), a AS (
                SELECT unique_small_grid_id, year, month FROM {area_relation}
            )
            SELECT
                count_if(p.unique_small_grid_id IS NOT NULL
                         AND a.unique_small_grid_id IS NULL),
                count_if(p.unique_small_grid_id IS NULL
                         AND a.unique_small_grid_id IS NOT NULL),
                count_if(p.unique_small_grid_id IS NOT NULL
                         AND a.unique_small_grid_id IS NOT NULL)
            FROM p FULL OUTER JOIN a USING (unique_small_grid_id, year, month)
            """
        ).fetchone()
        logging.info(
            "Merge population x legacy area [grid-month] | left_only=%s | "
            "right_only=%s | both=%s",
            *(f"{int(value):,}" for value in overlap),
        )
        if tuple(map(int, overlap)) != (0, 0, int(pop_rows)):
            raise ValueError("Legacy area rows do not exactly cover the population panel.")

        if "rollav_wind_direction_cellid_month" in area_columns:
            direction_mismatches = int(
                connection.execute(
                    f"""
                    SELECT count_if(
                        a.rollav_wind_direction_cellid_month IS DISTINCT FROM
                        p.rollav_wind_direction_cellid_month
                    )
                    FROM {pop_relation} AS p
                    JOIN {area_relation} AS a
                      USING (unique_small_grid_id, year, month)
                    """
                ).fetchone()[0]
            )
            logging.info("Rolling-direction mismatches: %s", f"{direction_mismatches:,}")
            if direction_mismatches:
                raise ValueError(
                    "The legacy areas were calculated with a different rolling "
                    "direction; geometry must be rebuilt instead of migrated."
                )
        elif tuple(area_columns_ordered) == CANONICAL_COLUMNS:
            logging.info("Area panel already has the canonical narrow schema.")
            return 0
        else:
            raise KeyError(
                "Legacy area panel has no copied rolling direction, so safe "
                "reuse cannot be verified."
            )

        connection.execute(
            f"""
            COPY (
                SELECT
                    p.unique_small_grid_id,
                    p.ac_uq_id,
                    p.year,
                    p.month,
                    a.downup_ac_area,
                    a.downwind_area,
                    a.upwind_area
                FROM {pop_relation} AS p
                LEFT JOIN {area_relation} AS a
                  USING (unique_small_grid_id, year, month)
            ) TO {sql_string(temporary)}
            (FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 250000)
            """
        )
        migrated = f"read_parquet({sql_string(temporary)})"
        new_rows, new_keys = connection.execute(
            f"""
            SELECT count(*), count(DISTINCT (
                unique_small_grid_id, ac_uq_id, year, month
            )) FROM {migrated}
            """
        ).fetchone()
        if new_rows != pop_rows or new_rows != new_keys:
            raise ValueError("Migrated area panel failed row/key validation.")
        if columns(connection, migrated) != CANONICAL_COLUMNS:
            raise ValueError("Migrated area panel has an unexpected schema.")
    finally:
        connection.close()

    os.replace(temporary, output)
    logging.info("Canonical area panel written: %s", output)
    logging.info("Rows: %s | columns: %s", f"{int(pop_rows):,}", len(CANONICAL_COLUMNS))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        logging.exception("Area-panel normalization failed")
        raise

#!/usr/bin/env python3
"""Generate AC-month population downwind of the AC's rice-producing grids.

This is the rice-source companion of ``build_downup_ac_pop_cluster.py``. The
original measure takes each small grid's centroid as the origin; here the
origins are the AC's rice zones and the unit of observation is AC x month.

For every AC ``a`` and month ``m``:

1. A grid is a rice zone when its MapSPAM 2010 rice production is positive and
   at least a production quantile. Two definitions are produced side by side:
   the within-AC quantile (``--rice-percentile``; unsuffixed columns) and the
   quantile across every grid of the sample (``--rice-sample-percentile``;
   columns suffixed ``_sample``).
2. The AC wind direction is the unit-vector mean of the grids' observed monthly
   ``wind_direction_av_cellid_month``. Every angle uses the pipeline convention:
   degrees counterclockwise from East.
3. A grid is downwind when it is a rice zone or lies downwind of at least one
   rice zone. With one direction per AC-month, that is every grid whose centroid
   projects onto the wind vector beyond the most-upwind rice zone.
4. ``downup_ac_pop_rice`` (and ``downup_ac_pop_rice_sample``) equals 1 when the
   downwind population exceeds half of the AC population. ACs without rice
   zones get zero downwind population.

Grids with a missing raw or calculation wind direction in any month are
excluded in their entirety, matching the wind-complete base of
``build_0_master_dataset.py``, so the output covers exactly its AC-months.
The output is written as Parquet and as a Stata ``.dta`` file.
"""

from __future__ import annotations

import argparse
import logging
import os
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

try:
    import duckdb
    import pandas as pd
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "DuckDB and pandas are required in the cluster Python environment."
    ) from exc


ROOT = Path("/groups/sgulzar/sa_fires/proj_bureaucrats_farms")
INTERMEDIATE = ROOT / "data_output" / "intermediate"
DEFAULT_PANEL = INTERMEDIATE / "data_2012_2024_grid_ac_downup_pop.parquet"
DEFAULT_POPULATION = INTERMEDIATE / "small_grid_population_2010.parquet"
DEFAULT_RICE = INTERMEDIATE / "small_grid_rice_2010.parquet"
DEFAULT_OUTPUT = INTERMEDIATE / "data_2012_2024_ac_downup_pop_rice.parquet"

# Centroids are in metres (EPSG:7755). A grid must clear the most-upwind rice
# zone by more than this margin, so floating-point noise never moves grids that
# lie on the dividing line.
PROJECTION_TOLERANCE_M = 1e-6
# Unit-vector sums shorter than this (per grid) have no defined direction.
RESULTANT_TOLERANCE = 1e-9


@dataclass(frozen=True)
class RiceZoneDefinition:
    """One rice-zone rule and the output columns it produces."""

    flag: str
    cutoff: str
    suffix: str
    label: str


RICE_ZONE_DEFINITIONS = (
    RiceZoneDefinition(
        flag="is_rice",
        cutoff="rice_cutoff_ac",
        suffix="",
        label="within-AC",
    ),
    RiceZoneDefinition(
        flag="is_rice_sample",
        cutoff="rice_cutoff_sample",
        suffix="_sample",
        label="sample",
    ),
)

OUTPUT_COLUMNS = (
    "ac_uq_id",
    "year",
    "month",
    "wind_direction_ac",
    "n_grids_ac",
    "total_pop_ac",
    *(
        column
        for zone in RICE_ZONE_DEFINITIONS
        for column in (
            f"n_rice_grids_ac{zone.suffix}",
            zone.cutoff,
            f"downwind_pop_rice_ac{zone.suffix}",
            f"upwind_pop_rice_ac{zone.suffix}",
            f"down_percent_pop_rice_ac{zone.suffix}",
            f"downup_ac_pop_rice{zone.suffix}",
        )
    ),
)

STATA_VARIABLE_LABELS = {
    "ac_uq_id": "Assembly constituency ID",
    "year": "Year",
    "month": "Month",
    "wind_direction_ac": "AC mean monthly wind direction (deg CCW from East)",
    "n_grids_ac": "Grids in AC",
    "total_pop_ac": "AC population 2010",
    "n_rice_grids_ac": "Rice-zone grids (>= within-AC percentile)",
    "rice_cutoff_ac": "Within-AC rice production cutoff (t)",
    "downwind_pop_rice_ac": "Pop. downwind of rice zones (within-AC cutoff)",
    "upwind_pop_rice_ac": "Pop. not downwind of rice zones (within-AC cutoff)",
    "down_percent_pop_rice_ac": "% AC pop. downwind of rice zones (within-AC cutoff)",
    "downup_ac_pop_rice": "Downwind pop. > 50% (within-AC cutoff)",
    "n_rice_grids_ac_sample": "Rice-zone grids (>= sample percentile)",
    "rice_cutoff_sample": "Sample rice production cutoff (t)",
    "downwind_pop_rice_ac_sample": "Pop. downwind of rice zones (sample cutoff)",
    "upwind_pop_rice_ac_sample": "Pop. not downwind of rice zones (sample cutoff)",
    "down_percent_pop_rice_ac_sample": "% AC pop. downwind of rice zones (sample cutoff)",
    "downup_ac_pop_rice_sample": "Downwind pop. > 50% (sample cutoff)",
}


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--panel", type=Path, default=DEFAULT_PANEL)
    parser.add_argument("--grid-population", type=Path, default=DEFAULT_POPULATION)
    parser.add_argument("--grid-rice", type=Path, default=DEFAULT_RICE)
    parser.add_argument(
        "--rice-column",
        default="rice_prod_2010",
        help="Column in --grid-rice that measures rice production.",
    )
    parser.add_argument(
        "--rice-percentile",
        type=float,
        default=0.5,
        help="Within-AC production quantile a grid must reach to be a rice zone.",
    )
    parser.add_argument(
        "--rice-sample-percentile",
        type=float,
        default=0.5,
        help=(
            "Production quantile across all sample grids a grid must reach to "
            "be a rice zone in the _sample columns."
        ),
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--output-dta",
        type=Path,
        default=None,
        help="Stata copy of the output; defaults to --output with a .dta suffix.",
    )
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
    args = parser.parse_args(argv)
    for name in ("rice_percentile", "rice_sample_percentile"):
        if not 0.0 <= getattr(args, name) <= 1.0:
            parser.error(f"--{name.replace('_', '-')} must lie in [0, 1].")
    return args


def sql_string(value: str | Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def quote_identifier(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def derive_paths(args: argparse.Namespace) -> tuple[Path, Path, Path, Path]:
    output = args.output.resolve()
    output_dta = (
        args.output_dta.resolve()
        if args.output_dta
        else output.with_suffix(".dta")
    )
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
    return output, output_dta, database, temp_directory


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
    output_dta: Path,
    database: Path,
    temp_directory: Path,
) -> None:
    for source in (args.panel, args.grid_population, args.grid_rice):
        if not source.is_file():
            raise FileNotFoundError(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    output_dta.parent.mkdir(parents=True, exist_ok=True)
    targets = [
        output,
        output_dta,
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
            remove_exact_path(path, path.parent)
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
) -> None:
    """Create ``panel_wind``, ``grid_population`` and ``grid_rice``."""

    panel_relation = f"read_parquet({sql_string(args.panel.resolve())})"
    population_relation = (
        f"read_parquet({sql_string(args.grid_population.resolve())})"
    )
    rice_relation = f"read_parquet({sql_string(args.grid_rice.resolve())})"

    require_columns(
        relation_columns(connection, panel_relation),
        {
            "unique_small_grid_id",
            "ac_uq_id",
            "year",
            "month",
            "wind_direction_av_cellid_month",
            "calculation_wind_direction",
        },
        "population panel",
    )
    require_columns(
        relation_columns(connection, population_relation),
        {"unique_small_grid_id", "population_2010", "centroid_x", "centroid_y"},
        "population Parquet",
    )
    require_columns(
        relation_columns(connection, rice_relation),
        {"unique_small_grid_id", args.rice_column},
        "rice Parquet",
    )

    logging.info("Importing panel, wind, population, and rice columns")
    connection.execute(
        f"""
        CREATE TABLE excluded_wind_grids AS
        SELECT DISTINCT CAST(unique_small_grid_id AS BIGINT) AS unique_small_grid_id
        FROM {panel_relation}
        WHERE
            wind_direction_av_cellid_month IS NULL
            OR calculation_wind_direction IS NULL
        """
    )
    connection.execute(
        f"""
        CREATE TABLE panel_wind AS
        SELECT
            CAST(p.unique_small_grid_id AS BIGINT) AS unique_small_grid_id,
            CAST(p.ac_uq_id AS BIGINT) AS ac_uq_id,
            CAST(p.year AS SMALLINT) AS year,
            CAST(p.month AS TINYINT) AS month,
            CAST(p.wind_direction_av_cellid_month AS DOUBLE)
                AS wind_direction_av_cellid_month
        FROM {panel_relation} AS p
        ANTI JOIN excluded_wind_grids AS e
            ON CAST(p.unique_small_grid_id AS BIGINT) = e.unique_small_grid_id
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
    connection.execute(
        f"""
        CREATE TABLE grid_rice AS
        SELECT
            CAST(unique_small_grid_id AS BIGINT) AS unique_small_grid_id,
            CAST({quote_identifier(args.rice_column)} AS DOUBLE) AS rice_prod
        FROM {rice_relation}
        """
    )

    for table, key_sql in (
        ("panel_wind", "unique_small_grid_id, year, month"),
        ("grid_population", "unique_small_grid_id"),
        ("grid_rice", "unique_small_grid_id"),
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

    excluded, rows = connection.execute(
        """
        SELECT
            (SELECT count(*) FROM excluded_wind_grids),
            (SELECT count(*) FROM panel_wind)
        """
    ).fetchone()
    logging.info("Grids excluded for missing wind: %s", f"{excluded:,}")
    logging.info("Retained panel rows: %s", f"{rows:,}")


def build_grid_ac(
    connection: duckdb.DuckDBPyConnection,
    rice_percentile: float,
    sample_percentile: float = 0.5,
) -> None:
    """Create ``grid_ac``: one row per grid with its AC, weights, and zone flags.

    The sample cutoff is the quantile across the retained panel grids, each
    counted once, so it does not depend on how many months a grid appears.
    """

    for value in (rice_percentile, sample_percentile):
        if not 0.0 <= value <= 1.0:
            raise ValueError("Rice percentiles must lie in [0, 1].")
    connection.execute(
        f"""
        CREATE TABLE grid_ac AS
        WITH membership AS (
            SELECT
                unique_small_grid_id,
                min(ac_uq_id) AS ac_uq_id
            FROM panel_wind
            GROUP BY unique_small_grid_id
            HAVING count(DISTINCT ac_uq_id) = 1
        ),
        joined AS (
            SELECT
                membership.ac_uq_id,
                membership.unique_small_grid_id,
                population.population_2010,
                population.centroid_x,
                population.centroid_y,
                rice.rice_prod
            FROM membership
            INNER JOIN grid_population AS population USING (unique_small_grid_id)
            INNER JOIN grid_rice AS rice USING (unique_small_grid_id)
        ),
        ac_cutoffs AS (
            SELECT
                ac_uq_id,
                quantile_cont(rice_prod, {float(rice_percentile)!r})
                    AS rice_cutoff_ac
            FROM joined
            GROUP BY ac_uq_id
        ),
        sample_cutoff AS (
            SELECT
                quantile_cont(rice_prod, {float(sample_percentile)!r})
                    AS rice_cutoff_sample
            FROM joined
        )
        SELECT
            joined.*,
            ac_cutoffs.rice_cutoff_ac,
            sample_cutoff.rice_cutoff_sample,
            (
                joined.rice_prod > 0.0
                AND joined.rice_prod >= ac_cutoffs.rice_cutoff_ac
            ) AS is_rice,
            (
                joined.rice_prod > 0.0
                AND joined.rice_prod >= sample_cutoff.rice_cutoff_sample
            ) AS is_rice_sample
        FROM joined
        INNER JOIN ac_cutoffs USING (ac_uq_id)
        CROSS JOIN sample_cutoff
        """
    )
    panel_grids, lookup_grids, incomplete = connection.execute(
        """
        SELECT
            (SELECT count(DISTINCT unique_small_grid_id) FROM panel_wind),
            (SELECT count(*) FROM grid_ac),
            (
                SELECT count_if(
                    population_2010 IS NULL
                    OR centroid_x IS NULL
                    OR centroid_y IS NULL
                    OR rice_prod IS NULL
                )
                FROM grid_ac
            )
        """
    ).fetchone()
    if panel_grids != lookup_grids:
        raise ValueError(
            f"Only {lookup_grids:,} of {panel_grids:,} panel grids have one AC "
            "and both a population/centroid and a rice record."
        )
    if incomplete:
        raise ValueError(
            f"{incomplete:,} grids have missing population, centroid, or rice."
        )
    percentiles = {"is_rice": rice_percentile, "is_rice_sample": sample_percentile}
    for zone in RICE_ZONE_DEFINITIONS:
        rice_grids, rice_acs, acs = connection.execute(
            f"""
            SELECT
                count_if({zone.flag}),
                count(DISTINCT ac_uq_id) FILTER (WHERE {zone.flag}),
                count(DISTINCT ac_uq_id)
            FROM grid_ac
            """
        ).fetchone()
        logging.info(
            "Rice zones, %s cutoff (production > 0 and >= p%g): "
            "%s grids in %s of %s ACs",
            zone.label,
            100.0 * percentiles[zone.flag],
            f"{rice_grids:,}",
            f"{rice_acs:,}",
            f"{acs:,}",
        )
    sample_cutoff = connection.execute(
        "SELECT any_value(rice_cutoff_sample) FROM grid_ac"
    ).fetchone()[0]
    logging.info("Sample rice production cutoff (t): %.6g", sample_cutoff)
    connection.execute("ANALYZE grid_ac")


def build_ac_month_measures(connection: duckdb.DuckDBPyConnection) -> None:
    """Create ``ac_month_pop_rice`` with the columns in ``OUTPUT_COLUMNS``."""

    def per_zone(template: str, separator: str = ",\n") -> str:
        return separator.join(
            template.format(
                flag=zone.flag, cutoff=zone.cutoff, sfx=zone.suffix
            )
            for zone in RICE_ZONE_DEFINITIONS
        )

    # Built outside the f-string below so it also parses on Python 3.11.
    tolerance = repr(PROJECTION_TOLERANCE_M)
    zone_totals = per_zone(
        "count_if({flag}) AS n_rice_grids_ac{sfx}, "
        "any_value({cutoff}) AS {cutoff}"
    )
    zone_flags = per_zone("g.{flag}")
    zone_thresholds = per_zone(
        "min(projection) FILTER (WHERE {flag}) AS rice_threshold{sfx}"
    )
    zone_downwind = per_zone(
        "coalesce(sum(m.population_2010) FILTER ("
        "WHERE m.{flag} OR m.projection > t.rice_threshold{sfx} + "
        + tolerance
        + "), 0.0) AS downwind_pop{sfx}"
    )
    zone_measures = per_zone(
        "totals.n_rice_grids_ac{sfx}, totals.{cutoff}, "
        "CASE WHEN totals.n_rice_grids_ac{sfx} = 0 THEN 0.0 "
        "WHEN w.wind_x IS NULL THEN NULL "
        "ELSE d.downwind_pop{sfx} END AS downwind_pop_rice_ac{sfx}"
    )
    zone_outputs = per_zone(
        "n_rice_grids_ac{sfx}, {cutoff}, downwind_pop_rice_ac{sfx}, "
        "total_pop_ac - downwind_pop_rice_ac{sfx} AS upwind_pop_rice_ac{sfx}, "
        "100.0 * downwind_pop_rice_ac{sfx} / nullif(total_pop_ac, 0.0) "
        "AS down_percent_pop_rice_ac{sfx}, "
        "CASE WHEN downwind_pop_rice_ac{sfx} IS NULL "
        "OR total_pop_ac <= 0.0 THEN 0 "
        "WHEN 2.0 * downwind_pop_rice_ac{sfx} > total_pop_ac THEN 1 "
        "ELSE 0 END::TINYINT AS downup_ac_pop_rice{sfx}"
    )
    connection.execute(
        f"""
        CREATE TABLE ac_month_pop_rice AS
        WITH ac_totals AS (
            SELECT
                ac_uq_id,
                count(*) AS n_grids_ac,
                sum(population_2010) AS total_pop_ac,
                {zone_totals}
            FROM grid_ac
            GROUP BY ac_uq_id
        ),
        wind_sums AS (
            SELECT
                p.ac_uq_id,
                p.year,
                p.month,
                count(*) AS wind_grids,
                sum(cos(radians(p.wind_direction_av_cellid_month))) AS sum_x,
                sum(sin(radians(p.wind_direction_av_cellid_month))) AS sum_y
            FROM panel_wind AS p
            INNER JOIN grid_ac AS g USING (unique_small_grid_id, ac_uq_id)
            GROUP BY p.ac_uq_id, p.year, p.month
        ),
        ac_wind AS (
            SELECT
                ac_uq_id,
                year,
                month,
                CASE
                    WHEN sqrt(sum_x * sum_x + sum_y * sum_y)
                         <= {RESULTANT_TOLERANCE!r} * wind_grids THEN NULL
                    ELSE sum_x / sqrt(sum_x * sum_x + sum_y * sum_y)
                END AS wind_x,
                CASE
                    WHEN sqrt(sum_x * sum_x + sum_y * sum_y)
                         <= {RESULTANT_TOLERANCE!r} * wind_grids THEN NULL
                    ELSE sum_y / sqrt(sum_x * sum_x + sum_y * sum_y)
                END AS wind_y
            FROM wind_sums
        ),
        grid_month AS (
            SELECT
                w.ac_uq_id,
                w.year,
                w.month,
                g.population_2010,
                {zone_flags},
                g.centroid_x * w.wind_x + g.centroid_y * w.wind_y AS projection
            FROM ac_wind AS w
            INNER JOIN grid_ac AS g USING (ac_uq_id)
        ),
        -- The most-upwind rice zone: everything beyond its perpendicular line is
        -- downwind of at least one rice zone.
        thresholds AS (
            SELECT
                ac_uq_id,
                year,
                month,
                {zone_thresholds}
            FROM grid_month
            GROUP BY ac_uq_id, year, month
        ),
        downwind AS (
            SELECT
                m.ac_uq_id,
                m.year,
                m.month,
                {zone_downwind}
            FROM grid_month AS m
            INNER JOIN thresholds AS t USING (ac_uq_id, year, month)
            GROUP BY m.ac_uq_id, m.year, m.month
        ),
        measures AS (
            SELECT
                w.ac_uq_id,
                w.year,
                w.month,
                CASE
                    WHEN w.wind_x IS NULL THEN NULL
                    ELSE fmod(degrees(atan2(w.wind_y, w.wind_x)) + 360.0, 360.0)
                END AS wind_direction_ac,
                totals.n_grids_ac,
                totals.total_pop_ac,
                {zone_measures}
            FROM ac_wind AS w
            INNER JOIN ac_totals AS totals USING (ac_uq_id)
            INNER JOIN downwind AS d USING (ac_uq_id, year, month)
        )
        SELECT
            ac_uq_id,
            year,
            month,
            wind_direction_ac,
            n_grids_ac,
            total_pop_ac,
            {zone_outputs}
        FROM measures
        """
    )


def export(
    connection: duckdb.DuckDBPyConnection, output: Path, output_dta: Path
) -> dict[str, dict[str, float] | int]:
    expected_rows = int(
        connection.execute(
            """
            SELECT count(*)
            FROM (SELECT DISTINCT ac_uq_id, year, month FROM panel_wind)
            """
        ).fetchone()[0]
    )
    missing_downup_sql = " + ".join(
        f"count_if(downup_ac_pop_rice{zone.suffix} IS NULL)"
        for zone in RICE_ZONE_DEFINITIONS
    )
    rows, keys, missing_downup = connection.execute(
        f"""
        SELECT
            count(*),
            count(DISTINCT (ac_uq_id, year, month)),
            {missing_downup_sql}
        FROM ac_month_pop_rice
        """
    ).fetchone()
    if rows != expected_rows or keys != rows:
        raise ValueError(
            f"AC-month output has {rows:,} rows and {keys:,} distinct keys; "
            f"expected {expected_rows:,}."
        )
    if missing_downup:
        raise ValueError(
            f"downup_ac_pop_rice columns are missing on {missing_downup:,} cells."
        )

    columns = ", ".join(OUTPUT_COLUMNS)
    ordered_query = f"""
        SELECT {columns}
        FROM ac_month_pop_rice
        ORDER BY ac_uq_id, year, month
    """
    connection.execute(
        f"""
        COPY ({ordered_query}) TO {sql_string(output)}
        (FORMAT PARQUET, COMPRESSION ZSTD)
        """
    )
    write_stata(connection.execute(ordered_query).df(), output_dta)

    summary: dict[str, dict[str, float] | int] = {
        "rows": int(rows),
        "acs": int(
            connection.execute(
                "SELECT count(DISTINCT ac_uq_id) FROM ac_month_pop_rice"
            ).fetchone()[0]
        ),
        "ac_months_without_wind_direction": int(
            connection.execute(
                "SELECT count_if(wind_direction_ac IS NULL) FROM ac_month_pop_rice"
            ).fetchone()[0]
        ),
    }
    for zone in RICE_ZONE_DEFINITIONS:
        sfx = zone.suffix
        values = connection.execute(
            f"""
            SELECT
                count_if(n_rice_grids_ac{sfx} = 0),
                avg(downup_ac_pop_rice{sfx}::DOUBLE),
                avg(down_percent_pop_rice_ac{sfx})
                    FILTER (WHERE n_rice_grids_ac{sfx} > 0),
                avg((down_percent_pop_rice_ac{sfx} >= 95.0)::DOUBLE)
                    FILTER (WHERE n_rice_grids_ac{sfx} > 0)
            FROM ac_month_pop_rice
            """
        ).fetchone()
        summary[zone.label] = {
            "ac_months_without_rice": float(values[0]),
            "share_downup": float(values[1] or 0.0),
            "mean_down_percent_with_rice": float(values[2] or 0.0),
            "share_saturated_with_rice": float(values[3] or 0.0),
        }
    return summary


def write_stata(frame: pd.DataFrame, output_dta: Path) -> None:
    """Write the AC-month table as a Stata 14+ file keyed on ac_uq_id year month."""

    if list(frame.columns) != list(OUTPUT_COLUMNS):
        raise ValueError("The Stata export does not match OUTPUT_COLUMNS.")
    too_long = [column for column in frame.columns if len(column) > 32]
    if too_long:
        raise ValueError(f"Stata variable names exceed 32 characters: {too_long}")
    frame = frame.astype(
        {
            "ac_uq_id": "int32",
            "year": "int16",
            "month": "int8",
            "n_grids_ac": "int32",
            **{
                f"n_rice_grids_ac{zone.suffix}": "int32"
                for zone in RICE_ZONE_DEFINITIONS
            },
            **{
                f"downup_ac_pop_rice{zone.suffix}": "int8"
                for zone in RICE_ZONE_DEFINITIONS
            },
        }
    )
    temporary = output_dta.with_name(output_dta.name + ".tmp")
    frame.to_stata(
        temporary,
        write_index=False,
        version=118,
        data_label="AC-month population downwind of rice zones",
        variable_labels=STATA_VARIABLE_LABELS,
    )
    os.replace(temporary, output_dta)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    output, output_dta, database, temp_directory = derive_paths(args)
    validate_paths(args, output, output_dta, database, temp_directory)

    connection = duckdb.connect(str(database))
    success = False
    try:
        configure(connection, args, temp_directory)
        import_inputs(connection, args)
        build_grid_ac(connection, args.rice_percentile, args.rice_sample_percentile)
        build_ac_month_measures(connection)
        summary = export(connection, output, output_dta)
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
                remove_exact_path(path, path.parent)

    logging.info("Completed AC-month rice-source population stage")
    logging.info("Parquet: %s", output)
    logging.info("Stata: %s", output_dta)
    logging.info("rows: %s", f"{summary['rows']:,}")
    logging.info("ACs: %s", f"{summary['acs']:,}")
    logging.info(
        "AC-months without a defined wind direction: %s",
        f"{summary['ac_months_without_wind_direction']:,}",
    )
    for zone in RICE_ZONE_DEFINITIONS:
        values = summary[zone.label]
        logging.info(
            "[%s cutoff] AC-months without rice zones: %s | share downup = 1: "
            "%.4f | mean downwind %% (with rice): %.2f | share >= 95%% "
            "downwind (with rice): %.4f",
            zone.label,
            f"{int(values['ac_months_without_rice']):,}",
            values["share_downup"],
            values["mean_down_percent_with_rice"],
            values["share_saturated_with_rice"],
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())

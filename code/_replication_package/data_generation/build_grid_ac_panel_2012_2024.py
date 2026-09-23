#!/usr/bin/env python3
"""Build the 2012-2024 monthly grid panel and assign grids to ACs.

The source Stata file is read in chunks because it contains roughly 18 million
rows. Only these source columns are retained:

    unique_grid_id, month, year, distr_id, district, province, downup_dummy

The script:

1. Keeps Bihar, Haryana, Punjab (source value Punjab_IND), and Uttar Pradesh.
2. Copies each grid's row in the source's final month to every subsequent
   month through December 2024. District assignments may vary over the
   observed panel; the final observed district is carried forward.
   ``downup_dummy`` is left null in all generated months.
3. Matches ``unique_grid_id`` to ``unq_s__`` in the grid shapefile.
4. Restricts candidate Assembly Constituencies to the grid's source state.
5. Assigns the AC with the largest grid-AC intersection area.
6. Drops grids with no positive-area same-state AC intersection.
7. Writes a Parquet panel with all non-geometry attributes from the AC
   shapefile, plus a compact assignment-audit Parquet.

Spatial intersections are calculated after projection to EPSG:7755, so overlap
areas are measured in square metres rather than square degrees.
"""

from __future__ import annotations

import argparse
import logging
import os
import re
import sys
from pathlib import Path

try:
    import duckdb
    import geopandas as gpd
    import numpy as np
    import pandas as pd
    import shapely
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "Missing dependency. Install duckdb, geopandas, pandas, pyarrow, "
        "pyogrio, and shapely before running this script."
    ) from exc


DEFAULT_MASTER = Path(
    r"C:\Users\eunic\Dropbox\sa_fires\proj_downwind\replication"
    r"\data_output\data_2012_2022_downup.dta"
)
DEFAULT_GRID_SHAPEFILE = Path(
    r"C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms\data_output"
    r"\intermediate\1-grid-generation.shp"
)
DEFAULT_AC_SHAPEFILE = Path(
    r"C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms\data_output"
    r"\intermediate\_0_2_3_ACs_right_shapefile.shp"
)
DEFAULT_OUTPUT = Path(
    r"C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms\data_output"
    r"\intermediate\data_2012_2024_grid_ac.parquet"
)

SOURCE_COLUMNS = [
    "unique_grid_id",
    "month",
    "year",
    "distr_id",
    "district",
    "province",
    "downup_dummy",
]

# Keys are normalized with normalize_state_name().
SOURCE_STATE_MAP = {
    "BIHAR": "Bihar",
    "HARYANA": "Haryana",
    "PUNJAB IND": "Punjab",
    "PUNJAB": "Punjab",
    "UTTAR PRADESH": "Uttar Pradesh",
}

AC_STATE_MAP = {
    "BIHAR": "Bihar",
    "HARYANA": "Haryana",
    "PUNJAB": "Punjab",
    "UTTAR PRADESH": "Uttar Pradesh",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--master-dta", type=Path, default=DEFAULT_MASTER)
    parser.add_argument("--grid-shapefile", type=Path, default=DEFAULT_GRID_SHAPEFILE)
    parser.add_argument("--ac-shapefile", type=Path, default=DEFAULT_AC_SHAPEFILE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--assignment-output",
        type=Path,
        default=None,
        help=(
            "Grid-to-AC audit Parquet. Defaults to OUTPUT with "
            "'_grid_ac_assignment' appended."
        ),
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=None,
        help="Disk-backed DuckDB working file. Defaults to OUTPUT.duckdb.",
    )
    parser.add_argument("--end-year", type=int, default=2024)
    parser.add_argument("--end-month", type=int, default=12)
    parser.add_argument("--chunk-size", type=int, default=500_000)
    parser.add_argument(
        "--metric-crs",
        default="EPSG:7755",
        help="Projected CRS used to compare intersection areas.",
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, min(8, os.cpu_count() or 1)),
    )
    parser.add_argument(
        "--memory-limit",
        default="8GB",
        help="DuckDB memory limit; operations may spill to disk.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace existing output, assignment, and DuckDB files.",
    )
    parser.add_argument(
        "--require-complete-ac-match",
        action="store_true",
        help="Fail if any retained grid has no positive-area same-state AC match.",
    )
    return parser.parse_args()


def normalize_state_name(value: object) -> str:
    """Normalize punctuation, underscores, and whitespace for state matching."""
    text = "" if pd.isna(value) else str(value)
    text = re.sub(r"[_\W]+", " ", text.upper(), flags=re.UNICODE)
    return " ".join(text.split())


def quote_identifier(name: str) -> str:
    """Quote a DuckDB identifier."""
    return '"' + name.replace('"', '""') + '"'


def sql_string(value: str | Path) -> str:
    """Quote a string literal for DuckDB SQL."""
    return "'" + str(value).replace("'", "''") + "'"


def output_paths(args: argparse.Namespace) -> tuple[Path, Path, Path]:
    output = args.output.resolve()
    assignment = (
        args.assignment_output.resolve()
        if args.assignment_output
        else output.with_name(output.stem + "_grid_ac_assignment.parquet")
    )
    database = (
        args.database.resolve()
        if args.database
        else output.with_suffix(".duckdb")
    )
    return output, assignment, database


def validate_paths(args: argparse.Namespace, outputs: tuple[Path, Path, Path]) -> None:
    for path in (args.master_dta, args.grid_shapefile, args.ac_shapefile):
        if not path.is_file():
            raise FileNotFoundError(path)

    for path in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            if not args.overwrite:
                raise FileExistsError(
                    f"{path} already exists. Use --overwrite to replace it."
                )
            if path.is_dir():
                raise IsADirectoryError(path)
            path.unlink()


def configure_duckdb(
    connection: duckdb.DuckDBPyConnection,
    args: argparse.Namespace,
    database: Path,
) -> None:
    temp_dir = database.with_name(database.stem + "_tmp")
    temp_dir.mkdir(parents=True, exist_ok=True)
    connection.execute(f"SET threads = {int(args.threads)}")
    connection.execute(f"SET memory_limit = {sql_string(args.memory_limit)}")
    connection.execute(f"SET temp_directory = {sql_string(temp_dir)}")
    connection.execute("SET preserve_insertion_order = false")


def import_master(
    connection: duckdb.DuckDBPyConnection,
    master_path: Path,
    chunk_size: int,
) -> None:
    """Stream selected DTA columns into a disk-backed DuckDB table."""
    logging.info(
        "Reading selected master columns in %s-row chunks", f"{chunk_size:,}"
    )
    reader = pd.read_stata(
        master_path,
        columns=SOURCE_COLUMNS,
        convert_categoricals=False,
        preserve_dtypes=True,
        iterator=True,
        chunksize=chunk_size,
    )

    created = False
    rows_read = 0
    rows_kept = 0
    for chunk_number, chunk in enumerate(reader, start=1):
        rows_read += len(chunk)
        normalized = chunk["province"].map(normalize_state_name)
        chunk["province"] = normalized.map(SOURCE_STATE_MAP)
        chunk = chunk.loc[chunk["province"].notna(), SOURCE_COLUMNS].copy()
        rows_kept += len(chunk)

        if not chunk.empty:
            connection.register("_master_chunk", chunk)
            if not created:
                connection.execute(
                    "CREATE TABLE panel_source AS SELECT * FROM _master_chunk"
                )
                created = True
            else:
                connection.execute("INSERT INTO panel_source SELECT * FROM _master_chunk")
            connection.unregister("_master_chunk")

        logging.info(
            "Master chunk %d: %s rows read; %s four-state rows retained so far",
            chunk_number,
            f"{rows_read:,}",
            f"{rows_kept:,}",
        )

    if not created:
        raise RuntimeError("No observations from the four requested states were found.")


def validate_and_expand_panel(
    connection: duckdb.DuckDBPyConnection,
    end_year: int,
    end_month: int,
) -> tuple[int, int, int]:
    """Validate the source panel and extend its final cross-section."""
    if not 1 <= end_month <= 12:
        raise ValueError("--end-month must be from 1 through 12.")

    invalid_months = connection.execute(
        "SELECT count(*) FROM panel_source WHERE month NOT BETWEEN 1 AND 12"
    ).fetchone()[0]
    if invalid_months:
        raise ValueError(f"Source has {invalid_months:,} invalid month values.")

    duplicates = connection.execute(
        """
        SELECT count(*)
        FROM (
            SELECT unique_grid_id, year, month
            FROM panel_source
            GROUP BY ALL
            HAVING count(*) <> 1
        )
        """
    ).fetchone()[0]
    if duplicates:
        raise ValueError(
            f"Source has {duplicates:,} duplicated grid-year-month keys."
        )

    source_year, source_month = connection.execute(
        """
        SELECT year, month
        FROM panel_source
        ORDER BY year DESC, month DESC
        LIMIT 1
        """
    ).fetchone()
    source_period = int(source_year) * 12 + int(source_month) - 1
    end_period = int(end_year) * 12 + int(end_month) - 1
    if end_period < source_period:
        raise ValueError(
            f"Requested end {end_year}-{end_month:02d} precedes source end "
            f"{source_year}-{source_month:02d}."
        )

    grid_count = connection.execute(
        "SELECT count(DISTINCT unique_grid_id) FROM panel_source"
    ).fetchone()[0]
    final_month_rows = connection.execute(
        """
        SELECT count(*)
        FROM panel_source
        WHERE year = ? AND month = ?
        """,
        [source_year, source_month],
    ).fetchone()[0]
    if final_month_rows != grid_count:
        raise ValueError(
            f"The final source month has {final_month_rows:,} rows but the panel "
            f"contains {grid_count:,} grids. Replication would omit "
            f"{grid_count - final_month_rows:,} grids."
        )

    # District boundaries/codes can change over time, so district changes are
    # valid and are deliberately not treated as an invariant. For the extended
    # months, each grid inherits distr_id and district from the final observed
    # month. Province is checked separately as a time-invariant grid property.
    grids_with_district_changes = connection.execute(
        """
        SELECT count(*)
        FROM (
            SELECT unique_grid_id
            FROM panel_source
            GROUP BY unique_grid_id
            HAVING count(DISTINCT (distr_id, district)) > 1
        )
        """
    ).fetchone()[0]
    logging.info(
        "%s grids change district in the observed panel; these changes are retained",
        f"{grids_with_district_changes:,}",
    )

    connection.execute(
        """
        CREATE TABLE panel_extended AS
        SELECT * FROM panel_source
        UNION ALL
        SELECT
            last.unique_grid_id,
            CAST((period.period_id % 12) + 1 AS TINYINT) AS month,
            CAST(floor(period.period_id / 12) AS SMALLINT) AS year,
            last.distr_id,
            last.district,
            last.province,
            CAST(NULL AS TINYINT) AS downup_dummy
        FROM (
            SELECT *
            FROM panel_source
            WHERE year = ? AND month = ?
        ) AS last
        CROSS JOIN range(?, ? + 1) AS period(period_id)
        """,
        [source_year, source_month, source_period + 1, end_period],
    )

    logging.info(
        "Extended %s grids from %d-%02d through %d-%02d",
        f"{grid_count:,}",
        source_year,
        source_month,
        end_year,
        end_month,
    )
    return int(source_year), int(source_month), int(grid_count)


def canonical_grid_states(
    connection: duckdb.DuckDBPyConnection,
) -> pd.DataFrame:
    """Return one stable source-state value per grid.

    Unlike district, province is required to be constant for every grid from
    the first through the final observed month.
    """
    conflicts = connection.execute(
        """
        SELECT count(*)
        FROM (
            SELECT unique_grid_id
            FROM panel_source
            GROUP BY unique_grid_id
            HAVING count(DISTINCT province) <> 1
        )
        """
    ).fetchone()[0]
    if conflicts:
        raise ValueError(f"{conflicts:,} grids change province within the source.")

    return connection.execute(
        """
        SELECT unique_grid_id, min(province) AS province
        FROM panel_source
        GROUP BY unique_grid_id
        ORDER BY unique_grid_id
        """
    ).fetch_df()


def prepare_geometries(
    grid_path: Path,
    ac_path: Path,
    grid_states: pd.DataFrame,
    metric_crs: str,
) -> tuple[gpd.GeoDataFrame, gpd.GeoDataFrame, list[str]]:
    """Read, validate, state-filter, and project grid and AC geometries."""
    logging.info("Reading grid geometry")
    grids = gpd.read_file(grid_path)
    grid_crs = grids.crs
    if "unq_s__" not in grids.columns:
        raise KeyError("Grid shapefile does not contain 'unq_s__'.")
    if grids.crs is None:
        raise ValueError("Grid shapefile has no CRS.")
    if grids["unq_s__"].duplicated().any():
        raise ValueError("Grid shapefile has duplicated 'unq_s__' values.")

    grids = grids[["unq_s__", "geometry"]].rename(
        columns={"unq_s__": "unique_grid_id"}
    )
    grids = grids.merge(
        grid_states,
        on="unique_grid_id",
        how="right",
        validate="one_to_one",
    )
    missing_grid_geometry = int(grids.geometry.isna().sum())
    if missing_grid_geometry:
        raise ValueError(
            f"{missing_grid_geometry:,} master grids are absent from the grid shapefile."
        )
    grids = gpd.GeoDataFrame(grids, geometry="geometry", crs=grid_crs)

    logging.info("Reading AC geometry and attributes")
    acs = gpd.read_file(ac_path)
    if acs.crs is None:
        raise ValueError("AC shapefile has no CRS.")
    for required in ("ac_uq_id", "STATE_UT"):
        if required not in acs.columns:
            raise KeyError(f"AC shapefile does not contain {required!r}.")
    if acs["ac_uq_id"].isna().any() or acs["ac_uq_id"].duplicated().any():
        raise ValueError("'ac_uq_id' must be nonmissing and unique.")

    ac_attribute_columns = [column for column in acs.columns if column != "geometry"]
    acs["_state_key"] = (
        acs["STATE_UT"].map(normalize_state_name).map(AC_STATE_MAP)
    )
    acs = acs.loc[acs["_state_key"].notna()].copy()

    if (~grids.geometry.is_valid).any():
        logging.warning("Repairing invalid grid geometries with make_valid()")
        grids.geometry = shapely.make_valid(grids.geometry.array)
    if (~acs.geometry.is_valid).any():
        count = int((~acs.geometry.is_valid).sum())
        logging.warning("Repairing %d invalid AC geometries with make_valid()", count)
        acs.geometry = shapely.make_valid(acs.geometry.array)

    grids = grids.to_crs(metric_crs)
    acs = acs.to_crs(metric_crs)
    return grids, acs, ac_attribute_columns


def assign_grids_to_acs(
    grids: gpd.GeoDataFrame,
    acs: gpd.GeoDataFrame,
    ac_attribute_columns: list[str],
) -> pd.DataFrame:
    """Choose the largest positive-area same-state AC overlap for each grid."""
    selected_parts: list[pd.DataFrame] = []

    for state in sorted(set(SOURCE_STATE_MAP.values())):
        left = grids.loc[
            grids["province"].eq(state), ["unique_grid_id", "province", "geometry"]
        ].reset_index(drop=True)
        right = acs.loc[
            acs["_state_key"].eq(state), ac_attribute_columns + ["geometry"]
        ].reset_index(drop=True)
        if left.empty:
            continue
        if right.empty:
            logging.warning("No AC polygons found for %s", state)
            continue

        left["_grid_row"] = np.arange(len(left), dtype=np.int64)
        right["_ac_row"] = np.arange(len(right), dtype=np.int64)
        pairs = gpd.sjoin(
            left[["_grid_row", "unique_grid_id", "geometry"]],
            right[["_ac_row", "geometry"]],
            how="inner",
            predicate="intersects",
        )
        if pairs.empty:
            logging.warning("No spatial candidates found for %s", state)
            continue

        grid_rows = pairs["_grid_row"].to_numpy(dtype=np.int64)
        ac_rows = pairs["_ac_row"].to_numpy(dtype=np.int64)
        overlaps = shapely.intersection(
            left.geometry.array.take(grid_rows),
            right.geometry.array.take(ac_rows),
        )
        overlap_area = np.asarray(shapely.area(overlaps), dtype=np.float64)

        candidates = pd.DataFrame(
            {
                "unique_grid_id": pairs["unique_grid_id"].to_numpy(),
                "_ac_row": ac_rows,
                "grid_ac_overlap_km2": overlap_area / 1_000_000,
            }
        )
        candidates = candidates.loc[candidates["grid_ac_overlap_km2"] > 0].copy()
        if candidates.empty:
            logging.warning("Only zero-area boundary touches found for %s", state)
            continue

        candidates = candidates.merge(
            right.drop(columns="geometry"),
            on="_ac_row",
            how="left",
            validate="many_to_one",
        )
        grid_areas = (
            left.set_index("unique_grid_id").geometry.area.rename("grid_area_m2")
        )
        candidates = candidates.merge(
            grid_areas,
            left_on="unique_grid_id",
            right_index=True,
            how="left",
            validate="many_to_one",
        )
        candidates["grid_ac_overlap_share"] = (
            candidates["grid_ac_overlap_km2"] * 1_000_000
            / candidates["grid_area_m2"]
        )

        # A stable AC-ID text key makes exact-area ties deterministic even if
        # the shapefile row order changes.
        candidates["_ac_tiebreak"] = candidates["ac_uq_id"].astype(str)
        candidates = candidates.sort_values(
            ["unique_grid_id", "grid_ac_overlap_km2", "_ac_tiebreak"],
            ascending=[True, False, True],
            kind="mergesort",
        )
        candidates["_rank"] = candidates.groupby("unique_grid_id").cumcount()
        candidates["_max_area"] = candidates.groupby("unique_grid_id")[
            "grid_ac_overlap_km2"
        ].transform("max")
        candidates["_is_max"] = np.isclose(
            candidates["grid_ac_overlap_km2"],
            candidates["_max_area"],
            rtol=1e-10,
            atol=1e-12,
        )
        candidates["_max_tie_count"] = candidates.groupby("unique_grid_id")[
            "_is_max"
        ].transform("sum")
        chosen = candidates.loc[candidates["_rank"].eq(0)].copy()
        chosen["grid_ac_area_tie"] = chosen["_max_tie_count"].gt(1)
        chosen["grid_area_km2"] = chosen["grid_area_m2"] / 1_000_000
        selected_parts.append(chosen)
        logging.info(
            "%s: assigned %s of %s grids",
            state,
            f"{chosen['unique_grid_id'].nunique():,}",
            f"{left['unique_grid_id'].nunique():,}",
        )

    if not selected_parts:
        raise RuntimeError("No grid-to-AC assignments were produced.")

    assignment = pd.concat(selected_parts, ignore_index=True)
    keep = [
        "unique_grid_id",
        *ac_attribute_columns,
        "grid_area_km2",
        "grid_ac_overlap_km2",
        "grid_ac_overlap_share",
        "grid_ac_area_tie",
    ]
    assignment = assignment[keep].sort_values("unique_grid_id").reset_index(drop=True)
    if assignment["unique_grid_id"].duplicated().any():
        raise RuntimeError("Internal error: assignment has duplicate grid IDs.")
    return assignment


def export_outputs(
    connection: duckdb.DuckDBPyConnection,
    assignment: pd.DataFrame,
    ac_attribute_columns: list[str],
    output: Path,
    assignment_output: Path,
    require_complete_match: bool,
) -> tuple[int, int]:
    """Write the compact assignment audit and final long Parquet.

    DuckDB treats identifiers case-insensitively. If an AC attribute differs
    from a master field only by case (notably AC ``DISTRICT`` versus master
    ``district``), the AC output name is prefixed with ``ac_`` so neither
    variable is lost.
    """
    assignment.to_parquet(
        assignment_output,
        index=False,
        engine="pyarrow",
        compression="zstd",
    )
    connection.execute(
        """
        CREATE TABLE grid_ac_assignment AS
        SELECT *
        FROM read_parquet(?)
        """,
        [str(assignment_output)],
    )

    total_grids = connection.execute(
        "SELECT count(DISTINCT unique_grid_id) FROM panel_extended"
    ).fetchone()[0]
    assigned_grids = connection.execute(
        "SELECT count(*) FROM grid_ac_assignment"
    ).fetchone()[0]
    unmatched = int(total_grids - assigned_grids)
    if unmatched:
        message = (
            f"{unmatched:,} of {total_grids:,} retained grids have no "
            "positive-area same-state AC match."
        )
        if require_complete_match:
            raise RuntimeError(message)
        logging.warning(message + " They will be excluded from the final panel.")

    used_names = {column.casefold() for column in SOURCE_COLUMNS}
    ac_select_parts: list[str] = []
    for column in ac_attribute_columns:
        output_name = column
        if output_name.casefold() in used_names:
            output_name = f"ac_{column}"
        while output_name.casefold() in used_names:
            output_name = f"ac_{output_name}"
        used_names.add(output_name.casefold())
        ac_select_parts.append(
            f"a.{quote_identifier(column)} AS {quote_identifier(output_name)}"
        )
    ac_select = ",\n            ".join(ac_select_parts)
    query = f"""
        SELECT
            p.unique_grid_id,
            p.month,
            p.year,
            p.distr_id,
            p.district,
            p.province,
            p.downup_dummy,
            {ac_select}
        FROM panel_extended AS p
        INNER JOIN grid_ac_assignment AS a USING (unique_grid_id)
        ORDER BY p.unique_grid_id, p.year, p.month
    """
    connection.execute(
        f"""
        COPY ({query})
        TO {sql_string(output)}
        (FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 250000)
        """
    )

    output_rows = connection.execute(f"SELECT count(*) FROM ({query})").fetchone()[0]
    duplicate_rows = connection.execute(
        f"""
        SELECT count(*)
        FROM (
            SELECT unique_grid_id, year, month
            FROM ({query})
            GROUP BY ALL
            HAVING count(*) <> 1
        )
        """
    ).fetchone()[0]
    if duplicate_rows:
        raise RuntimeError(
            f"Final output has {duplicate_rows:,} duplicated grid-month keys."
        )
    return int(output_rows), unmatched


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    output, assignment_output, database = output_paths(args)
    validate_paths(args, (output, assignment_output, database))

    connection = duckdb.connect(str(database))
    try:
        configure_duckdb(connection, args, database)
        import_master(connection, args.master_dta.resolve(), args.chunk_size)
        source_year, source_month, grid_count = validate_and_expand_panel(
            connection, args.end_year, args.end_month
        )
        grid_states = canonical_grid_states(connection)
        grids, acs, ac_attribute_columns = prepare_geometries(
            args.grid_shapefile.resolve(),
            args.ac_shapefile.resolve(),
            grid_states,
            args.metric_crs,
        )
        assignment = assign_grids_to_acs(grids, acs, ac_attribute_columns)
        output_rows, unmatched = export_outputs(
            connection,
            assignment,
            ac_attribute_columns,
            output,
            assignment_output,
            args.require_complete_ac_match,
        )
        connection.execute("CHECKPOINT")
    finally:
        connection.close()

    ties = int(assignment["grid_ac_area_tie"].sum())
    logging.info("Completed successfully")
    logging.info("Source final month: %d-%02d", source_year, source_month)
    logging.info("Retained grids: %s", f"{grid_count:,}")
    logging.info("Final panel rows: %s", f"{output_rows:,}")
    logging.info("Unmatched grids: %s", f"{unmatched:,}")
    logging.info("Maximum-area ties resolved by ac_uq_id: %s", f"{ties:,}")
    logging.info("Panel Parquet: %s", output)
    logging.info("Assignment audit: %s", assignment_output)
    logging.info("DuckDB database: %s", database)
    return 0


if __name__ == "__main__":
    sys.exit(main())

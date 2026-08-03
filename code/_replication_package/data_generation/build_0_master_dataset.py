#!/usr/bin/env python3
"""Build the 2012-2024 grid-month master dataset with DuckDB.

The population-stage Parquet is the row-preserving base. Area treatment, the
13 km placebo measures, protests, elections, fires, and AC-level rice
information are left-joined without changing that key. Every merge reports
left_only, right_only, and both counts. Both Parquet and CSV outputs are
written.
"""

from __future__ import annotations

import argparse
import logging
import os
import shutil
import sys
from dataclasses import dataclass
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
    if LOCAL_INTERMEDIATE.exists():
        return LOCAL_INTERMEDIATE
    return CLUSTER_INTERMEDIATE


def parse_args() -> argparse.Namespace:
    intermediate = default_intermediate()
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--intermediate", type=Path, default=intermediate)
    parser.add_argument("--area", type=Path, default=None)
    parser.add_argument("--population", type=Path, default=None)
    parser.add_argument("--placebo-13km", type=Path, default=None)
    parser.add_argument("--protests", type=Path, default=None)
    parser.add_argument("--elections", type=Path, default=None)
    parser.add_argument("--fire", type=Path, default=None)
    parser.add_argument("--rice", type=Path, default=None)
    parser.add_argument("--output-parquet", type=Path, default=None)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--database", type=Path, default=None)
    parser.add_argument("--temp-directory", type=Path, default=None)
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument("--memory-limit", default="90GB")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument(
        "--skip-csv",
        action="store_true",
        help="Write only the Parquet output.",
    )
    return parser.parse_args()


def resolve_paths(args: argparse.Namespace) -> dict[str, Path]:
    intermediate = args.intermediate.resolve()
    output_parquet = (
        args.output_parquet.resolve()
        if args.output_parquet
        else intermediate / "0_master_dataset.parquet"
    )
    return {
        "intermediate": intermediate,
        "area": (
            args.area.resolve()
            if args.area
            else intermediate / "data_2012_2024_grid_ac_downup.parquet"
        ),
        "population": (
            args.population.resolve()
            if args.population
            else intermediate / "data_2012_2024_grid_ac_downup_pop.parquet"
        ),
        "placebo_13km": (
            args.placebo_13km.resolve()
            if args.placebo_13km
            else intermediate / "data_2012_2024_grid_ac_13kmpl.parquet"
        ),
        "protests": (
            args.protests.resolve()
            if args.protests
            else intermediate / "8_grids_ac_pr_5km.csv"
        ),
        "elections": (
            args.elections.resolve()
            if args.elections
            else intermediate / "panel_data_election_year.parquet"
        ),
        "fire": (
            args.fire.resolve()
            if args.fire
            else intermediate / "_3_fire_grid.csv"
        ),
        "rice": (
            args.rice.resolve()
            if args.rice
            else intermediate / "rice_info_ac_lvl.dta"
        ),
        "output_parquet": output_parquet,
        "output_csv": (
            args.output_csv.resolve()
            if args.output_csv
            else intermediate / "0_master_dataset.csv"
        ),
        "database": (
            args.database.resolve()
            if args.database
            else intermediate / "0_master_dataset.duckdb"
        ),
        "temp_directory": (
            args.temp_directory.resolve()
            if args.temp_directory
            else intermediate / "0_master_dataset_duckdb_tmp"
        ),
    }


def sql_string(value: str | Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def quote_identifier(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def remove_exact_path(path: Path, allowed_parent: Path) -> None:
    resolved = path.resolve()
    parent = allowed_parent.resolve()
    if resolved.parent != parent:
        raise ValueError(f"Refusing to remove path outside {parent}: {resolved}")
    if resolved.is_dir():
        shutil.rmtree(resolved)
    elif resolved.exists():
        resolved.unlink()


def require_files(paths: dict[str, Path]) -> None:
    for name in (
        "area",
        "population",
        "placebo_13km",
        "protests",
        "elections",
        "fire",
        "rice",
    ):
        if not paths[name].is_file():
            raise FileNotFoundError(f"Missing {name} input: {paths[name]}")


def normalize_protests(path: Path) -> pd.DataFrame:
    frame = pd.read_csv(path)
    if "unique_small_grid_id" not in frame.columns:
        if "unq_s__" not in frame.columns:
            raise KeyError(
                "The protest file needs unique_small_grid_id or unq_s__."
            )
        frame = frame.rename(columns={"unq_s__": "unique_small_grid_id"})
    required = {
        "unique_small_grid_id",
        "protest_id",
        "protest_place",
        "yr_pr_5km",
        "mt_pr_5km",
    }
    missing = sorted(required.difference(frame.columns))
    if missing:
        raise KeyError(f"Missing protest columns: {missing}")
    frame = frame[list(required)].copy()
    if frame["unique_small_grid_id"].isna().any():
        raise ValueError("The protest grid identifier contains missing values.")
    if frame["unique_small_grid_id"].duplicated().any():
        raise ValueError("The protest file has duplicate grid identifiers.")
    frame["unique_small_grid_id"] = frame["unique_small_grid_id"].astype("int64")
    return frame


def normalize_elections(path: Path) -> pd.DataFrame:
    suffix = path.suffix.casefold()
    if suffix == ".parquet":
        frame = pd.read_parquet(path)
    elif suffix == ".dta":
        logging.warning(
            "Reading legacy Stata election input; prefer the Parquet file: %s",
            path,
        )
        frame = pd.read_stata(path, convert_categoricals=False)
    else:
        raise ValueError(
            "The election input must be a .parquet file "
            f"(or a legacy .dta override), not {path.suffix!r}."
        )
    required = {"ac_uq_id", "year", "month", "yeargov"}
    missing = sorted(required.difference(frame.columns))
    if missing:
        raise KeyError(f"Missing election columns: {missing}")
    if frame.duplicated(["ac_uq_id", "year", "month"]).any():
        raise ValueError(
            "The election panel is not unique by ac_uq_id x year x month."
        )
    if frame["yeargov"].isna().any():
        raise ValueError("The election panel contains missing yeargov values.")

    # Convert blank Stata strings to genuine missing values. The upstream
    # panel has 1,440 politician-unmatched rows whose geographic fields were
    # populated with the first record's ARARIA/BIHAR values. Recover only the
    # fields that are empirically invariant within AC among matched records.
    string_columns = frame.select_dtypes(include=["object", "string"]).columns
    for column in string_columns:
        frame[column] = frame[column].replace(r"^\s*$", pd.NA, regex=True)

    ac_constant_columns = [
        "state",
        "acpost08ID",
        "ASSEMBLY",
        "ASSEMBLY_1",
        "DISTRICT",
        "PARLIAMENT",
        "P_NAME",
        "STATE_UT",
        "state_clean",
        "STATE_UT_clean",
    ]
    matched = frame.loc[frame["unique_id"].notna()]
    for column in ac_constant_columns:
        counts = matched.groupby("ac_uq_id")[column].nunique(dropna=True)
        changing = counts[counts > 1]
        if not changing.empty:
            raise ValueError(
                f"Election column {column} is not AC-constant for "
                f"{len(changing)} ACs."
            )
        lookup = (
            matched.dropna(subset=[column])
            .drop_duplicates(["ac_uq_id", column])
            .set_index("ac_uq_id")[column]
        )
        if lookup.index.duplicated().any():
            raise ValueError(f"Ambiguous AC lookup for election column {column}.")
        frame[column] = frame["ac_uq_id"].map(lookup)
        if frame[column].isna().any():
            raise ValueError(
                f"Cannot repair AC-constant election column {column}."
            )
    return frame


def normalize_rice(path: Path) -> tuple[pd.DataFrame, float]:
    frame = pd.read_stata(path, convert_categoricals=False)
    if "ac_uq_id" not in frame.columns:
        raise KeyError("The rice file does not contain ac_uq_id.")
    if frame["ac_uq_id"].isna().any() or frame["ac_uq_id"].duplicated().any():
        raise ValueError("The rice file must be unique and nonmissing by AC.")
    required = {
        "rice_area_ha_aclvl",
        "rice_harvarea_ha_aclvl",
        "rice_prod_mt_aclvl",
        "rice_area_share_aclvl",
        "rice_harvarea_share_aclvl",
        "rice_area_aclvl_ahigh",
        "rice_harvarea_aclvl_ahigh",
    }
    missing = sorted(required.difference(frame.columns))
    if missing:
        raise KeyError(f"Missing rice columns: {missing}")
    median = float(frame["rice_prod_mt_aclvl"].median(skipna=True))
    frame["rice_prod_aclvl_ahigh"] = (
        frame["rice_prod_mt_aclvl"].fillna(0).gt(median).astype("int8")
    )
    keep = ["ac_uq_id", *sorted(required), "rice_prod_aclvl_ahigh"]
    return frame[keep].copy(), median


def election_select_list(
    election_columns: list[str], existing_columns: set[str]
) -> str:
    selections: list[str] = []
    used = {column.casefold() for column in existing_columns}
    for column in election_columns:
        if column in {"ac_uq_id", "year", "month", "yeargov"}:
            continue
        output = "election_index" if column == "index" else column
        if output.casefold() in used:
            output = f"election_{output}"
        suffix = 2
        candidate = output
        while candidate.casefold() in used:
            candidate = f"{output}_{suffix}"
            suffix += 1
        output = candidate
        used.add(output.casefold())
        selections.append(
            f"e.{quote_identifier(column)} AS {quote_identifier(output)}"
        )
    return ",\n            ".join(selections)


def scalar(connection: duckdb.DuckDBPyConnection, query: str) -> object:
    return connection.execute(query).fetchone()[0]


@dataclass(frozen=True)
class MergeDiagnostics:
    """Full-outer key-overlap counts corresponding to pandas/Stata merge tags."""

    left_only: int
    right_only: int
    both: int


def check_merge(
    connection: duckdb.DuckDBPyConnection,
    *,
    name: str,
    left_query: str,
    right_query: str,
    using_columns: tuple[str, ...],
    require_all_left: bool = False,
    require_all_right: bool = False,
) -> MergeDiagnostics:
    """Log left_only/right_only/both counts and enforce requested coverage."""

    if not using_columns:
        raise ValueError("Merge diagnostics require at least one key column.")
    using_sql = ", ".join(quote_identifier(column) for column in using_columns)
    result = MergeDiagnostics(
        *map(
            int,
            connection.execute(
                f"""
                WITH
                left_source AS ({left_query}),
                right_source AS ({right_query}),
                left_marked AS (
                    SELECT *, TRUE AS __merge_left
                    FROM left_source
                ),
                right_marked AS (
                    SELECT *, TRUE AS __merge_right
                    FROM right_source
                )
                SELECT
                    count_if(
                        __merge_left IS NOT NULL
                        AND __merge_right IS NULL
                    ),
                    count_if(
                        __merge_left IS NULL
                        AND __merge_right IS NOT NULL
                    ),
                    count_if(
                        __merge_left IS NOT NULL
                        AND __merge_right IS NOT NULL
                    )
                FROM left_marked
                FULL OUTER JOIN right_marked USING ({using_sql})
                """
            ).fetchone(),
        )
    )
    logging.info(
        "Merge %s | left_only=%s | right_only=%s | both=%s",
        name,
        f"{result.left_only:,}",
        f"{result.right_only:,}",
        f"{result.both:,}",
    )
    failures: list[str] = []
    if require_all_left and result.left_only:
        failures.append(f"left_only={result.left_only:,}")
    if require_all_right and result.right_only:
        failures.append(f"right_only={result.right_only:,}")
    if failures:
        raise ValueError(f"Merge {name} failed coverage checks: {', '.join(failures)}.")
    return result


def main() -> int:
    args = parse_args()
    paths = resolve_paths(args)
    require_files(paths)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    output_parent = paths["output_parquet"].parent
    output_parent.mkdir(parents=True, exist_ok=True)
    if paths["output_csv"].parent != output_parent:
        paths["output_csv"].parent.mkdir(parents=True, exist_ok=True)

    outputs = [paths["output_parquet"]]
    if not args.skip_csv:
        outputs.append(paths["output_csv"])
    existing = [path for path in outputs if path.exists()]
    if existing and not args.overwrite:
        raise FileExistsError(
            "Output exists; pass --overwrite: "
            + ", ".join(map(str, existing))
        )

    parquet_temp = paths["output_parquet"].with_name(
        paths["output_parquet"].name + ".tmp"
    )
    csv_temp = paths["output_csv"].with_name(paths["output_csv"].name + ".tmp")
    work_paths = [
        parquet_temp,
        csv_temp,
        paths["database"],
        paths["temp_directory"],
    ]
    for path in work_paths:
        if path.exists():
            remove_exact_path(path, path.parent)

    paths["temp_directory"].mkdir(parents=True, exist_ok=True)
    connection = duckdb.connect(str(paths["database"]))
    try:
        connection.execute(f"SET threads = {max(1, args.threads)}")
        connection.execute(
            f"SET memory_limit = {sql_string(args.memory_limit)}"
        )
        connection.execute(
            f"SET temp_directory = {sql_string(paths['temp_directory'])}"
        )
        connection.execute("SET preserve_insertion_order = false")

        logging.info("Loading protest, election, rice, and fire inputs")
        protests = normalize_protests(paths["protests"])
        elections = normalize_elections(paths["elections"])
        rice, rice_production_median = normalize_rice(paths["rice"])
        connection.register("_protests_frame", protests)
        connection.register("_elections_frame", elections)
        connection.register("_rice_frame", rice)
        connection.execute(
            "CREATE TEMP TABLE protest_grid AS SELECT * FROM _protests_frame"
        )
        connection.execute(
            "CREATE TEMP TABLE election_panel AS SELECT * FROM _elections_frame"
        )
        connection.execute(
            "CREATE TEMP TABLE rice_ac AS SELECT * FROM _rice_frame"
        )
        connection.execute(
            f"""
            CREATE TEMP TABLE fire_grid AS
            SELECT
                unique_small_grid_id::BIGINT AS unique_small_grid_id,
                year::SMALLINT AS year,
                month::TINYINT AS month,
                "count"::BIGINT AS "count",
                mean_brightness::DOUBLE AS mean_brightness
            FROM read_csv_auto(
                {sql_string(paths["fire"])},
                header = true,
                sample_size = -1
            )
            """
        )
        connection.unregister("_protests_frame")
        connection.unregister("_elections_frame")
        connection.unregister("_rice_frame")
        logging.info(
            "Rice-production median used for rice_prod_aclvl_ahigh: %.12g",
            rice_production_median,
        )

        area = sql_string(paths["area"])
        population = sql_string(paths["population"])
        placebo_13km = sql_string(paths["placebo_13km"])

        logging.info("Validating large-panel keys")
        area_rows, area_keys = connection.execute(
            f"""
            SELECT count(*), count(DISTINCT (
                unique_small_grid_id, year, month
            ))
            FROM read_parquet({area})
            """
        ).fetchone()
        population_rows, population_keys = connection.execute(
            f"""
            SELECT count(*), count(DISTINCT (
                unique_small_grid_id, year, month
            ))
            FROM read_parquet({population})
            """
        ).fetchone()
        placebo_rows, placebo_keys = connection.execute(
            f"""
            SELECT count(*), count(DISTINCT (
                unique_small_grid_id, year, month
            ))
            FROM read_parquet({placebo_13km})
            """
        ).fetchone()
        if area_rows != area_keys:
            raise ValueError("The area panel key is not unique.")
        if population_rows != population_keys:
            raise ValueError("The population panel key is not unique.")
        if placebo_rows != placebo_keys:
            raise ValueError("The 13 km placebo panel key is not unique.")

        population_area_merge = check_merge(
            connection,
            name="population base x area panel [grid-month]",
            left_query=f"""
                SELECT unique_small_grid_id, year, month
                FROM read_parquet({population})
            """,
            right_query=f"""
                SELECT unique_small_grid_id, year, month
                FROM read_parquet({area})
            """,
            using_columns=("unique_small_grid_id", "year", "month"),
            require_all_left=True,
            require_all_right=True,
        )
        if population_area_merge.both != population_rows:
            raise ValueError("The area merge does not preserve the population base.")

        population_placebo_merge = check_merge(
            connection,
            name="population base x 13 km placebo [grid-AC-month]",
            left_query=f"""
                SELECT unique_small_grid_id, ac_uq_id, year, month
                FROM read_parquet({population})
            """,
            right_query=f"""
                SELECT unique_small_grid_id, ac_uq_id, year, month
                FROM read_parquet({placebo_13km})
            """,
            using_columns=("unique_small_grid_id", "ac_uq_id", "year", "month"),
            require_all_left=True,
            require_all_right=True,
        )
        if population_placebo_merge.both != population_rows:
            raise ValueError(
                "The 13 km merge does not preserve the population base."
            )
        fire_rows, fire_keys = connection.execute(
            """
            SELECT
                count(*),
                count(DISTINCT (unique_small_grid_id, year, month))
            FROM fire_grid
            """
        ).fetchone()
        if fire_rows != fire_keys:
            raise ValueError("The fire panel key is not unique.")
        missing_fire_brightness = scalar(
            connection,
            "SELECT count_if(mean_brightness IS NULL) FROM fire_grid",
        )
        if missing_fire_brightness:
            raise ValueError(
                "The fire input contains "
                f"{missing_fire_brightness:,} rows with missing mean_brightness."
            )

        check_merge(
            connection,
            name="population base x fire panel [grid-month]",
            left_query=f"""
                SELECT unique_small_grid_id, year, month
                FROM read_parquet({population})
            """,
            right_query="""
                SELECT unique_small_grid_id, year, month
                FROM fire_grid
            """,
            using_columns=("unique_small_grid_id", "year", "month"),
        )

        protest_merge = check_merge(
            connection,
            name="population grids x protest grids [grid]",
            left_query=f"""
                SELECT DISTINCT unique_small_grid_id
                FROM read_parquet({population})
            """,
            right_query="SELECT unique_small_grid_id FROM protest_grid",
            using_columns=("unique_small_grid_id",),
        )
        if protest_merge.right_only:
            logging.warning(
                "Protest grids outside the population base: %s",
                f"{protest_merge.right_only:,}",
            )

        connection.execute(
            f"""
            CREATE TEMP TABLE grid_lookup AS
            WITH grid_ac AS (
                SELECT
                    unique_small_grid_id,
                    min(ac_uq_id) AS ac_uq_id,
                    count(DISTINCT ac_uq_id) AS ac_count
                FROM read_parquet({population})
                GROUP BY unique_small_grid_id
            ),
            assigned AS (
                SELECT
                    g.unique_small_grid_id,
                    g.ac_uq_id,
                    p.protest_id,
                    coalesce(p.protest_place, 0) AS protest_place,
                    p.yr_pr_5km,
                    p.mt_pr_5km
                FROM grid_ac AS g
                LEFT JOIN protest_grid AS p USING (unique_small_grid_id)
                WHERE g.ac_count = 1
            )
            SELECT
                *,
                dense_rank() OVER (
                    ORDER BY protest_place, ac_uq_id
                )::INTEGER AS ac_area_tr
            FROM assigned
            """
        )
        check_merge(
            connection,
            name="population base x grid/protest lookup [grid-AC]",
            left_query=f"""
                SELECT DISTINCT unique_small_grid_id, ac_uq_id
                FROM read_parquet({population})
            """,
            right_query="SELECT unique_small_grid_id, ac_uq_id FROM grid_lookup",
            using_columns=("unique_small_grid_id", "ac_uq_id"),
            require_all_left=True,
            require_all_right=True,
        )

        check_merge(
            connection,
            name="population base x election panel [AC-month]",
            left_query=f"""
                SELECT ac_uq_id, year, month
                FROM read_parquet({population})
            """,
            right_query="SELECT ac_uq_id, year, month FROM election_panel",
            using_columns=("ac_uq_id", "year", "month"),
            require_all_left=True,
        )

        rice_merge = check_merge(
            connection,
            name="population ACs x rice panel [AC]",
            left_query=f"""
                SELECT DISTINCT ac_uq_id
                FROM read_parquet({population})
            """,
            right_query="SELECT ac_uq_id FROM rice_ac",
            using_columns=("ac_uq_id",),
        )
        if rice_merge.left_only:
            logging.warning(
                "Rice data absent for %s panel ACs; rice columns will be zero.",
                f"{rice_merge.left_only:,}",
            )

        mismatch_rows = scalar(
            connection,
            f"""
            SELECT count(*)
            FROM read_parquet({area}) AS a
            JOIN read_parquet({population}) AS p
              USING (unique_small_grid_id, year, month)
            WHERE
                a.province IS DISTINCT FROM p.province
                OR a.district IS DISTINCT FROM p.district
                OR a.wind_speed_av_cellid_month
                   IS DISTINCT FROM p.wind_speed_av_cellid_month
                OR a.wind_direction_av_cellid_month
                   IS DISTINCT FROM p.wind_direction_av_cellid_month
                OR a.rollav_wind_speed_cellid_month
                   IS DISTINCT FROM p.rollav_wind_speed_cellid_month
                OR a.rollav_wind_direction_cellid_month
                   IS DISTINCT FROM p.rollav_wind_direction_cellid_month
                OR a.downup_dummy IS DISTINCT FROM p.downup_dummy
                OR a.downwind_pop IS DISTINCT FROM p.downwind_pop
                OR a.upwind_pop IS DISTINCT FROM p.upwind_pop
                OR a.downup_ac_pop IS DISTINCT FROM p.downup_ac_pop
            """,
        )
        if mismatch_rows:
            raise ValueError(
                "Area/population shared fields disagree on "
                f"{mismatch_rows:,} rows."
            )

        placebo_mismatch_rows = scalar(
            connection,
            f"""
            SELECT count(*)
            FROM read_parquet({population}) AS p
            JOIN read_parquet({placebo_13km}) AS q
              USING (unique_small_grid_id, year, month)
            WHERE
                p.ac_uq_id IS DISTINCT FROM q.ac_uq_id
                OR p.calculation_wind_direction
                   IS DISTINCT FROM q.calculation_wind_direction
            """,
        )
        if placebo_mismatch_rows:
            raise ValueError(
                "The 13 km panel disagrees with the population-stage grid, "
                f"AC, or wind assignment on {placebo_mismatch_rows:,} rows."
            )

        sd_value = scalar(
            connection,
            f"""
            SELECT stddev_samp(downwind_pop - upwind_pop)
            FROM read_parquet({population})
            """,
        )
        logging.info("downup_diff_pop sample SD: %.12g", sd_value)

        base_columns = {
            row[0]
            for row in connection.execute(
                f"DESCRIBE SELECT * FROM read_parquet({population})"
            ).fetchall()
        }
        additional_columns = {
            "ac_uq_id",
            "calculation_wind_direction",
            "downwind_pop_ac_nosmall",
            "upwind_pop_ac_nosmall",
            "total_pop",
            "downup_diff_pop",
            "downup_1sd_pop",
            "down_percent_pop",
            "downup_diff_percent_pop",
            "downup_ac",
            "downup_ac_area",
            "downwind_area",
            "upwind_area",
            "monthyear",
            "protest_id",
            "protest_place",
            "yr_pr_5km",
            "mt_pr_5km",
            "ac_area_tr",
            "protest5km",
            "count",
            "mean_brightness",
            "av_wind_speed",
            "wind_direction",
            "rice_area_ha_aclvl",
            "rice_harvarea_ha_aclvl",
            "rice_prod_mt_aclvl",
            "rice_area_share_aclvl",
            "rice_harvarea_share_aclvl",
            "rice_area_aclvl_ahigh",
            "rice_harvarea_aclvl_ahigh",
            "rice_prod_aclvl_ahigh",
            "yeargov",
            "downwind_area_13kmpl",
            "upwind_area_13kmpl",
            "downwind_pop_13kmpl",
            "upwind_pop_13kmpl",
            "downup_13kmpl",
        }
        election_fields = election_select_list(
            list(elections.columns), base_columns | additional_columns
        )
        election_suffix = f",\n            {election_fields}" if election_fields else ""

        sd_literal = repr(float(sd_value))
        master_query = f"""
        WITH joined AS (
            SELECT
                p.*,
                a.downup_ac_area,
                a.downwind_area,
                a.upwind_area,
                q.downwind_area_13kmpl,
                q.upwind_area_13kmpl,
                q.downwind_pop_13kmpl,
                q.upwind_pop_13kmpl,
                q.downup_13kmpl,
                p.downwind_pop AS downwind_pop_ac_nosmall,
                p.upwind_pop AS upwind_pop_ac_nosmall,
                p.downwind_pop + p.upwind_pop AS total_pop,
                p.downwind_pop - p.upwind_pop AS downup_diff_pop,
                a.downup_ac_area AS downup_ac,
                (p.year::INTEGER * 12 + p.month::INTEGER) AS monthyear,
                g.protest_id,
                g.protest_place,
                g.yr_pr_5km,
                g.mt_pr_5km,
                g.ac_area_tr,
                coalesce(f."count", 0)::BIGINT AS "count",
                f.mean_brightness,
                p.rollav_wind_speed_cellid_month AS av_wind_speed,
                p.wind_direction_av_cellid_month AS wind_direction,
                coalesce(r.rice_area_ha_aclvl, 0)::DOUBLE
                    AS rice_area_ha_aclvl,
                coalesce(r.rice_harvarea_ha_aclvl, 0)::DOUBLE
                    AS rice_harvarea_ha_aclvl,
                coalesce(r.rice_prod_mt_aclvl, 0)::DOUBLE
                    AS rice_prod_mt_aclvl,
                coalesce(r.rice_area_share_aclvl, 0)::DOUBLE
                    AS rice_area_share_aclvl,
                coalesce(r.rice_harvarea_share_aclvl, 0)::DOUBLE
                    AS rice_harvarea_share_aclvl,
                coalesce(r.rice_area_aclvl_ahigh, 0)::TINYINT
                    AS rice_area_aclvl_ahigh,
                coalesce(r.rice_harvarea_aclvl_ahigh, 0)::TINYINT
                    AS rice_harvarea_aclvl_ahigh,
                coalesce(r.rice_prod_aclvl_ahigh, 0)::TINYINT
                    AS rice_prod_aclvl_ahigh,
                e.yeargov AS yeargov,
                CASE
                    WHEN g.yr_pr_5km IS NULL OR g.mt_pr_5km IS NULL THEN 0
                    WHEN (p.year::INTEGER * 12 + p.month::INTEGER)
                         >= (g.yr_pr_5km::INTEGER * 12
                             + g.mt_pr_5km::INTEGER) THEN 1
                    ELSE 0
                END::TINYINT AS protest5km
                {election_suffix}
            FROM read_parquet({population}) AS p
            LEFT JOIN read_parquet({area}) AS a
              ON p.unique_small_grid_id = a.unique_small_grid_id
             AND p.year = a.year
             AND p.month = a.month
            LEFT JOIN read_parquet({placebo_13km}) AS q
              ON p.unique_small_grid_id = q.unique_small_grid_id
             AND p.year = q.year
             AND p.month = q.month
             AND p.ac_uq_id = q.ac_uq_id
            LEFT JOIN grid_lookup AS g
              ON p.unique_small_grid_id = g.unique_small_grid_id
             AND p.ac_uq_id = g.ac_uq_id
            LEFT JOIN election_panel AS e
              ON p.ac_uq_id = e.ac_uq_id
             AND p.year = e.year
             AND p.month = e.month
            LEFT JOIN fire_grid AS f
              ON p.unique_small_grid_id = f.unique_small_grid_id
             AND p.year = f.year
             AND p.month = f.month
            LEFT JOIN rice_ac AS r
              ON p.ac_uq_id = r.ac_uq_id
        )
        SELECT
            *,
            CASE
                WHEN downup_diff_pop IS NULL THEN NULL
                WHEN downup_diff_pop > {sd_literal} THEN 1
                ELSE 0
            END::TINYINT AS downup_1sd_pop,
            (downwind_pop_ac_nosmall * 100.0)
                / nullif(total_pop, 0) AS down_percent_pop,
            (downup_diff_pop * 100.0)
                / nullif(total_pop, 0) AS downup_diff_percent_pop
        FROM joined
        """

        logging.info("Writing master Parquet")
        connection.execute(
            f"""
            COPY ({master_query})
            TO {sql_string(parquet_temp)}
            (FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 262144)
            """
        )
        os.replace(parquet_temp, paths["output_parquet"])

        (
            output_rows,
            output_keys,
            missing_ac,
            missing_election,
            missing_yeargov,
            missing_count,
            missing_brightness_with_fire,
            no_fire_rows,
            missing_rice,
            missing_placebo,
            missing_wind,
            incomplete_placebo,
        ) = connection.execute(
                f"""
                SELECT
                    count(*),
                    count(DISTINCT (
                        unique_small_grid_id, year, month
                    )),
                    count_if(ac_uq_id IS NULL),
                    count_if(election_year IS NULL),
                    count_if(yeargov IS NULL),
                    count_if("count" IS NULL),
                    count_if("count" > 0 AND mean_brightness IS NULL),
                    count_if("count" = 0 AND mean_brightness IS NULL),
                    count_if(
                        rice_area_ha_aclvl IS NULL
                        OR rice_harvarea_ha_aclvl IS NULL
                        OR rice_prod_mt_aclvl IS NULL
                        OR rice_area_share_aclvl IS NULL
                        OR rice_harvarea_share_aclvl IS NULL
                        OR rice_area_aclvl_ahigh IS NULL
                        OR rice_harvarea_aclvl_ahigh IS NULL
                        OR rice_prod_aclvl_ahigh IS NULL
                    ),
                    count_if(downup_13kmpl IS NULL),
                    count_if(calculation_wind_direction IS NULL),
                    count_if(
                        calculation_wind_direction IS NOT NULL
                        AND (
                            downwind_area_13kmpl IS NULL
                            OR upwind_area_13kmpl IS NULL
                            OR downwind_pop_13kmpl IS NULL
                            OR upwind_pop_13kmpl IS NULL
                            OR downup_13kmpl IS NULL
                        )
                    )
                FROM read_parquet({sql_string(paths['output_parquet'])})
                """
            ).fetchone()
        if output_rows != population_rows or output_keys != population_rows:
            raise ValueError("The output does not preserve the base panel key.")
        if missing_ac:
            raise ValueError("The output contains missing ac_uq_id values.")
        if missing_yeargov:
            raise ValueError(
                f"The output contains {missing_yeargov:,} missing yeargov values."
            )
        if missing_count or missing_rice:
            raise ValueError("Fire counts or rice fields remain missing.")
        if missing_brightness_with_fire:
            raise ValueError(
                "mean_brightness is missing for "
                f"{missing_brightness_with_fire:,} rows with positive fire counts."
            )
        if missing_placebo != missing_wind or incomplete_placebo:
            raise ValueError(
                "The 13 km measures are incomplete beyond missing-wind rows."
            )
        logging.info(
            "Rows without election_year (field may legitimately be missing): %s",
            f"{missing_election:,}",
        )
        logging.info(
            "Rows with no fire record (count=0, mean_brightness missing): %s",
            f"{no_fire_rows:,}",
        )

        if not args.skip_csv:
            logging.info("Writing master CSV")
            connection.execute(
                f"""
                COPY (
                    SELECT *
                    FROM read_parquet({sql_string(paths['output_parquet'])})
                )
                TO {sql_string(csv_temp)}
                (FORMAT CSV, HEADER TRUE)
                """
            )
            os.replace(csv_temp, paths["output_csv"])

        summary = connection.execute(
            f"""
            SELECT
                count(*) AS rows,
                count(DISTINCT unique_small_grid_id) AS grids,
                count(DISTINCT ac_uq_id) AS acs,
                count_if(protest5km = 1) AS treated_rows,
                count_if(downup_1sd_pop = 1) AS one_sd_rows,
                count_if(total_pop = 0) AS zero_population_rows
            FROM read_parquet({sql_string(paths['output_parquet'])})
            """
        ).fetchone()
        logging.info("Completed master dataset")
        logging.info("rows: %s", f"{summary[0]:,}")
        logging.info("grids: %s", f"{summary[1]:,}")
        logging.info("ACs: %s", f"{summary[2]:,}")
        logging.info("protest5km=1 rows: %s", f"{summary[3]:,}")
        logging.info("downup_1sd_pop=1 rows: %s", f"{summary[4]:,}")
        logging.info("zero-population rows: %s", f"{summary[5]:,}")
        logging.info("Parquet: %s", paths["output_parquet"])
        if not args.skip_csv:
            logging.info("CSV: %s", paths["output_csv"])
        return 0
    finally:
        connection.close()
        for path in (parquet_temp, csv_temp):
            if path.exists():
                remove_exact_path(path, path.parent)
        if paths["database"].exists():
            remove_exact_path(paths["database"], paths["database"].parent)
        if paths["temp_directory"].exists():
            remove_exact_path(
                paths["temp_directory"], paths["temp_directory"].parent
            )


if __name__ == "__main__":
    sys.exit(main())

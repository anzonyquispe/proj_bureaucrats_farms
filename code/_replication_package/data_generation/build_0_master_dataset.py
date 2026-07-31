#!/usr/bin/env python3
"""Build the 2012-2024 grid-month master dataset with DuckDB.

The area-stage Parquet is the row-preserving base. Population, protests,
elections, fires, and AC-level rice information are added without changing
that key. Both Parquet and CSV outputs are written.
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
        "protests": (
            args.protests.resolve()
            if args.protests
            else intermediate / "8_grids_ac_pr_5km.csv"
        ),
        "elections": (
            args.elections.resolve()
            if args.elections
            else intermediate / "panel_data_election_year.dta"
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
    frame = pd.read_stata(path, convert_categoricals=False)
    required = {"ac_uq_id", "year", "month"}
    missing = sorted(required.difference(frame.columns))
    if missing:
        raise KeyError(f"Missing election columns: {missing}")
    if frame.duplicated(["ac_uq_id", "year", "month"]).any():
        raise ValueError(
            "The election panel is not unique by ac_uq_id x year x month."
        )

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
        if column in {"ac_uq_id", "year", "month"}:
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
        if area_rows != area_keys:
            raise ValueError("The area panel key is not unique.")
        if population_rows != population_keys:
            raise ValueError("The population panel key is not unique.")
        if area_rows != population_rows:
            raise ValueError(
                f"Area/population row mismatch: {area_rows:,} vs "
                f"{population_rows:,}."
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
        lookup_grids = scalar(connection, "SELECT count(*) FROM grid_lookup")
        population_grids = scalar(
            connection,
            f"""
            SELECT count(DISTINCT unique_small_grid_id)
            FROM read_parquet({population})
            """,
        )
        if lookup_grids != population_grids:
            raise ValueError(
                "At least one grid changes AC over time or has a missing AC."
            )

        unmatched_protests = scalar(
            connection,
            """
            SELECT count(*)
            FROM protest_grid AS p
            ANTI JOIN grid_lookup AS g USING (unique_small_grid_id)
            """,
        )
        if unmatched_protests:
            logging.warning(
                "Protest grids outside the four-state panel: %s",
                f"{unmatched_protests:,}",
            )

        missing_elections = scalar(
            connection,
            f"""
            SELECT count(*)
            FROM read_parquet({population}) AS p
            LEFT JOIN election_panel AS e
              USING (ac_uq_id, year, month)
            WHERE e.ac_uq_id IS NULL
            """,
        )
        if missing_elections:
            raise ValueError(
                f"Election data are missing for {missing_elections:,} rows."
            )

        missing_rice_acs = scalar(
            connection,
            f"""
            SELECT count(*)
            FROM (
                SELECT DISTINCT ac_uq_id
                FROM read_parquet({population})
            ) AS p
            ANTI JOIN rice_ac AS r USING (ac_uq_id)
            """,
        )
        if missing_rice_acs:
            logging.warning(
                "Rice data absent for %s panel ACs; rice columns will be zero.",
                f"{missing_rice_acs:,}",
            )

        mismatch_rows = scalar(
            connection,
            f"""
            SELECT count(*)
            FROM read_parquet({area}) AS a
            JOIN read_parquet({population}) AS p
              USING (unique_small_grid_id, year, month)
            WHERE
                a.downwind_pop IS DISTINCT FROM p.downwind_pop
                OR a.upwind_pop IS DISTINCT FROM p.upwind_pop
                OR a.downup_ac_pop IS DISTINCT FROM p.downup_ac_pop
            """,
        )
        if mismatch_rows:
            raise ValueError(
                f"Area/population measures disagree on {mismatch_rows:,} rows."
            )

        sd_value = scalar(
            connection,
            f"""
            SELECT stddev_samp(downwind_pop - upwind_pop)
            FROM read_parquet({area})
            """,
        )
        logging.info("downup_diff_pop sample SD: %.12g", sd_value)

        area_columns = {
            row[0]
            for row in connection.execute(
                f"DESCRIBE SELECT * FROM read_parquet({area})"
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
        }
        election_fields = election_select_list(
            list(elections.columns), area_columns | additional_columns
        )
        election_suffix = f",\n            {election_fields}" if election_fields else ""

        sd_literal = repr(float(sd_value))
        master_query = f"""
        WITH joined AS (
            SELECT
                a.*,
                p.ac_uq_id,
                p.calculation_wind_direction,
                a.downwind_pop AS downwind_pop_ac_nosmall,
                a.upwind_pop AS upwind_pop_ac_nosmall,
                a.downwind_pop + a.upwind_pop AS total_pop,
                a.downwind_pop - a.upwind_pop AS downup_diff_pop,
                a.downup_ac_area AS downup_ac,
                (a.year::INTEGER * 12 + a.month::INTEGER) AS monthyear,
                g.protest_id,
                g.protest_place,
                g.yr_pr_5km,
                g.mt_pr_5km,
                g.ac_area_tr,
                coalesce(f."count", 0)::BIGINT AS "count",
                f.mean_brightness,
                a.rollav_wind_speed_cellid_month AS av_wind_speed,
                a.wind_direction_av_cellid_month AS wind_direction,
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
                CASE
                    WHEN g.yr_pr_5km IS NULL OR g.mt_pr_5km IS NULL THEN 0
                    WHEN (a.year::INTEGER * 12 + a.month::INTEGER)
                         >= (g.yr_pr_5km::INTEGER * 12
                             + g.mt_pr_5km::INTEGER) THEN 1
                    ELSE 0
                END::TINYINT AS protest5km
                {election_suffix}
            FROM read_parquet({area}) AS a
            JOIN read_parquet({population}) AS p
              USING (unique_small_grid_id, year, month)
            JOIN grid_lookup AS g
              ON a.unique_small_grid_id = g.unique_small_grid_id
             AND p.ac_uq_id = g.ac_uq_id
            LEFT JOIN election_panel AS e
              ON p.ac_uq_id = e.ac_uq_id
             AND a.year = e.year
             AND a.month = e.month
            LEFT JOIN fire_grid AS f
              ON a.unique_small_grid_id = f.unique_small_grid_id
             AND a.year = f.year
             AND a.month = f.month
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
            missing_count,
            missing_rice,
        ) = connection.execute(
                f"""
                SELECT
                    count(*),
                    count(DISTINCT (
                        unique_small_grid_id, year, month
                    )),
                    count_if(ac_uq_id IS NULL),
                    count_if(election_year IS NULL),
                    count_if("count" IS NULL),
                    count_if(
                        rice_area_ha_aclvl IS NULL
                        OR rice_harvarea_ha_aclvl IS NULL
                        OR rice_prod_mt_aclvl IS NULL
                        OR rice_area_share_aclvl IS NULL
                        OR rice_harvarea_share_aclvl IS NULL
                        OR rice_area_aclvl_ahigh IS NULL
                        OR rice_harvarea_aclvl_ahigh IS NULL
                        OR rice_prod_aclvl_ahigh IS NULL
                    )
                FROM read_parquet({sql_string(paths['output_parquet'])})
                """
            ).fetchone()
        if output_rows != area_rows or output_keys != area_rows:
            raise ValueError("The output does not preserve the base panel key.")
        if missing_ac:
            raise ValueError("The output contains missing ac_uq_id values.")
        if missing_count or missing_rice:
            raise ValueError("Fire counts or rice fields remain missing.")
        logging.info(
            "Rows without election_year (field may legitimately be missing): %s",
            f"{missing_election:,}",
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

#!/usr/bin/env python3
"""Export the reference dataset's grid-month ``downup_pop`` crosswalk to Stata.

The bureaucrat treatment uses the district population-based Down>Up dummy
(``downup_pop``) from the reference grid-month dataset.  The master dataset only
carries the area-based ``downup_dummy`` from that source, so this small-width
crosswalk exposes ``downup_pop`` on the master's grid-month keys without
importing the full reference CSV in Stata.
"""

from __future__ import annotations

import argparse
import logging
import os
from pathlib import Path

import duckdb


CLUSTER_INTERMEDIATE = Path(
    "/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate"
)
LOCAL_INTERMEDIATE = Path(
    r"C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms"
    r"\data_output\intermediate"
)

# Same four-state restriction as build_grid_ac_panel_2012_2024.py, applied to
# province names normalized like normalize_state_name().
SOURCE_STATES = ("BIHAR", "HARYANA", "PUNJAB IND", "PUNJAB", "UTTAR PRADESH")


def default_intermediate() -> Path:
    return LOCAL_INTERMEDIATE if LOCAL_INTERMEDIATE.exists() else CLUSTER_INTERMEDIATE


def parse_args() -> argparse.Namespace:
    intermediate = default_intermediate()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-csv",
        type=Path,
        default=intermediate / "data_2012_2022_downup.csv",
    )
    parser.add_argument(
        "--master-parquet",
        type=Path,
        default=intermediate / "0_master_dataset.parquet",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=intermediate / "grid_month_downup_pop.dta",
    )
    parser.add_argument("--threads", type=int, default=max(1, os.cpu_count() or 1))
    parser.add_argument("--memory-limit", default="16GB")
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def qstr(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
    )
    source_csv = args.source_csv.resolve()
    master = args.master_parquet.resolve()
    output = args.output.resolve()
    if not source_csv.is_file():
        raise FileNotFoundError(f"Reference CSV not found: {source_csv}")
    if not master.is_file():
        raise FileNotFoundError(f"Master parquet not found: {master}")
    if output.exists() and not args.overwrite:
        raise FileExistsError(f"Output exists; pass --overwrite: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect()
    con.execute(f"SET threads={max(1, args.threads)}")
    con.execute(f"SET memory_limit={qstr(args.memory_limit)}")
    con.execute("SET preserve_insertion_order=false")

    # Read as text so sparse columns cannot be mis-typed by the CSV sniffer.
    source = f"read_csv({qstr(source_csv)}, header=true, all_varchar=true)"
    required = {"unique_grid_id", "year", "month", "province", "downup_dummy", "downup_pop"}
    columns = {
        row[0] for row in con.execute(f"DESCRIBE SELECT * FROM {source}").fetchall()
    }
    missing = sorted(required - columns)
    if missing:
        raise ValueError("Reference CSV is missing: " + ", ".join(missing))

    states = ", ".join(qstr(state) for state in SOURCE_STATES)
    logging.info("Reading %s", source_csv)
    con.execute(
        f"""
        CREATE TEMP TABLE crosswalk AS
        SELECT
            CAST(unique_grid_id AS BIGINT) AS unique_small_grid_id,
            CAST(year AS INTEGER) AS year,
            CAST(month AS INTEGER) AS month,
            CAST(nullif(trim(downup_dummy), '') AS DOUBLE) AS downup_dummy,
            CAST(nullif(trim(downup_pop), '') AS DOUBLE) AS downup_pop
        FROM {source}
        WHERE trim(regexp_replace(upper(province), '[_\\W]+', ' ', 'g')) IN ({states})
        """
    )

    rows, unique_keys, non_binary, pop_one, pop_zero, pop_null = con.execute(
        """
        SELECT
            count(*),
            count(DISTINCT (unique_small_grid_id, year, month)),
            count_if(downup_pop IS NOT NULL AND downup_pop NOT IN (0, 1)),
            count_if(downup_pop = 1),
            count_if(downup_pop = 0),
            count_if(downup_pop IS NULL)
        FROM crosswalk
        """
    ).fetchone()
    if rows == 0:
        raise ValueError("No four-state rows were found in the reference CSV.")
    if rows != unique_keys:
        raise ValueError(
            "Reference grid-year-month key is not unique: "
            f"rows={rows:,}, unique_keys={unique_keys:,}"
        )
    if non_binary:
        raise ValueError(f"downup_pop has {non_binary:,} values outside {{0, 1}}")
    logging.info(
        "downup_pop: %s ones, %s zeros, %s missing (of %s rows)",
        f"{pop_one:,}",
        f"{pop_zero:,}",
        f"{pop_null:,}",
        f"{rows:,}",
    )

    # The master's downup_dummy comes from this same source, so every master row
    # carrying it must find its key here with an identical value.
    unmatched, mismatched = con.execute(
        f"""
        SELECT
            count_if(c.unique_small_grid_id IS NULL),
            count_if(
                c.unique_small_grid_id IS NOT NULL
                AND c.downup_dummy IS DISTINCT FROM m.downup_dummy
            )
        FROM (
            SELECT
                CAST(unique_small_grid_id AS BIGINT) AS unique_small_grid_id,
                CAST(year AS INTEGER) AS year,
                CAST(month AS INTEGER) AS month,
                CAST(downup_dummy AS DOUBLE) AS downup_dummy
            FROM read_parquet({qstr(master)})
            WHERE downup_dummy IS NOT NULL
        ) AS m
        LEFT JOIN crosswalk AS c
          USING (unique_small_grid_id, year, month)
        """
    ).fetchone()
    if unmatched or mismatched:
        raise ValueError(
            "Reference keys do not align with the master: "
            f"{unmatched:,} master rows unmatched, "
            f"{mismatched:,} downup_dummy disagreements"
        )
    logging.info("Master downup_dummy agrees with the reference on every row")

    frame = con.execute(
        """
        SELECT
            CAST(unique_small_grid_id AS INTEGER) AS unique_small_grid_id,
            CAST(month AS TINYINT) AS month,
            CAST(year AS SMALLINT) AS year,
            CAST(downup_pop AS FLOAT) AS downup_pop
        FROM crosswalk
        ORDER BY unique_small_grid_id, year, month
        """
    ).fetchdf()
    con.close()

    temporary = output.with_name(output.stem + ".tmp" + output.suffix)
    if temporary.exists():
        temporary.unlink()
    try:
        frame.to_stata(temporary, write_index=False, version=118)
        temporary.replace(output)
    finally:
        if temporary.exists():
            temporary.unlink()

    logging.info("Completed crosswalk: %s", output)
    logging.info("Rows: %s", f"{len(frame):,}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

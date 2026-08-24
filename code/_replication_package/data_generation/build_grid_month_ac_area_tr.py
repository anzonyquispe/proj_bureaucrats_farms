#!/usr/bin/env python3
"""Export the master dataset's grid-month ``ac_area_tr`` crosswalk to Stata.

The protest estimations reproduce the reference analysis by clustering on
``ac_area_tr``.  This small-width crosswalk avoids repeatedly importing the
full master CSV in Stata while preserving its canonical grid-month assignment.
"""

from __future__ import annotations

import argparse
import logging
import os
from pathlib import Path

import duckdb
import pandas as pd


CLUSTER_INTERMEDIATE = Path(
    "/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate"
)
LOCAL_INTERMEDIATE = Path(
    r"C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms"
    r"\data_output\intermediate"
)


def default_intermediate() -> Path:
    return LOCAL_INTERMEDIATE if LOCAL_INTERMEDIATE.exists() else CLUSTER_INTERMEDIATE


def parse_args() -> argparse.Namespace:
    intermediate = default_intermediate()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--master-parquet",
        type=Path,
        default=intermediate / "0_master_dataset.parquet",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=intermediate / "grid_month_ac_area_tr.dta",
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
    master = args.master_parquet.resolve()
    output = args.output.resolve()
    if not master.is_file():
        raise FileNotFoundError(f"Master parquet not found: {master}")
    if output.exists() and not args.overwrite:
        raise FileExistsError(f"Output exists; pass --overwrite: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect()
    con.execute(f"SET threads={max(1, args.threads)}")
    con.execute(f"SET memory_limit={qstr(args.memory_limit)}")
    con.execute("SET preserve_insertion_order=false")
    source = f"read_parquet({qstr(master)})"

    required = {"unique_small_grid_id", "month", "year", "ac_area_tr"}
    columns = {
        row[0] for row in con.execute(f"DESCRIBE SELECT * FROM {source}").fetchall()
    }
    missing = sorted(required - columns)
    if missing:
        raise ValueError("Master parquet is missing: " + ", ".join(missing))

    rows, unique_keys, missing_area = con.execute(
        f"""
        SELECT
            count(*),
            count(DISTINCT (unique_small_grid_id, year, month)),
            count_if(ac_area_tr IS NULL)
        FROM {source}
        """
    ).fetchone()
    if rows != unique_keys:
        raise ValueError(
            "Master grid-year-month key is not unique: "
            f"rows={rows:,}, unique_keys={unique_keys:,}"
        )
    if missing_area:
        raise ValueError(f"Master contains {missing_area:,} missing ac_area_tr values")

    logging.info("Reading %s validated grid-month assignments", f"{rows:,}")
    frame = con.execute(
        f"""
        SELECT
            CAST(unique_small_grid_id AS INTEGER) AS unique_small_grid_id,
            CAST(month AS TINYINT) AS month,
            CAST(year AS SMALLINT) AS year,
            CAST(ac_area_tr AS SMALLINT) AS ac_area_tr
        FROM {source}
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

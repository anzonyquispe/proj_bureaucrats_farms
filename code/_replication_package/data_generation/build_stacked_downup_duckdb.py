#!/usr/bin/env python3
"""Build combined_dt.csv and combined_dt.db from the master Parquet.

This is the area-treatment launcher for the resumable, cohort-by-cohort
DuckDB pipeline in ``build_stacked_downup_13kmpl_duckdb.py``. Command-line
arguments supplied by the caller override these project defaults.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from build_stacked_downup_13kmpl_duckdb import main


CLUSTER_INTERMEDIATE = Path(
    "/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate"
)
LOCAL_INTERMEDIATE = Path(
    r"C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms"
    r"\data_output\intermediate"
)


def default_intermediate() -> Path:
    return LOCAL_INTERMEDIATE if LOCAL_INTERMEDIATE.exists() else CLUSTER_INTERMEDIATE


def project_defaults() -> list[str]:
    intermediate = default_intermediate()
    threads = os.environ.get("NSLOTS", str(os.cpu_count() or 1))
    return [
        "--input",
        str(intermediate / "0_master_dataset.parquet"),
        "--output",
        str(intermediate / "combined_dt.csv"),
        "--database",
        str(intermediate / "combined_dt.db"),
        "--temp-directory",
        str(intermediate / "combined_dt_duckdb_tmp"),
        "--treatment-col",
        "downup_ac",
        "--keep-cols",
        "unique_small_grid_id",
        "month",
        "year",
        "monthyear",
        "province",
        "ac_uq_id",
        "downup_ac",
        "count",
        "av_wind_speed",
        "wind_direction",
        "rice_prod_aclvl_ahigh",
        "--cutoff-year",
        "2022",
        "--cutoff-month",
        "8",
        "--threads",
        threads,
        "--memory-limit",
        "90GB",
        "--checkpoint-every",
        "25",
        "--write-manifest",
    ]


if __name__ == "__main__":
    raise SystemExit(main([*project_defaults(), *sys.argv[1:]]))

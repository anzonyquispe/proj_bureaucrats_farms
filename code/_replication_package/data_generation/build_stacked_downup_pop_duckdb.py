#!/usr/bin/env python3
"""Build combined_dt_pop.csv and combined_dt_pop.db from master Parquet."""

from __future__ import annotations

import sys

from build_stacked_downup_duckdb import project_defaults
from build_stacked_downup_13kmpl_duckdb import main


def population_defaults() -> list[str]:
    defaults = project_defaults()
    population: list[str] = []
    for value in defaults:
        if value == "downup_ac":
            population.append("downup_ac_pop")
        else:
            population.append(
                value.replace(
                    "combined_dt_duckdb_tmp",
                    "combined_dt_pop_duckdb_tmp",
                )
                .replace("combined_dt.csv", "combined_dt_pop.csv")
                .replace("combined_dt.db", "combined_dt_pop.db")
            )
    return population


if __name__ == "__main__":
    raise SystemExit(main([*population_defaults(), *sys.argv[1:]]))

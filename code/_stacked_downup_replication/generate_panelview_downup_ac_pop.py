#!/usr/bin/env python3
"""Generate the grid-level panel view for the population downwind treatment.

The input is the canonical ``0_master_merge_data_gen.csv`` panel.  Grids are
sampled reproducibly within province x assembly-constituency strata; the
sampling unit is always the grid, and every month for a selected grid is kept.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import duckdb
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
from matplotlib.patches import Patch
import numpy as np
import pandas as pd


DEFAULT_DATA_ROOT = Path(
    r"C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms"
)
DEFAULT_REPO = Path(
    r"C:\Users\eunic\OneDrive\Documents\GitHub\proj_bureaucrats_farms"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT)
    parser.add_argument("--repo", type=Path, default=DEFAULT_REPO)
    parser.add_argument("--sample", default="", help="Input suffix, e.g. _sample")
    parser.add_argument("--fraction", type=float, default=0.01)
    parser.add_argument("--seed", type=int, default=20260831)
    return parser.parse_args()


def sql_path(path: Path) -> str:
    return str(path.resolve()).replace("'", "''").replace("\\", "/")


def main() -> None:
    args = parse_args()
    if not 0 < args.fraction <= 1:
        raise ValueError("--fraction must be in (0, 1].")

    intermediate = args.data_root / "data_output" / "intermediate"
    master = intermediate / f"0_master_merge_data_gen{args.sample}.csv"
    if not master.exists():
        raise FileNotFoundError(f"Missing master dataset: {master}")

    figures = args.repo / "figures"
    tables = args.repo / "tables"
    figures.mkdir(parents=True, exist_ok=True)
    tables.mkdir(parents=True, exist_ok=True)
    output = figures / "panelview_downup_ac_pop.png"
    audit_output = tables / "panelview_downup_ac_pop_selected_grids.csv"
    excluded_output = tables / "panelview_downup_ac_pop_excluded_grids.csv"

    master_sql = sql_path(master)
    scan = (
        f"read_csv_auto('{master_sql}', header=true, parallel=true, "
        "union_by_name=true)"
    )
    date_filter = """
        (year > 2012 OR (year = 2012 AND month >= 9))
        AND (year < 2022 OR (year = 2022 AND month <= 8))
    """

    con = duckdb.connect()
    con.execute("SET threads TO 10")
    con.execute("SET preserve_insertion_order = false")

    # Hash ordering gives deterministic pseudo-random sampling without loading
    # the multi-gigabyte master CSV into pandas.  CEIL guarantees at least one
    # sampled grid in every nonempty province x AC stratum.
    selected = con.execute(
        f"""
        WITH grid_attributes AS (
            SELECT
                unique_small_grid_id,
                min(province) AS province,
                min(ac_uq_id) AS ac_uq_id,
                count(DISTINCT province) AS n_provinces,
                count(DISTINCT ac_uq_id) AS n_acs
            FROM {scan}
            WHERE {date_filter}
            GROUP BY unique_small_grid_id
        ), valid_grids AS (
            SELECT *
            FROM grid_attributes
            WHERE n_provinces = 1 AND n_acs = 1
        ), ranked AS (
            SELECT
                unique_small_grid_id,
                province,
                ac_uq_id,
                row_number() OVER (
                    PARTITION BY province, ac_uq_id
                    ORDER BY hash(unique_small_grid_id, {args.seed})
                ) AS sample_rank,
                count(*) OVER (PARTITION BY province, ac_uq_id) AS stratum_grids
            FROM valid_grids
        )
        SELECT
            unique_small_grid_id,
            province,
            ac_uq_id,
            sample_rank,
            stratum_grids,
            greatest(1, CAST(ceil(stratum_grids * {args.fraction}) AS BIGINT))
                AS selected_from_stratum
        FROM ranked
        WHERE sample_rank <= greatest(
            1, CAST(ceil(stratum_grids * {args.fraction}) AS BIGINT)
        )
        ORDER BY province, ac_uq_id, sample_rank
        """
    ).fetchdf()

    # Province must never change.  A grid with changing AC membership cannot
    # belong to a unique province x AC sampling stratum, so record and exclude
    # it explicitly rather than assigning it arbitrarily.
    all_grid_audit = con.execute(
        f"""
        SELECT
            count(*) AS grids,
            count(*) FILTER (WHERE n_provinces <> 1) AS changing_province,
            count(*) FILTER (WHERE n_acs <> 1) AS changing_ac
        FROM (
            SELECT
                unique_small_grid_id,
                count(DISTINCT province) AS n_provinces,
                count(DISTINCT ac_uq_id) AS n_acs
            FROM {scan}
            WHERE {date_filter}
            GROUP BY unique_small_grid_id
        )
        """
    ).fetchone()
    if all_grid_audit[1]:
        raise ValueError(
            "Grid geography changes inside the plotting window: "
            f"changing province={all_grid_audit[1]:,}, "
            f"changing AC={all_grid_audit[2]:,}."
        )
    if all_grid_audit[2]:
        excluded = con.execute(
            f"""
            SELECT
                unique_small_grid_id,
                string_agg(DISTINCT CAST(province AS VARCHAR), ', '
                           ORDER BY CAST(province AS VARCHAR)) AS provinces,
                string_agg(DISTINCT CAST(ac_uq_id AS VARCHAR), ', '
                           ORDER BY CAST(ac_uq_id AS VARCHAR)) AS ac_uq_ids
            FROM {scan}
            WHERE {date_filter}
            GROUP BY unique_small_grid_id
            HAVING count(DISTINCT ac_uq_id) <> 1
            ORDER BY unique_small_grid_id
            """
        ).fetchdf()
        excluded.to_csv(excluded_output, index=False)
        print(
            "WARNING: Excluded "
            f"{len(excluded):,} grid(s) with changing AC membership; "
            f"audit written to {excluded_output}"
        )

    selected["sample_seed"] = args.seed
    selected["sample_fraction"] = args.fraction
    selected.to_csv(audit_output, index=False)
    con.register("selected_grids", selected[["unique_small_grid_id"]])

    panel = con.execute(
        f"""
        SELECT
            m.unique_small_grid_id,
            CAST(m.year AS INTEGER) AS year,
            CAST(m.month AS INTEGER) AS month,
            CAST(m.downup_ac_pop AS INTEGER) AS downup_ac_pop
        FROM {scan} AS m
        INNER JOIN selected_grids AS s USING (unique_small_grid_id)
        WHERE {date_filter}
        ORDER BY m.unique_small_grid_id, m.year, m.month
        """
    ).fetchdf()
    con.close()

    panel["month_index"] = (
        (panel["year"] - 2012) * 12 + panel["month"] - 8
    ).astype("int16")
    if panel.duplicated(["unique_small_grid_id", "month_index"]).any():
        raise ValueError("Master data are not unique by grid and month.")
    observed_treatment = set(panel["downup_ac_pop"].dropna().unique())
    if not observed_treatment.issubset({0, 1}):
        raise ValueError(
            f"downup_ac_pop contains values outside 0/1: {observed_treatment}"
        )
    if panel["downup_ac_pop"].isna().any():
        raise ValueError("Selected grids contain missing downup_ac_pop values.")

    months_per_grid = panel.groupby("unique_small_grid_id")["month_index"].nunique()
    if not (months_per_grid == 120).all():
        bad = int((months_per_grid != 120).sum())
        raise ValueError(f"{bad:,} selected grids do not contain all 120 months.")
    if set(panel["month_index"].unique()) != set(range(1, 121)):
        raise ValueError("The panel must span month indices 1 through 120.")

    wide = panel.pivot(
        index="unique_small_grid_id",
        columns="month_index",
        values="downup_ac_pop",
    ).astype("int8")
    first_downwind = wide.eq(1).idxmax(axis=1)
    first_downwind.loc[~wide.eq(1).any(axis=1)] = 121
    selected_index = selected.set_index("unique_small_grid_id")
    ordering = pd.DataFrame(
        {
            "first_downwind": first_downwind,
            "province": selected_index.loc[wide.index, "province"].astype(str),
            "ac_uq_id": selected_index.loc[wide.index, "ac_uq_id"],
            "grid": wide.index,
        },
        index=wide.index,
    ).sort_values(["first_downwind", "province", "ac_uq_id", "grid"])
    wide = wide.loc[ordering.index]

    fig, ax = plt.subplots(figsize=(12, 8))
    ax.imshow(
        wide.to_numpy(dtype="int8"),
        aspect="auto",
        cmap=ListedColormap(["#cfe2f3", "#1f4e79"]),
        vmin=0,
        vmax=1,
        interpolation="nearest",
        rasterized=True,
    )
    month_breaks = np.array([1, *range(12, 121, 12)])
    ax.set_xticks(month_breaks - 1, month_breaks)
    ax.set_xlabel("Month (1 = September 2012; 120 = August 2022)")
    ax.set_ylabel("")
    ax.set_yticks([])
    ax.tick_params(axis="y", length=0)
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.legend(
        handles=[
            Patch(facecolor="#cfe2f3", label="Upwind (Down ≤ Up population)"),
            Patch(facecolor="#1f4e79", label="Downwind (Down > Up population)"),
        ],
        loc="upper center",
        bbox_to_anchor=(0.5, -0.10),
        ncol=2,
        frameon=False,
    )
    fig.tight_layout()
    fig.savefig(output, dpi=300, bbox_inches="tight")
    plt.close(fig)

    strata = selected[["province", "ac_uq_id"]].drop_duplicates().shape[0]
    print(f"Master grids audited: {all_grid_audit[0]:,}")
    print(
        f"Selected {len(selected):,} grids from {strata:,} province-AC strata "
        f"({args.fraction:.1%}, minimum one grid per stratum)."
    )
    print(f"Panel rows plotted: {len(panel):,} ({len(selected):,} grids x 120 months)")
    print(f"Generated: {output}")
    print(f"Sampling audit: {audit_output}")


if __name__ == "__main__":
    main()

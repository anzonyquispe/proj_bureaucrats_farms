#!/usr/bin/env python3
"""Generate the three active protest-design figures referenced by main.tex."""

from __future__ import annotations

import argparse
from pathlib import Path

import geopandas as gpd
import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
import pandas as pd


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument(
        "--shared-root",
        type=Path,
        help="sa_fires root containing data/input (defaults to root parent)",
    )
    return parser.parse_args()


def require(path: Path) -> Path:
    if not path.exists():
        raise FileNotFoundError(f"Required input does not exist: {path}")
    return path


def main() -> None:
    options = parse_args()
    root = options.root
    shared = options.shared_root or root.parent
    intermediate = root / "data_output" / "intermediate"
    figures = root / "tex" / "paper" / "figures"
    figures.mkdir(parents=True, exist_ok=True)

    states = gpd.read_file(require(
        shared / "data" / "input" / "admin-data" / "india" / "IND_adm" / "IND_adm1.shp"
    ))
    states = states.loc[states.NAME_1.isin(["Bihar", "Uttar Pradesh", "Punjab", "Haryana"])]
    protest_grid = pd.read_csv(require(intermediate / "8_grids_ac_pr_5km.csv"))
    intersection = pd.read_csv(require(intermediate / "_1_AC_grid_intersection.csv"))
    joined = intersection.merge(protest_grid, how="left")
    joined["protest_place"] = joined.protest_place.fillna(0)
    grid = gpd.read_file(require(intermediate / "1-grid-generation.shp"))
    if "unq_s__" in grid:
        grid = grid.rename(columns={"unq_s__": "unique_small_grid_id"})
    joined = gpd.GeoDataFrame(
        joined.merge(grid[["unique_small_grid_id", "geometry"]]),
        geometry="geometry",
        crs=grid.crs,
    )
    joined["treat"] = joined.protest_place.gt(0).astype(int)
    constituencies = gpd.read_file(require(intermediate / "_0_2_3_ACs_right_shapefile.shp"))

    fig, ax = plt.subplots(figsize=(8, 8))
    states.boundary.plot(ax=ax, color="black")
    constituencies.boundary.plot(ax=ax, color="#2C4460", linewidth=0.2)
    joined.plot(ax=ax, color=joined.treat.map({0: "white", 1: "#2793F2"}), linewidth=0)
    ax.legend(
        handles=[
            mpatches.Patch(facecolor="#2793F2", edgecolor="black", label="Treated"),
            mpatches.Patch(facecolor="white", edgecolor="black", label="Control"),
        ],
        loc="upper right",
        frameon=False,
    )
    ax.axis("off")
    fig.savefig(figures / "5km_plot.png", dpi=300, bbox_inches="tight")
    plt.close(fig)

    protests = pd.read_csv(
        require(shared / "data" / "input" / "acled" / "2000-01-01-2025-05-13-South_Asia-India.csv"),
        sep=";",
    )
    protests["event_date"] = pd.to_datetime(protests.event_date, dayfirst=True)
    protests = protests.loc[protests.event_date.between("2020-06-01", "2021-12-09")].copy()
    farmer = protests.assoc_actor_1.str.lower().str.contains(r"\bfarm\w*", na=False)
    farmer |= protests.notes.str.lower().str.contains(r"\bfarm\w*", na=False)
    protests = protests.loc[farmer].copy()
    protests["year_month"] = protests.event_date.dt.to_period("M")
    monthly = (
        protests[["year_month", "admin1"]]
        .drop_duplicates()
        .year_month.value_counts()
        .sort_index()
    )
    monthly.index = monthly.index.to_timestamp()
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.bar(monthly.index, monthly.values, color="steelblue", edgecolor="black", width=20)
    ax.set_xlabel("Month")
    ax.set_ylabel("Count of Number of Protests")
    ax.grid(alpha=0.3, axis="y")
    span = monthly.index.max() - monthly.index.min()
    ax.set_xlim(monthly.index.min() - span * 0.05, monthly.index.max() + span * 0.05)
    fig.tight_layout()
    fig.savefig(figures / "protests_monthly_bars.png", dpi=300)
    plt.close(fig)

    points = gpd.GeoDataFrame(
        protests,
        geometry=gpd.points_from_xy(protests.longitude, protests.latitude),
        crs="EPSG:4326",
    )
    ac_id = 285
    events = gpd.sjoin(
        points,
        constituencies[["ac_uq_id", "geometry"]],
        predicate="within",
    )
    events = events.loc[events.ac_uq_id.eq(ac_id)].drop_duplicates(["latitude", "longitude"])
    buffers = events.to_crs(7755).copy()
    buffers.geometry = buffers.geometry.buffer(5000)
    buffers = buffers.to_crs(4326)
    fig, ax = plt.subplots(figsize=(8, 8))
    buffers.plot(ax=ax, color="blue", alpha=0.2)
    constituencies.loc[constituencies.ac_uq_id.eq(ac_id)].boundary.plot(ax=ax, color="black")
    ax.legend(
        handles=[
            mpatches.Patch(color="blue", alpha=0.2, label="Protests"),
            mpatches.Patch(edgecolor="black", facecolor="none", label="Assembly Constituency"),
        ],
        loc="lower right",
        frameon=False,
    )
    ax.axis("off")
    fig.tight_layout()
    fig.savefig(figures / "ac_protest_plot.png", dpi=300)
    plt.close(fig)
    print("Generated 5km_plot.png, protests_monthly_bars.png, and ac_protest_plot.png")


if __name__ == "__main__":
    main()

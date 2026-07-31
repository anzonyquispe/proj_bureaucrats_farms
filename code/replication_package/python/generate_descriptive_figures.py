#!/usr/bin/env python3
"""Generate active descriptive figures formerly embedded in notebooks."""

from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
from matplotlib.patches import Patch
import numpy as np
import pandas as pd


def args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--sample", default="")
    parser.add_argument("--rural-var", default="is_rural_area")
    return parser.parse_args()


def require(path: Path) -> Path:
    if not path.exists():
        raise FileNotFoundError(f"Required input does not exist: {path}")
    return path


def merge_rural(data: pd.DataFrame, intermediate: Path, rural_var: str) -> pd.DataFrame:
    rural = pd.read_stata(require(intermediate / "ghs_grid_classification_2000.dta"))
    if rural_var not in rural and rural_var == "is_rural_area" and "is_rural" in rural:
        rural = rural.rename(columns={"is_rural": rural_var})
    if rural_var not in rural:
        raise KeyError(f"{rural_var!r} is absent from ghs_grid_classification_2000.dta")
    return data.merge(
        rural[["unique_small_grid_id", rural_var]], on="unique_small_grid_id", how="inner"
    ).query(f"{rural_var} == 1").copy()


def monthly_figures(intermediate: Path, figures: Path, sample: str, rural_var: str) -> None:
    data = pd.read_csv(
        require(intermediate / f"0_master_merge_data_gen{sample}.csv"), low_memory=False
    )
    data = merge_rural(data, intermediate, rural_var)
    data = data.loc[(data.year < 2022) | ((data.year == 2022) & (data.month <= 8))].copy()
    data["date"] = pd.to_datetime(dict(year=data.year, month=data.month, day=1))
    monthly = data.groupby(["year", "month", "date"], as_index=False).agg(
        count=("count", "sum"),
        actual_wind=("wind_direction", "mean"),
        rolling_wind=("rollav_wind_direction_cellid_month", "mean"),
    )
    monthly["count"] /= 1000
    september = monthly.loc[monthly.date.dt.month.eq(9), "date"].tolist()
    september.append(pd.Timestamp(2022, 9, 1))
    september = sorted(set(september))

    fig, ax = plt.subplots(figsize=(10, 6))
    ax.plot(monthly.date, monthly["count"], color="red", marker="o")
    ax.set_xticks(september, [f"{d.year}m{d.month}" for d in september])
    ax.set_ylabel("Monthly Number of Fires (in 1000)")
    ax.grid(True, linestyle="--", alpha=0.5)
    ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(figures / "monthly_fires.png", dpi=300, bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(10, 6))
    ax.plot(monthly.date, monthly.actual_wind, "--s", color="lightblue", label="Actual")
    ax.plot(monthly.date, monthly.rolling_wind, "--^", color="pink", label="10yr Rolling")
    ax.set_xticks(september, [f"{d.year}m{d.month}" for d in september])
    ax.set_ylabel("Monthly Wind Bearing")
    ax.grid(True, linestyle="--", alpha=0.5)
    ax.spines[["top", "right"]].set_visible(False)
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.06), ncol=2, frameon=False)
    fig.tight_layout()
    fig.savefig(figures / "monthly_wind_direction.png", dpi=300, bbox_inches="tight")
    plt.close(fig)


def relative_time_histogram(intermediate: Path, figures: Path, sample: str, rural_var: str) -> None:
    data = pd.read_stata(require(intermediate / f"combined_dt_pop{sample}.dta"))
    data = merge_rural(data, intermediate, rural_var)
    duplicate = pd.read_stata(require(intermediate / "grids_with_more_1_ac.dta"))
    data = data.merge(duplicate, on="unique_small_grid_id", how="left")
    data = data.loc[
        data.dpl_ac.isna()
        & ((data.year < 2022) | ((data.year == 2022) & (data.month <= 8)))
    ]
    counts = data.groupby("relative_monthyear").size().rename("n_obs").reset_index()
    edge = max(abs(counts.relative_monthyear.min()), abs(counts.relative_monthyear.max()))
    bins = np.arange(-edge, edge + 5, 5)
    fig, ax = plt.subplots(figsize=(8, 5))
    ax.hist(
        counts.relative_monthyear,
        bins=bins,
        weights=counts.n_obs / 1000,
        color="gray",
        edgecolor="black",
        alpha=0.8,
    )
    ax.set_xlabel("Relative Time periods from Treatment")
    ax.set_ylabel("Density of Observations per period")
    ax.grid(alpha=0.3, axis="y")
    fig.tight_layout()
    fig.savefig(figures / "downup_evtime_hist.png", dpi=300)
    plt.close(fig)


def politician_panel(intermediate: Path, figures: Path, sample: str) -> None:
    use = ["unique_small_grid_id", "monthyear", "self_profession"]
    data = pd.read_csv(
        require(intermediate / f"0_master_merge_data_gen{sample}.csv"), usecols=use
    )
    data.self_profession = data.self_profession.fillna(0).astype(int)
    wide = data.pivot_table(
        index="unique_small_grid_id", columns="monthyear", values="self_profession", aggfunc="max"
    ).fillna(0).sort_index().sort_index(axis=1)
    matrix = wide.to_numpy(float)
    height = max(6, matrix.shape[0] * 0.02)
    width = max(10, matrix.shape[1] * 0.06)
    fig, ax = plt.subplots(figsize=(width, height))
    ax.imshow(
        matrix,
        aspect="auto",
        cmap=ListedColormap(["#cfe2f3", "#1f77b4"]),
        vmin=0,
        vmax=1,
        interpolation="nearest",
    )
    xidx = np.linspace(0, matrix.shape[1] - 1, min(20, matrix.shape[1]), dtype=int)
    yidx = np.linspace(0, matrix.shape[0] - 1, min(30, matrix.shape[0]), dtype=int)
    ax.set_xticks(xidx, [str(wide.columns[i]) for i in xidx], rotation=45, ha="right")
    ax.set_yticks(yidx, [str(wide.index[i]) for i in yidx], fontsize=7)
    ax.set_xlabel("Month-Year")
    ax.set_ylabel("Grid ID")
    ax.legend(
        handles=[
            Patch(facecolor="#1f77b4", edgecolor="black", label="Agricultural profession"),
            Patch(facecolor="#cfe2f3", edgecolor="black", label="Non-agricultural profession"),
        ],
        loc="upper right",
        bbox_to_anchor=(1, -0.08),
        ncol=2,
        frameon=False,
    )
    fig.tight_layout()
    fig.savefig(figures / "panelview_self_profession.png", dpi=300, bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    options = args()
    intermediate = options.root / "data_output" / "intermediate"
    figures = options.root / "tex" / "paper" / "figures"
    figures.mkdir(parents=True, exist_ok=True)
    monthly_figures(intermediate, figures, options.sample, options.rural_var)
    relative_time_histogram(intermediate, figures, options.sample, options.rural_var)
    politician_panel(intermediate, figures, options.sample)
    print("Generated monthly, relative-time, and panel-view figures.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate the active descriptive figures referenced by main.tex."""

from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
from matplotlib.patches import Patch
import numpy as np
import pandas as pd


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--sample", default="")
    parser.add_argument("--rural-var", default="is_rural")
    parser.add_argument(
        "--only", choices=("all", "panelview"), default="all",
        help="Generate every descriptive figure or only panelview_self_profession.",
    )
    return parser.parse_args()


def require(path: Path) -> Path:
    if not path.exists():
        raise FileNotFoundError(f"Required input does not exist: {path}")
    return path


def merge_rural(data: pd.DataFrame, intermediate: Path, rural_var: str) -> pd.DataFrame:
    rural = pd.read_stata(require(intermediate / "ghs_grid_classification_2000.dta"))
    if rural_var not in rural:
        raise KeyError(f"{rural_var!r} is absent from ghs_grid_classification_2000.dta")
    rural = rural[["unique_small_grid_id", rural_var]].drop_duplicates()
    if rural.unique_small_grid_id.duplicated().any():
        raise ValueError("Rural classification is not unique by unique_small_grid_id")
    merged = data.merge(rural, on="unique_small_grid_id", how="left", validate="many_to_one")
    return merged.loc[merged[rural_var].eq(1)].copy()


def monthly_figures(intermediate: Path, figures: Path, sample: str, rural_var: str) -> None:
    use = [
        "unique_small_grid_id", "year", "month", "count", "wind_direction",
        "rollav_wind_direction_cellid_month",
    ]
    data = pd.read_csv(
        require(intermediate / f"0_master_dataset{sample}.csv"),
        usecols=use,
        low_memory=False,
    )
    data = merge_rural(data, intermediate, rural_var)
    data = data.loc[(data.year < 2022) | ((data.year == 2022) & (data.month <= 8))].copy()
    data["date"] = pd.to_datetime(dict(year=data.year, month=data.month, day=1))
    monthly = data.groupby(["year", "month", "date"], as_index=False).agg(
        count=("count", "sum"),
        actual_wind=("wind_direction", "mean"),
        rolling_wind=("rollav_wind_direction_cellid_month", "mean"),
    )
    monthly["count_thousands"] = monthly["count"] / 1000
    september = sorted(
        set(monthly.loc[monthly.date.dt.month.eq(9), "date"].tolist() + [pd.Timestamp(2022, 9, 1)])
    )

    fig, ax = plt.subplots(figsize=(10, 6))
    ax.plot(monthly.date, monthly.count_thousands, color="red", marker="o")
    ax.set_xticks(september, [f"{date.year}m{date.month}" for date in september])
    ax.set_ylabel("Monthly Number of Fires (in 1000)")
    ax.grid(True, linestyle="--", alpha=0.5)
    ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(figures / "monthly_fires.png", dpi=300, bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(10, 6))
    ax.plot(monthly.date, monthly.actual_wind, "--s", color="lightblue", label="Actual")
    ax.plot(monthly.date, monthly.rolling_wind, "--^", color="pink", label="10yr Rolling")
    ax.set_xticks(september, [f"{date.year}m{date.month}" for date in september])
    ax.set_ylabel("Monthly Wind Bearing")
    ax.grid(True, linestyle="--", alpha=0.5)
    ax.spines[["top", "right"]].set_visible(False)
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.06), ncol=2, frameon=False)
    fig.tight_layout()
    fig.savefig(figures / "monthly_wind_direction.png", dpi=300, bbox_inches="tight")
    plt.close(fig)


def relative_time_histogram(intermediate: Path, figures: Path, sample: str, rural_var: str) -> None:
    use = ["unique_small_grid_id", "year", "month", "relative_monthyear"]
    data = pd.read_csv(
        require(intermediate / f"combined_dt_pop{sample}.csv"),
        usecols=use,
        low_memory=False,
    )
    data = merge_rural(data, intermediate, rural_var)
    # All grid histories are retained. The former grids_with_more_1_ac exclusion
    # is intentionally not part of the current analysis sample.
    data = data.loc[(data.year < 2022) | ((data.year == 2022) & (data.month <= 8))]
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
    del sample  # The election panel is the canonical AC-level input.
    use = ["ac_uq_id", "year", "month", "self_profession"]
    data = pd.read_stata(
        require(intermediate / "panel_data_election_year.dta"),
        columns=use,
        convert_categoricals=False,
    )
    if data.duplicated(["ac_uq_id", "year", "month"]).any():
        raise ValueError("Election panel is not unique by AC-year-month")
    observed = set(data["self_profession"].dropna().unique())
    if not observed.issubset({0, 1}):
        raise ValueError(f"Unexpected self_profession values: {sorted(observed)}")
    data["self_profession_nomiss"] = data["self_profession"].fillna(0).astype(int)
    data["date"] = pd.to_datetime(dict(year=data.year, month=data.month, day=1))
    data = data.loc[data["date"].between("2012-09-01", "2022-08-01")].copy()
    expected_dates = pd.date_range("2012-09-01", "2022-08-01", freq="MS")
    observed_dates = pd.DatetimeIndex(sorted(data["date"].unique()))
    if not observed_dates.equals(expected_dates):
        missing = expected_dates.difference(observed_dates).strftime("%Y-%m").tolist()
        raise ValueError(f"AC panel does not cover all 120 required months; missing={missing}")
    wide = data.pivot(
        index="ac_uq_id", columns="date", values="self_profession_nomiss"
    ).fillna(0).sort_index().sort_index(axis=1)

    # Group ACs by the first month in which an agricultural politician is
    # observed. Earlier-switching cohorts appear first and never-treated ACs
    # appear last; AC id breaks ties reproducibly within each cohort.
    first_treated = wide.apply(
        lambda row: row.index[row.eq(1)][0] if row.eq(1).any() else pd.NaT,
        axis=1,
    )
    cohort_label = first_treated.dt.strftime("%Y-%m").fillna("Never treated")
    ordering = pd.DataFrame(
        {
            "first_treated": first_treated.fillna(pd.Timestamp.max),
            "ac_sort": wide.index,
        },
        index=wide.index,
    ).sort_values(["first_treated", "ac_sort"])
    wide = wide.loc[ordering.index]
    cohort_label = cohort_label.loc[ordering.index]
    cohort_runs = cohort_label.ne(cohort_label.shift()).cumsum()
    cohort_groups = cohort_label.groupby(cohort_runs, sort=False)
    cohort_names = cohort_groups.first().tolist()
    cohort_sizes = cohort_groups.size().to_numpy()
    cohort_ends = np.cumsum(cohort_sizes)
    cohort_starts = np.r_[0, cohort_ends[:-1]]
    cohort_midpoints = (cohort_starts + cohort_ends - 1) / 2
    matrix = wide.to_numpy(float)
    # Keep the raster within Matplotlib's pixel limits for the full grid panel.
    height = min(40, max(6, matrix.shape[0] * 0.02))
    width = min(24, max(10, matrix.shape[1] * 0.06))
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
    ax.set_xticks(
        xidx,
        [wide.columns[index].strftime("%Y-%m") for index in xidx],
        rotation=45,
        ha="right",
    )
    ax.set_yticks(
        cohort_midpoints,
        [f"{name} (n={size})" for name, size in zip(cohort_names, cohort_sizes)],
        fontsize=8,
    )
    for boundary in cohort_ends[:-1] - 0.5:
        ax.axhline(boundary, color="white", linewidth=1.2)
    ax.set_xlabel("Month-Year")
    ax.set_ylabel("First agricultural-politician month")
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
    options = parse_args()
    intermediate = options.root / "data_output" / "intermediate"
    figures = options.output_root / "figures"
    figures.mkdir(parents=True, exist_ok=True)
    if options.only == "all":
        monthly_figures(intermediate, figures, options.sample, options.rural_var)
        relative_time_histogram(intermediate, figures, options.sample, options.rural_var)
    politician_panel(intermediate, figures, options.sample)
    if options.only == "panelview":
        print("Generated AC-level politician panel-view figure.")
    else:
        print("Generated monthly, relative-time, and politician panel-view figures.")


if __name__ == "__main__":
    main()

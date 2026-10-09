#!/usr/bin/env python3
"""Event-time density histograms over the stacked population panel.

This rebuilds the appendix figure that main_v2.tex and main_v3.tex include as
downup_evtime_hist_new.png, which until now existed only in
code/figure_app_new.ipynb on one machine's Dropbox, with the project root
hard-coded. Nothing in the repository produced it, so the figure in the paper
could not be regenerated or checked. The paths now follow the same
--root/--output-root contract as generate_design_maps.py.

What is counted
---------------
One row of combined_dt_pop is a grid x month x COHORT, so a grid-month that
falls inside several cohort windows is counted once per cohort. That is what
makes this a stacked density rather than a raw panel count, and it is the point
of the figure: it shows how much weight each event time actually carries.

Filters follow _replication_package/density_figures.ipynb:

1. is_rural == 1, rural grids only
2. dpl_ac != 1, dropping grids that straddle more than one constituency
3. year < 2022 or (year == 2022 and month <= 8), the September-August fire year

Treated twin
------------
Each figure is produced twice in a single streaming pass: once over the whole
sample and once over treated units alone (treat == 1). Reading the 5 GB panel
twice to get the second one would be the obvious waste, so both counters are
accumulated side by side. The treated series is the one that says how much
identifying variation sits at each event time; the pooled series is dominated
by controls and understates how thin the tails are.

The two are plotted on independent y-axes because the treated count is roughly
an order of magnitude smaller; bar heights are comparable within a figure, not
across the pair.
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

COLUMNS = ["unique_small_grid_id", "month", "year", "relative_monthyear", "treat"]
PLOT_STYLE = {
    "font.family": "serif",
    "font.size": 12,
    "axes.linewidth": 0.8,
    "xtick.direction": "out",
    "ytick.direction": "out",
}
X_LABEL = "Relative Time periods from Treatment"
Y_LABEL = "Density of Observations per period"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--sample", default="")
    parser.add_argument(
        "--stacked",
        type=Path,
        help="Override the panel; defaults to INTERMEDIATE/combined_dt_pop<sample>.dta "
        "falling back to the .csv.",
    )
    parser.add_argument(
        "--figures-dir",
        type=Path,
        help="Override the figure directory; defaults to OUTPUT_ROOT/figures.",
    )
    parser.add_argument(
        "--stem",
        default="downup_evtime_hist_new",
        help="Figure stem. The default is the name the paper already includes.",
    )
    parser.add_argument("--window", type=int, default=50)
    parser.add_argument("--bin-width", type=int, default=5)
    parser.add_argument("--chunk-rows", type=int, default=2_000_000)
    args = parser.parse_args()
    if args.window <= 0 or args.bin_width <= 0 or args.chunk_rows <= 0:
        parser.error("--window, --bin-width and --chunk-rows must be positive")
    return args


def require(path: Path) -> Path:
    if not path.exists():
        raise FileNotFoundError(f"Required input does not exist: {path}")
    return path


def resolve_stacked(intermediate: Path, sample: str, override: Path | None) -> Path:
    if override:
        return require(override)
    candidates = [
        intermediate / f"combined_dt_pop{sample}.dta",
        intermediate / f"combined_dt_pop{sample}.csv",
    ]
    path = next((candidate for candidate in candidates if candidate.exists()), None)
    if path is None:
        raise FileNotFoundError(
            "combined_dt_pop was not found as .dta or .csv in " + str(intermediate)
        )
    return path


def panel_columns(path: Path) -> list[str]:
    """Column names only, without reading the file.

    StataReader.varlist is not public API and is absent in some pandas
    versions, so the header comes from a one-row chunk instead.
    """

    if path.suffix.lower() == ".dta":
        with pd.read_stata(path, chunksize=1) as reader:
            return list(next(iter(reader)).columns)
    return list(pd.read_csv(path, nrows=0).columns)


def preflight(intermediate: Path, stacked: Path) -> None:
    """Name every missing input before reading five gigabytes of panel.

    Without this the job dies in under a minute with a bare FileNotFoundError
    or a KeyError from deep inside the Stata reader, which says nothing about
    which file or column was at fault.
    """

    needed = {
        "stacked panel": stacked,
        "rural classification": intermediate / "ghs_grid_classification_2000.dta",
        "multi-AC grids": intermediate / "grids_with_more_1_ac.dta",
    }
    missing = {label: path for label, path in needed.items() if not path.exists()}
    for label, path in needed.items():
        mark = "MISSING" if label in missing else f"{path.stat().st_size / 1e9:.2f} GB"
        print(f"  {label:24s} {mark:>10}  {path}")
    if missing:
        raise FileNotFoundError(
            "Inputs not found: "
            + "; ".join(f"{label} at {path}" for label, path in missing.items())
        )

    available = panel_columns(stacked)
    absent = [column for column in COLUMNS if column not in available]
    if absent:
        raise ValueError(
            f"{stacked.name} is missing {', '.join(absent)}. "
            f"It has {len(available)} columns: {', '.join(sorted(available))}"
        )
    print(f"  panel columns: {len(available)}, all {len(COLUMNS)} needed ones present")


def grid_filters(intermediate: Path) -> tuple[set[int], set[int]]:
    """The two filters are grid properties, so they reduce to two id sets."""

    ghs = pd.read_stata(
        require(intermediate / "ghs_grid_classification_2000.dta"),
        columns=["unique_small_grid_id", "is_rural"],
    )
    rural = set(
        ghs.loc[ghs["is_rural"] == 1, "unique_small_grid_id"].astype("int64")
    )

    multi = pd.read_stata(
        require(intermediate / "grids_with_more_1_ac.dta"),
        columns=["unique_small_grid_id", "dpl_ac"],
    )
    straddling = set(
        multi.loc[multi["dpl_ac"] == 1, "unique_small_grid_id"].astype("int64")
    )

    print(f"rural grids kept:       {len(rural):,}")
    print(f"multi-AC grids dropped: {len(straddling):,}")
    return rural, straddling


def chunk_reader(path: Path, chunk_rows: int):
    if path.suffix.lower() == ".dta":
        return pd.read_stata(path, columns=COLUMNS, chunksize=chunk_rows)
    return pd.read_csv(path, usecols=COLUMNS, chunksize=chunk_rows)


def collapse(path: Path, rural: set[int], straddling: set[int], chunk_rows: int):
    """One pass, two counters: the whole sample and the treated units alone."""

    everyone = pd.Series(dtype="int64")
    treated = pd.Series(dtype="int64")
    rows_read = rows_kept = rows_treated = 0
    started = time.time()

    reader = chunk_reader(path, chunk_rows)
    context = reader if hasattr(reader, "__enter__") else None
    iterator = context.__enter__() if context else reader
    try:
        for index, chunk in enumerate(iterator, start=1):
            rows_read += len(chunk)
            grid_id = chunk["unique_small_grid_id"].astype("int64")
            keep = (
                grid_id.isin(rural)
                & ~grid_id.isin(straddling)
                & (
                    (chunk["year"] < 2022)
                    | ((chunk["year"] == 2022) & (chunk["month"] <= 8))
                )
            )

            kept = chunk.loc[keep]
            treat = kept["treat"].astype("int64")
            if not treat.isin((0, 1)).all():
                raise ValueError("treat is not 0/1 in the stacked panel.")

            event_time = kept["relative_monthyear"].astype("int64")
            rows_kept += len(event_time)
            everyone = everyone.add(event_time.value_counts(), fill_value=0)

            treated_time = event_time[treat.eq(1).to_numpy()]
            rows_treated += len(treated_time)
            treated = treated.add(treated_time.value_counts(), fill_value=0)

            print(
                f"  chunk {index}: {rows_read:,} read / {rows_kept:,} kept "
                f"/ {rows_treated:,} treated  ({time.time() - started:.0f}s)",
                flush=True,
            )
    finally:
        if context:
            context.__exit__(None, None, None)

    print(
        f"\nrows read: {rows_read:,}   kept: {rows_kept:,} "
        f"({rows_kept / rows_read:.1%})   treated: {rows_treated:,} "
        f"({rows_treated / rows_kept:.1%} of kept)"
    )
    return tidy(everyone), tidy(treated)


def tidy(totals: pd.Series) -> pd.DataFrame:
    return (
        totals.astype("int64")
        .rename("n_obs")
        .rename_axis("relative_monthyear")
        .sort_index()
        .reset_index()
    )


def plot(counts: pd.DataFrame, path: Path, bin_width: int, window: int | None) -> None:
    frame = counts
    if window is not None:
        frame = counts[counts["relative_monthyear"].abs() <= window]
        share = frame["n_obs"].sum() / counts["n_obs"].sum()
        print(
            f"  within +/-{window} months: {frame['n_obs'].sum():,} "
            f"({share:.1%} of the series)"
        )
        edge = window
    else:
        edge = int(
            max(
                abs(frame["relative_monthyear"].min()),
                abs(frame["relative_monthyear"].max()),
            )
        )

    plt.rcParams.update(PLOT_STYLE)
    plt.figure(figsize=(8, 5))
    bins = np.arange(-edge, edge + bin_width, bin_width)
    # Weighted histogram: each event time carries its own observation count.
    plt.hist(
        frame["relative_monthyear"],
        bins=bins,
        weights=frame["n_obs"] / 1000,
        color="gray",
        edgecolor="black",
        alpha=0.8,
    )
    plt.xlabel(X_LABEL)
    plt.ylabel(Y_LABEL)
    if window is not None:
        plt.xlim(-window, window)
    plt.grid(alpha=0.3, axis="y")
    plt.tight_layout()
    plt.savefig(path, dpi=300)
    plt.close()
    print(f"  wrote {path}")


def describe(counts: pd.DataFrame, label: str) -> None:
    if counts.empty:
        raise ValueError(f"The {label} series is empty; check the filters.")
    low = counts["relative_monthyear"].min()
    high = counts["relative_monthyear"].max()
    print(
        f"{label}: {counts['n_obs'].sum():,} observations over "
        f"{len(counts)} event times, {low} .. {high}"
    )


def main() -> None:
    options = parse_args()
    intermediate = options.root / "data_output" / "intermediate"
    figures = options.figures_dir or (options.output_root / "figures")
    figures.mkdir(parents=True, exist_ok=True)

    stacked = resolve_stacked(intermediate, options.sample, options.stacked)
    print("Inputs:")
    preflight(intermediate, stacked)

    rural, straddling = grid_filters(intermediate)
    everyone, treated = collapse(
        stacked, rural, straddling, options.chunk_rows
    )

    describe(everyone, "All units")
    describe(treated, "Treated units")

    stem = options.stem
    for counts, suffix, label in (
        (everyone, "", "all units"),
        (treated, "_treated", "treated units"),
    ):
        # The aggregated series behind each figure, written out so the figure
        # can be rebuilt or audited without re-reading the panel.
        counts_path = intermediate / f"rtime_abs_nobs_rebuilt{suffix}{options.sample}.csv"
        counts.to_csv(counts_path, index=False)
        print(f"{label}: wrote {counts_path}")
        plot(counts, figures / f"{stem}{suffix}.png", options.bin_width, None)
        plot(
            counts,
            figures / f"{stem}{suffix}_zoom.png",
            options.bin_width,
            options.window,
        )


if __name__ == "__main__":
    main()

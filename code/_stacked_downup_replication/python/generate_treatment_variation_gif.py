#!/usr/bin/env python3
"""Animate month-by-month treatment assignment as treatment_variation_2012_2022.gif.

This figure previously existed only in cells 82 and 83 of code/_app_maps_acs.ipynb,
with the project root hard-coded to one collaborator's Dropbox, so it could not
be rebuilt by anyone else or on the cluster. The logic is unchanged apart from
the framing described below; the paths now follow the same --root/--output-root
contract as generate_design_maps.py.

Framing
-------
The notebook set the extent from ``grid.total_bounds``, which spans the whole
158,775-cell grid rather than the roughly 100,254 cells that are actually drawn,
and then forced that into a square 8x8 figure. With an equal aspect ratio the
remainder became white margin, leaving the map covering 513x440 of an 880x880
frame -- 29% of the area, and about two pixels per grid cell.

Here the extent comes from the union of the grids that appear in any month, and
the axes box is given that extent's aspect ratio across the full figure width,
with a strip reserved on top for the month label. The extent is still fixed
across the animation, so nothing shifts from frame to frame.

Memory
------
0_master_merge_data_gen.csv is around 9 GB, so it is read in chunks and only
the four columns the animation needs are kept.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import geopandas as gpd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
from PIL import Image

TREATMENT_COLUMN = "downup_ac_pop"
COLOR = {0: "#CCCCCC", 1: "#8B0000"}
MONTHS = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]
COLUMNS = ["year", "month", "unique_small_grid_id", TREATMENT_COLUMN]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--sample", default="")
    parser.add_argument(
        "--shared-root",
        type=Path,
        help="sa_fires root containing data/input and proj_downwind (defaults to root parent)",
    )
    parser.add_argument(
        "--master",
        type=Path,
        help="Override the panel; defaults to INTERMEDIATE/0_master_merge_data_gen<sample>.csv.",
    )
    parser.add_argument("--start-year", type=int, default=2012)
    parser.add_argument("--start-month", type=int, default=9)
    parser.add_argument("--end-year", type=int, default=2022)
    parser.add_argument("--end-month", type=int, default=8)
    parser.add_argument(
        "--width-inches",
        type=float,
        default=10.0,
        help="Figure width; the map spans all of it.",
    )
    parser.add_argument("--dpi", type=int, default=100)
    parser.add_argument("--duration-ms", type=int, default=1000)
    parser.add_argument("--chunk-rows", type=int, default=2_000_000)
    parser.add_argument(
        "--keep-frames",
        action="store_true",
        default=True,
        help="Keep the per-month PNGs beside the GIF (default).",
    )
    args = parser.parse_args()
    for name in ("start_month", "end_month"):
        if not 1 <= getattr(args, name) <= 12:
            parser.error(f"--{name.replace('_', '-')} must be between 1 and 12")
    if args.width_inches <= 0 or args.dpi <= 0:
        parser.error("--width-inches and --dpi must be positive")
    return args


def require(path: Path) -> Path:
    if not path.exists():
        raise FileNotFoundError(f"Required input does not exist: {path}")
    return path


def read_grid(root: Path, shared: Path) -> gpd.GeoDataFrame:
    """Same two candidate locations generate_design_maps.py accepts."""

    intermediate = root / "data_output" / "intermediate"
    candidates = [
        intermediate / "1-grid-generation.shp",
        shared / "proj_downwind" / "data_output" / "intermediate" / "1-grid-generation.shp",
    ]
    path = next((candidate for candidate in candidates if candidate.exists()), None)
    if path is None:
        raise FileNotFoundError(
            "1-grid-generation.shp was not found in either supported folder"
        )
    grid = gpd.read_file(path)
    if "unq_s__" in grid:
        grid = grid.rename(columns={"unq_s__": "unique_small_grid_id"})
    return grid


def read_panel(master: Path, start: int, end: int, chunk_rows: int) -> pd.DataFrame:
    """Keep the four needed columns for the months inside the window."""

    kept: list[pd.DataFrame] = []
    rows_seen = 0
    if master.suffix.lower() == ".parquet":
        frame = pd.read_parquet(master, columns=COLUMNS)
        rows_seen = len(frame)
        stamp = frame["year"].astype("int64") * 12 + frame["month"].astype("int64")
        kept.append(frame[(stamp >= start) & (stamp <= end)])
    else:
        reader = pd.read_csv(
            master,
            usecols=COLUMNS,
            chunksize=chunk_rows,
            dtype={"year": "int16", "month": "int8", TREATMENT_COLUMN: "float32"},
        )
        for chunk in reader:
            rows_seen += len(chunk)
            stamp = chunk["year"].astype("int64") * 12 + chunk["month"].astype("int64")
            part = chunk[(stamp >= start) & (stamp <= end)]
            if len(part):
                kept.append(part)

    panel = pd.concat(kept, ignore_index=True)
    missing = int(panel[TREATMENT_COLUMN].isna().sum())
    if missing:
        raise ValueError(f"{missing:,} rows have a missing {TREATMENT_COLUMN}.")
    print(f"Read {rows_seen:,} rows; {len(panel):,} inside the window")
    return panel


def main() -> None:
    options = parse_args()
    shared = options.shared_root or options.root.parent
    figures = options.output_root / "figures"
    frames_dir = figures / "gif_frames"
    figures.mkdir(parents=True, exist_ok=True)
    frames_dir.mkdir(parents=True, exist_ok=True)

    intermediate = options.root / "data_output" / "intermediate"
    master = options.master or (
        intermediate / f"0_master_merge_data_gen{options.sample}.csv"
    )
    require(master)

    start = options.start_year * 12 + options.start_month
    end = options.end_year * 12 + options.end_month

    grid = read_grid(options.root, shared)
    panel = read_panel(master, start, end, options.chunk_rows)
    print(f"Grid: {len(grid):,} cells; panel: {panel['unique_small_grid_id'].nunique():,} drawn")

    geometry = grid[["unique_small_grid_id", "geometry"]]
    drawn = grid[grid["unique_small_grid_id"].isin(panel["unique_small_grid_id"].unique())]
    if drawn.empty:
        raise ValueError("No grid in the shapefile matched the panel; check the id column.")

    minx, miny, maxx, maxy = drawn.total_bounds
    dx, dy = maxx - minx, maxy - miny
    margin = 0.01
    minx, maxx = minx - margin * dx, maxx + margin * dx
    miny, maxy = miny - margin * dy, maxy + margin * dy
    dx, dy = maxx - minx, maxy - miny

    axes_height = options.width_inches * dy / dx
    title_strip = 0.62
    fig_w = options.width_inches
    fig_h = axes_height + title_strip
    print(
        f"Extent {dx:.4f} x {dy:.4f}; frame "
        f"{round(fig_w * options.dpi)} x {round(fig_h * options.dpi)} px"
    )

    months = panel[["year", "month"]].drop_duplicates().sort_values(["year", "month"])
    frame_paths: list[Path] = []
    for year, month in months.itertuples(index=False):
        subset = panel[(panel["year"] == year) & (panel["month"] == month)][
            ["unique_small_grid_id", TREATMENT_COLUMN]
        ]
        merged = subset.merge(geometry, on="unique_small_grid_id")   # inner merge
        merged = gpd.GeoDataFrame(merged, geometry="geometry", crs=grid.crs)
        merged["plot_color"] = merged[TREATMENT_COLUMN].astype("int8").map(COLOR)
        if merged["plot_color"].isna().any():
            raise ValueError(
                f"{TREATMENT_COLUMN} is outside (0, 1) in {MONTHS[month - 1]} {year}."
            )

        fig = plt.figure(figsize=(fig_w, fig_h))
        ax = fig.add_axes([0.0, 0.0, 1.0, axes_height / fig_h])
        merged.plot(ax=ax, color=merged["plot_color"], edgecolor="none",
                    linewidth=0, antialiased=False)
        ax.set_xlim(minx, maxx)
        ax.set_ylim(miny, maxy)
        ax.set_title(f"{MONTHS[month - 1]} {year}", fontsize=20)
        ax.set_axis_off()

        path = frames_dir / f"frame_{year}_{month:02d}.png"
        # No bbox_inches: trimming per frame would resize them independently.
        fig.savefig(path, dpi=options.dpi)
        plt.close(fig)
        frame_paths.append(path)
        print(f"  {MONTHS[month - 1]} {year}: {len(merged):,} grids", flush=True)

    sizes = {Image.open(path).size for path in frame_paths}
    if len(sizes) != 1:
        raise ValueError(f"Frame sizes are not constant: {sizes}")

    frames = [
        Image.open(path).convert("RGB").quantize(method=Image.MEDIANCUT)
        for path in frame_paths
    ]
    output = figures / "treatment_variation_2012_2022.gif"
    frames[0].save(
        output,
        save_all=True,
        append_images=frames[1:],
        duration=options.duration_ms,
        loop=0,          # forever
        disposal=2,      # clear each frame, so nothing ghosts through
        optimize=False,
    )
    print(
        f"Generated {output} - {len(frames)} frames of {sizes.pop()} px, "
        f"{options.duration_ms} ms each, {output.stat().st_size / 1e6:.1f} MB"
    )

    if not options.keep_frames:
        for path in frame_paths:
            path.unlink()
        frames_dir.rmdir()


if __name__ == "__main__":
    main()

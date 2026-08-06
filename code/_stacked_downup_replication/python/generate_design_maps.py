#!/usr/bin/env python3
"""Generate the active design maps formerly spread across notebooks."""

from __future__ import annotations

import argparse
from pathlib import Path

import geopandas as gpd
import matplotlib.image as mpimg
import matplotlib.offsetbox as offsetbox
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, Rectangle
import numpy as np
import pandas as pd
from shapely.geometry import LineString, Point, Polygon


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--sample", default="")
    parser.add_argument(
        "--shared-root",
        type=Path,
        help="sa_fires root containing data/input and proj_downwind (defaults to root parent)",
    )
    return parser.parse_args()


def require(path: Path) -> Path:
    if not path.exists():
        raise FileNotFoundError(f"Required input does not exist: {path}")
    return path


def read_inputs(root: Path, shared: Path, sample: str):
    intermediate = root / "data_output" / "intermediate"
    data = pd.read_csv(
        require(intermediate / f"0_master_dataset{sample}.csv"),
        usecols=["unique_small_grid_id", "ac_uq_id", "year", "month", "downup_ac_pop"],
        low_memory=False,
    )
    grid_candidates = [
        intermediate / "1-grid-generation.shp",
        shared / "proj_downwind" / "data_output" / "intermediate" / "1-grid-generation.shp",
    ]
    grid_path = next((path for path in grid_candidates if path.exists()), None)
    if grid_path is None:
        raise FileNotFoundError("1-grid-generation.shp was not found in either supported folder")
    grid = gpd.read_file(grid_path)
    if "unq_s__" in grid:
        grid = grid.rename(columns={"unq_s__": "unique_small_grid_id"})
    acs = gpd.read_file(require(intermediate / "_0_2_3_ACs_right_shapefile.shp"))
    boundary_candidates = [
        root / "data" / "input" / "ac_boundaries" / "Constituencies_Boundaries_Post_2008.shp",
        shared / "data" / "input" / "ac_boundaries" / "Constituencies_Boundaries_Post_2008.shp",
    ]
    boundary_path = next((path for path in boundary_candidates if path.exists()), None)
    if boundary_path is None:
        raise FileNotFoundError("Constituencies_Boundaries_Post_2008.shp was not found")
    return intermediate, data, grid, acs, gpd.read_file(boundary_path)


def map_grids(figures: Path, grid: gpd.GeoDataFrame, acs: gpd.GeoDataFrame,
              boundaries: gpd.GeoDataFrame) -> None:
    selected_ac = acs.loc[acs.ac_uq_id.eq(780)]
    if selected_ac.empty:
        raise ValueError("AC 780, used by the original map, is absent")
    states = boundaries.loc[
        boundaries.STATE_UT.isin(["PUNJAB", "HARYANA", "UTTAR PRADESH", "BIHAR"])
    ]
    xmin, ymin, xmax, ymax = states.total_bounds
    fig, ax = plt.subplots(figsize=(30, 30))
    states.plot(ax=ax, color="#AFE1AF", edgecolor=None)
    boundaries.boundary.plot(ax=ax, color="#336ece")
    ax.set(xlim=(xmin - 1, xmax + 1), ylim=(ymin - 1, ymax + 1))
    ax.axis("off")
    inset = fig.add_axes([0.6, 0.45, 0.3, 0.3])
    boundaries.plot(ax=inset, color="#AFE1AF", edgecolor="black")
    boundaries.boundary.plot(ax=inset, color="#336ece", linewidth=0.5)
    grid.plot(ax=inset, facecolor="none", edgecolor="black", linewidth=0.1)
    ixmin, iymin, ixmax, iymax = selected_ac.total_bounds
    inset.set(xlim=(ixmin - 0.1, ixmax + 0.1), ylim=(iymin - 0.02, iymax + 0.02))
    inset.axis("off")
    inset.add_patch(Rectangle((0, 0), 1, 1, transform=inset.transAxes,
                              fill=False, color="red", lw=5))
    center = selected_ac.geometry.centroid.iloc[0]
    ax.add_patch(FancyArrowPatch(
        (center.x, center.y), (center.x + 5.4, center.y + 2.2),
        color="red", arrowstyle="->", lw=3, zorder=10,
    ))
    fig.savefig(figures / "map_grids.png", dpi=300, bbox_inches="tight")
    plt.close(fig)


def radius_map(figures: Path, data: pd.DataFrame, grid: gpd.GeoDataFrame,
               acs: gpd.GeoDataFrame) -> None:
    ac_id = 61
    ids = data.loc[
        data.ac_uq_id.eq(ac_id) & data.year.eq(2020) & data.month.eq(12),
        "unique_small_grid_id",
    ].drop_duplicates()
    selected = gpd.GeoDataFrame(
        pd.DataFrame({"unique_small_grid_id": ids}).merge(grid),
        geometry="geometry",
        crs=grid.crs,
    )
    focus = selected.loc[selected.unique_small_grid_id.eq(7334)]
    if focus.empty:
        raise ValueError("Grid 7334, used by the original 12 km map, is absent")
    center = focus.geometry.centroid.to_crs(7755)
    buffer = center.buffer(12_000).to_crs(selected.crs)
    fig, ax = plt.subplots(figsize=(10, 8))
    selected.plot(ax=ax, edgecolor="black", facecolor="none")
    acs.loc[acs.ac_uq_id.eq(ac_id)].boundary.plot(ax=ax, edgecolor="black")
    buffer.boundary.plot(ax=ax, edgecolor="black", linewidth=1)
    center.to_crs(selected.crs).plot(ax=ax, color="black", marker="s", markersize=40)
    ax.axis("off")
    fig.tight_layout()
    fig.savefig(figures / "acs_grids_radius12km.png", dpi=300, bbox_inches="tight")
    plt.close(fig)


def time_map(data: pd.DataFrame, grid: gpd.GeoDataFrame, figures: Path,
             month: int, title: str, filename: str) -> None:
    values = data.loc[
        data.year.eq(2013) & data.month.eq(month),
        ["unique_small_grid_id", "downup_ac_pop"],
    ].drop_duplicates("unique_small_grid_id")
    mapped = gpd.GeoDataFrame(values.merge(grid), geometry="geometry", crs=grid.crs)
    mapped["plot_color"] = mapped.downup_ac_pop.map({0: "#8FC6FA", 1: "#032544"})
    fig, ax = plt.subplots(figsize=(8, 8))
    mapped.plot(ax=ax, color=mapped.plot_color, edgecolor="none", linewidth=0,
                antialiased=False)
    ax.set_title(title)
    ax.axis("off")
    fig.savefig(figures / filename, dpi=300, bbox_inches="tight")
    plt.close(fig)


def make_line(center: Point, bounds) -> LineString:
    xmin, ymin, xmax, ymax = bounds
    length = max(xmax - xmin, ymax - ymin) * 2
    return LineString([
        (center.x - length / 2, center.y - length / 2),
        (center.x + length / 2, center.y + length / 2),
    ])


def halfplane(line: LineString, below: bool) -> Polygon:
    (x1, y1), (x2, y2) = line.coords[0], line.coords[-1]
    normal = np.array([-(y2 - y1), x2 - x1], float)
    normal /= np.linalg.norm(normal)
    if below:
        normal *= -1
    scale = (max(abs(x1), abs(y1), abs(x2), abs(y2)) + 1) * 50
    p1, p2 = np.array([x1, y1]), np.array([x2, y2])
    return Polygon([p1, p2, p2 + normal * scale, p1 + normal * scale]).buffer(0)


def sample_region(region, count: int, rng: np.random.Generator) -> np.ndarray:
    if region.is_empty or region.area <= 0:
        raise ValueError("Treatment-panel population target is infeasible")
    minx, miny, maxx, maxy = region.bounds
    points: list[tuple[float, float]] = []
    attempts = 0
    while len(points) < count and attempts < 200_000:
        point = Point(rng.uniform(minx, maxx), rng.uniform(miny, maxy))
        if region.contains(point):
            points.append((point.x, point.y))
        attempts += 1
    if len(points) != count:
        raise RuntimeError("Could not place the fixed treatment-panel population")
    return np.asarray(points)


def treatment_panels(intermediate: Path, shared: Path, figures: Path,
                     data: pd.DataFrame, grid: gpd.GeoDataFrame,
                     acs: gpd.GeoDataFrame) -> None:
    ids = data.loc[
        data.ac_uq_id.eq(61) & data.year.eq(2020) & data.month.eq(12),
        "unique_small_grid_id",
    ].drop_duplicates()
    cells = gpd.GeoDataFrame(
        pd.DataFrame({"unique_small_grid_id": ids}).merge(grid),
        geometry="geometry",
        crs=grid.crs,
    )
    boundary = acs.loc[acs.ac_uq_id.eq(780)]
    fire_a = cells.loc[cells.unique_small_grid_id.eq(42175)]
    fire_b = cells.loc[cells.unique_small_grid_id.eq(39875)]
    if boundary.empty or fire_a.empty or fire_b.empty:
        raise ValueError("Original treatment-panel AC/fire-grid IDs are absent")
    center_a = fire_a.geometry.centroid.iloc[0]
    center_b = fire_b.geometry.centroid.iloc[0]
    line_a = make_line(center_a, boundary.total_bounds)
    line_b = make_line(center_b, boundary.total_bounds)
    a_below = halfplane(line_a, True)
    b_below = halfplane(line_b, True)
    universe = cells.geometry.union_all() if hasattr(cells.geometry, "union_all") else cells.geometry.unary_union
    rng = np.random.default_rng(11)
    both = sample_region(universe.intersection(a_below).intersection(b_below), 10, rng)
    between = sample_region(universe.intersection(a_below).difference(b_below), 3, rng)
    above = sample_region(universe.difference(a_below.union(b_below)), 4, rng)
    population = np.vstack([both, between, above])
    flags_a = np.array([True] * 13 + [False] * 4)
    flags_b = np.array([True] * 10 + [False] * 7)
    fire_candidates = [
        intermediate / "fire.png",
        shared / "proj_downwind" / "tex" / "paper" / "figures" / "fire.png",
    ]
    fire_path = next((path for path in fire_candidates if path.exists()), None)
    if fire_path is None:
        raise FileNotFoundError("fire.png was not found")
    fire_icon = mpimg.imread(fire_path)

    def plot(line, center, below, flags, filename):
        down = halfplane(line, below)
        shade = cells.geometry.apply(
            lambda geometry: geometry.intersection(down).area / geometry.area > 0.5
            if geometry.area else False
        )
        fig, ax = plt.subplots(figsize=(10, 10))
        cells.boundary.plot(ax=ax, color="black", linewidth=0.3)
        cells.loc[shade].plot(ax=ax, color="pink", alpha=0.6, antialiased=False)
        boundary.boundary.plot(ax=ax, color="blue", linewidth=1.5)
        ax.scatter(population[flags, 0], population[flags, 1], s=130, color="black",
                   edgecolor="white", linewidth=0.7, zorder=8)
        ax.scatter(population[~flags, 0], population[~flags, 1], s=130,
                   facecolor="white", edgecolor="black", linewidth=2.1, zorder=8)
        icon = offsetbox.OffsetImage(fire_icon, zoom=0.015)
        ax.add_artist(offsetbox.AnnotationBbox(icon, (center.x, center.y + 0.005), frameon=False))
        (x1, y1), (x2, y2) = line.coords[0], line.coords[-1]
        normal = np.array([-(y2 - y1), x2 - x1], float)
        normal /= np.linalg.norm(normal)
        if below:
            normal *= -1
        span = max(boundary.total_bounds[2:] - boundary.total_bounds[:2])
        head = np.array([center.x, center.y])
        tail = head - normal * span * 0.12
        ax.add_patch(FancyArrowPatch(tail, head, arrowstyle="-|>", color="blue",
                                     lw=4, mutation_scale=22))
        ax.axis("off")
        fig.savefig(figures / filename, dpi=300, bbox_inches="tight")
        plt.close(fig)

    plot(line_a, center_a, True, flags_a, "panel_A_downwind.png")
    plot(line_b, center_b, True, flags_b, "panel_B_downwind.png")
    plot(line_b, center_b, False, ~flags_b, "panel_C_upwind.png")


def main() -> None:
    options = parse_args()
    shared = options.shared_root or options.root.parent
    figures = options.root / "tex" / "paper" / "figures"
    figures.mkdir(parents=True, exist_ok=True)
    intermediate, data, grid, acs, boundaries = read_inputs(
        options.root, shared, options.sample
    )
    map_grids(figures, grid, acs, boundaries)
    radius_map(figures, data, grid, acs)
    time_map(data, grid, figures, 3, "March 2013", "march2013_plot.png")
    time_map(data, grid, figures, 10, "October 2013", "october2013_plot.png")
    treatment_panels(intermediate, shared, figures, data, grid, acs)
    print("Generated active design maps and treatment-illustration panels.")


if __name__ == "__main__":
    main()

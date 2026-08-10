"""Generate the six map panels used by the paper.

This consolidates the relevant code from ``32_Map_population.ipynb`` and
``_app_maps_acs.ipynb``.  AC membership is read from the new master parquet
and validated against the right-hand AC shapefile; it is not hard-coded.

Outputs
-------
panel_A_downwind.png, panel_B_downwind.png, panel_C_upwind.png,
march2013_plot.png, october2013_plot.png, map_grids.png
"""

# %% Imports and paths
from __future__ import annotations

import argparse
from pathlib import Path

import geopandas as gpd
import matplotlib.image as mpimg
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.patches import FancyArrowPatch, Rectangle
from shapely.geometry import LineString, Polygon


DEFAULT_PROJECT = Path(
    r"C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms"
)
DEFAULT_MASTER = DEFAULT_PROJECT / "data_output/intermediate/0_master_dataset.parquet"
DEFAULT_ACS = DEFAULT_PROJECT / "data_output/intermediate/_0_2_3_ACs_right_shapefile.shp"
DEFAULT_GRID = DEFAULT_PROJECT / "data_output/intermediate/1-grid-generation.shp"
DEFAULT_OUTPUT = Path(r"C:\Users\eunic\OneDrive\Documents\GitHub\proj_bureaucrats_farms\figures")
DEFAULT_FIRE = (
    DEFAULT_PROJECT.parent / "proj_downwind/tex/paper/figures/fire.png"
)
DEFAULT_GRID_POPULATION = (
    DEFAULT_PROJECT / "data_output/intermediate/small_grid_population_2010.parquet"
)

POPULATION_ANCHORS = (7289, 5818)
MAP_GRID_ANCHORS = (42175, 39875)
PANEL_A_FIRE_GRID = 7289
PANEL_BC_FIRE_GRID = 5818


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--master", type=Path, default=DEFAULT_MASTER)
    parser.add_argument("--acs", type=Path, default=DEFAULT_ACS)
    parser.add_argument("--grid", type=Path, default=DEFAULT_GRID)
    parser.add_argument(
        "--grid-population", type=Path, default=DEFAULT_GRID_POPULATION,
        help="Pixel-derived 2010 population aggregated to each small grid",
    )
    parser.add_argument("--fire-icon", type=Path, default=DEFAULT_FIRE)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def require_files(paths: list[Path]) -> None:
    missing = [str(path) for path in paths if not path.exists()]
    if missing:
        raise FileNotFoundError("Missing required input(s):\n  " + "\n  ".join(missing))


def read_inputs(args: argparse.Namespace) -> tuple[gpd.GeoDataFrame, gpd.GeoDataFrame]:
    require_files([args.master, args.acs, args.grid, args.grid_population, args.fire_icon])

    acs = gpd.read_file(args.acs)
    if "ac_uq_id" not in acs.columns:
        raise KeyError("The AC shapefile must contain ac_uq_id")
    acs["geometry"] = acs.geometry.make_valid()

    grid = gpd.read_file(args.grid)
    if "unique_small_grid_id" not in grid.columns:
        if "unq_s__" not in grid.columns:
            raise KeyError("The grid shapefile needs unique_small_grid_id or unq_s__")
        grid = grid.rename(columns={"unq_s__": "unique_small_grid_id"})
    grid["unique_small_grid_id"] = grid["unique_small_grid_id"].astype("int64")
    grid = grid[["unique_small_grid_id", "geometry"]].drop_duplicates(
        "unique_small_grid_id"
    )
    if grid.crs != acs.crs:
        grid = grid.to_crs(acs.crs)
    return acs, grid


def infer_ac(master: Path, anchor_grid_ids: tuple[int, ...], acs: gpd.GeoDataFrame) -> int:
    """Infer one AC from focal grids in the master and validate the polygon."""
    crosswalk = pd.read_parquet(
        master,
        columns=["unique_small_grid_id", "ac_uq_id"],
        filters=[("unique_small_grid_id", "in", list(anchor_grid_ids))],
    ).drop_duplicates()

    found_ids = set(crosswalk["unique_small_grid_id"].astype(int))
    missing = set(anchor_grid_ids) - found_ids
    if missing:
        raise ValueError(f"Anchor grid(s) absent from master: {sorted(missing)}")

    ac_ids = sorted(crosswalk["ac_uq_id"].dropna().astype(int).unique())
    if len(ac_ids) != 1:
        raise ValueError(
            f"Anchor grids {anchor_grid_ids} do not identify one AC; found {ac_ids}"
        )
    ac_id = ac_ids[0]
    if not acs["ac_uq_id"].astype(int).eq(ac_id).any():
        raise ValueError(f"AC {ac_id} from the master is absent from the shapefile")
    return ac_id


def grids_for_ac(master: Path, grid: gpd.GeoDataFrame, ac_id: int) -> gpd.GeoDataFrame:
    ids = pd.read_parquet(
        master,
        columns=["unique_small_grid_id"],
        filters=[("ac_uq_id", "==", ac_id)],
    ).drop_duplicates()
    out = grid.merge(ids, on="unique_small_grid_id", how="inner", validate="one_to_one")
    if out.empty:
        raise ValueError(f"No grid geometries found for AC {ac_id}")
    return gpd.GeoDataFrame(out, geometry="geometry", crs=grid.crs)


def union_geometry(gdf: gpd.GeoDataFrame):
    return gdf.geometry.union_all() if hasattr(gdf.geometry, "union_all") else gdf.unary_union


# %% Population panels from 32_Map_population.ipynb
def make_45_line(point, bounds: np.ndarray) -> LineString:
    minx, miny, maxx, maxy = bounds
    length = 3 * max(maxx - minx, maxy - miny)
    return LineString(
        [
            (point.x - length, point.y - length),
            (point.x + length, point.y + length),
        ]
    )


def halfplane(line: LineString, side: str, bounds: np.ndarray) -> Polygon:
    """Return a large polygon on the above or below side of a directed line."""
    (x1, y1), (x2, y2) = line.coords[0], line.coords[-1]
    start = np.array([x1, y1], dtype=float)
    end = np.array([x2, y2], dtype=float)
    normal = np.array([-(y2 - y1), x2 - x1], dtype=float)
    normal /= np.linalg.norm(normal)
    if side == "below":
        normal *= -1
    elif side != "above":
        raise ValueError("side must be 'above' or 'below'")
    minx, miny, maxx, maxy = bounds
    distance = 100 * max(maxx - minx, maxy - miny)
    return Polygon([start, end, end + normal * distance, start + normal * distance])


def read_grid_population(path: Path) -> pd.DataFrame:
    population = pd.read_parquet(
        path, columns=["unique_small_grid_id", "population_2010"]
    )
    if population["unique_small_grid_id"].duplicated().any():
        raise ValueError("small_grid_population_2010.parquet has duplicate grid IDs")
    return population


def plot_population_panel(
    selected_grids: gpd.GeoDataFrame,
    selected_polygon: gpd.GeoDataFrame,
    fire_grid_id: int,
    downwind_side: str,
    output_path: Path,
    grid_population: pd.DataFrame,
    fire_icon: Path,
) -> None:
    fire_cell = selected_grids.loc[
        selected_grids["unique_small_grid_id"].eq(fire_grid_id)
    ]
    if len(fire_cell) != 1:
        raise ValueError(f"Expected one fire grid {fire_grid_id}; found {len(fire_cell)}")
    # A single small grid is effectively planar at this scale; using the
    # Shapely geometry directly also avoids GeoPandas' whole-series CRS warning.
    fire_centroid = fire_cell.geometry.iloc[0].centroid
    polygon = union_geometry(selected_polygon)
    line = make_45_line(fire_centroid, selected_polygon.total_bounds)
    down_hp = halfplane(line, downwind_side, selected_polygon.total_bounds)
    down_geom = polygon.intersection(down_hp)
    up_geom = polygon.difference(down_hp)
    split = gpd.GeoDataFrame(
        {"side": ["downwind", "upwind"]},
        geometry=[down_geom, up_geom],
        crs=selected_polygon.crs,
    )
    grid_plot = selected_grids.merge(
        grid_population, on="unique_small_grid_id", how="left", validate="one_to_one"
    )
    if grid_plot["population_2010"].isna().any():
        missing = grid_plot.loc[
            grid_plot["population_2010"].isna(), "unique_small_grid_id"
        ].tolist()
        raise ValueError(f"Population is missing for selected grid(s): {missing[:10]}")
    grid_plot["population_k"] = (grid_plot["population_2010"] / 1_000).round()
    centroid_points = grid_plot.geometry.apply(lambda geometry: geometry.centroid)
    downwind_grid = centroid_points.apply(down_hp.covers)

    fig, ax = plt.subplots(figsize=(8, 6))
    split.loc[split.side.eq("downwind")].plot(ax=ax, color="lightcoral", alpha=0.6)
    split.loc[split.side.eq("upwind")].plot(ax=ax, color="lightblue", alpha=0.6)
    grid_plot.boundary.plot(ax=ax, color="black", linewidth=0.5)
    selected_polygon.boundary.plot(ax=ax, color="black", linewidth=1.5)

    icon = mpimg.imread(fire_icon)
    icon_size = 0.005
    ax.imshow(
        icon,
        extent=[
            fire_centroid.x - icon_size,
            fire_centroid.x + icon_size,
            fire_centroid.y - icon_size,
            fire_centroid.y + icon_size,
        ],
        aspect="auto",
        zorder=9,
    )

    # Arrow points toward the fire from the upwind side.
    direction = np.array([-1.0, 1.0]) if downwind_side == "below" else np.array([1.0, -1.0])
    direction /= np.linalg.norm(direction)
    span = max(
        selected_polygon.total_bounds[2] - selected_polygon.total_bounds[0],
        selected_polygon.total_bounds[3] - selected_polygon.total_bounds[1],
    )
    head = np.array([fire_centroid.x, fire_centroid.y])
    tail = head + direction * span * 0.12
    ax.add_patch(
        FancyArrowPatch(
            posA=tuple(tail), posB=tuple(head), arrowstyle="-|>",
            color="black", mutation_scale=18, linewidth=2, zorder=11,
        )
    )

    for _, row in grid_plot.iterrows():
        point = row.geometry.centroid
        ax.text(
            point.x, point.y, f"{row['population_k']:.0f}", fontsize=7,
            ha="center", va="center", color="black", fontweight="bold", zorder=12,
        )

    down = grid_plot.loc[downwind_grid, "population_2010"].sum() / 1_000
    up = grid_plot.loc[~downwind_grid, "population_2010"].sum() / 1_000
    ax.text(0.50, -0.01, f"{down:,.0f}", transform=ax.transAxes, ha="center",
            va="top", fontsize=22, color="lightcoral", clip_on=False)
    ax.plot([0.46, 0.54], [-0.08, -0.08], transform=ax.transAxes,
            color="black", linewidth=1.5, clip_on=False)
    ax.text(0.50, -0.095, f"{up:,.0f}", transform=ax.transAxes, ha="center",
            va="top", fontsize=22, color="lightblue", clip_on=False)
    ax.set_axis_off()
    fig.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close(fig)


# %% AC and grid overview from _app_maps_acs.ipynb
def plot_map_grids(
    acs: gpd.GeoDataFrame,
    grid: gpd.GeoDataFrame,
    master: Path,
    output_path: Path,
) -> int:
    ac_id = infer_ac(master, MAP_GRID_ANCHORS, acs)
    selected_ac = acs.loc[acs["ac_uq_id"].astype(int).eq(ac_id)].copy()
    selected_grids = grids_for_ac(master, grid, ac_id)
    states = ["PUNJAB", "HARYANA", "UTTAR PRADESH", "BIHAR"]
    study_acs = acs.loc[acs["STATE_UT"].isin(states)].copy()

    fig, ax = plt.subplots(figsize=(10, 10))
    study_acs.plot(ax=ax, color="#AFE1AF", edgecolor="#336ece", linewidth=0.35)
    ax.set_axis_off()

    inset = fig.add_axes([0.59, 0.48, 0.32, 0.32])
    study_acs.boundary.plot(ax=inset, color="#336ece", linewidth=0.25)
    selected_ac.plot(ax=inset, color="#AFE1AF", edgecolor="black", linewidth=1.2)
    selected_grids.boundary.plot(ax=inset, color="black", linewidth=0.15)
    minx, miny, maxx, maxy = selected_ac.total_bounds
    inset.set_xlim(minx - 0.10, maxx + 0.10)
    inset.set_ylim(miny - 0.03, maxy + 0.03)
    inset.set_axis_off()
    inset.add_patch(
        Rectangle((0, 0), 1, 1, transform=inset.transAxes, fill=False,
                  edgecolor="red", linewidth=3, zorder=20)
    )

    centroid = union_geometry(selected_ac).centroid
    ax.add_patch(
        FancyArrowPatch(
            (centroid.x, centroid.y), (centroid.x + 5.0, centroid.y + 2.0),
            color="red", arrowstyle="->", linewidth=2.5,
        )
    )
    fig.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close(fig)
    return ac_id


# %% March and October 2013 treatment maps from _app_maps_acs.ipynb
def plot_month(
    master: Path,
    grid: gpd.GeoDataFrame,
    year: int,
    month: int,
    output_path: Path,
) -> int:
    values = pd.read_parquet(
        master,
        columns=["unique_small_grid_id", "downup_ac_pop"],
        filters=[("year", "==", year), ("month", "==", month)],
    ).drop_duplicates("unique_small_grid_id")
    mapped = grid.merge(values, on="unique_small_grid_id", how="inner", validate="one_to_one")
    mapped = gpd.GeoDataFrame(mapped, geometry="geometry", crs=grid.crs)
    colors = mapped["downup_ac_pop"].map({0: "#8FC6FA", 1: "#032544"})

    fig, ax = plt.subplots(figsize=(8, 8))
    mapped.plot(ax=ax, color=colors, edgecolor="none", linewidth=0, antialiased=False)
    ax.set_title(pd.Timestamp(year=year, month=month, day=1).strftime("%B %Y"))
    ax.set_axis_off()
    fig.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close(fig)
    return len(mapped)


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    acs, grid = read_inputs(args)
    grid_population = read_grid_population(args.grid_population)

    population_ac_id = infer_ac(args.master, POPULATION_ANCHORS, acs)
    population_polygon = acs.loc[
        acs["ac_uq_id"].astype(int).eq(population_ac_id)
    ].copy()
    population_grids = grids_for_ac(args.master, grid, population_ac_id)
    print(
        f"Population panels: AC {population_ac_id}, "
        f"{population_grids['unique_small_grid_id'].nunique()} grids"
    )

    plot_population_panel(
        population_grids, population_polygon, PANEL_A_FIRE_GRID, "below",
        args.output_dir / "panel_A_downwind.png", grid_population, args.fire_icon,
    )
    plot_population_panel(
        population_grids, population_polygon, PANEL_BC_FIRE_GRID, "below",
        args.output_dir / "panel_B_downwind.png", grid_population, args.fire_icon,
    )
    plot_population_panel(
        population_grids, population_polygon, PANEL_BC_FIRE_GRID, "above",
        args.output_dir / "panel_C_upwind.png", grid_population, args.fire_icon,
    )

    map_ac_id = plot_map_grids(
        acs, grid, args.master, args.output_dir / "map_grids.png"
    )
    march_n = plot_month(
        args.master, grid, 2013, 3, args.output_dir / "march2013_plot.png"
    )
    october_n = plot_month(
        args.master, grid, 2013, 10, args.output_dir / "october2013_plot.png"
    )
    print(f"Grid overview: AC {map_ac_id}")
    print(f"March 2013: {march_n:,} grids; October 2013: {october_n:,} grids")
    print("Saved six outputs to:", args.output_dir)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build a LaTeX report explaining corrected AC area/pop classifications.

The report selects a real grid-month whose corrected area and population
indicators differ when possible. It recomputes both measures from source
geometry, population centroids, and the rolling wind angle. All angles use the
same Cartesian convention: degrees counterclockwise from East.
"""

from __future__ import annotations

import argparse
import logging
import math
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

import duckdb
import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.lines import Line2D
from matplotlib.patches import Arc, Patch, Polygon as MplPolygon
from shapely.geometry import Polygon

import build_downup_ac_area_cluster as area_builder


LOCAL_SA_ROOT = Path(r"C:\Users\eunic\Dropbox\sa_fires")
CLUSTER_SA_ROOT = Path("/groups/sgulzar/sa_fires")
METRIC_CRS = "EPSG:7755"


@dataclass(frozen=True)
class ClassificationExample:
    grid_id: int
    ac_uq_id: int
    year: int
    month: int
    wind_angle_east: float
    province: str
    district: str
    assembly: str
    focal_x: float
    focal_y: float
    focal_population: float
    ac_geometry: object
    grid_geometry: object
    neighbors: pd.DataFrame
    downwind_mask: np.ndarray
    upwind_mask: np.ndarray
    boundary_mask: np.ndarray
    downwind_area: float
    upwind_area: float
    downwind_pop: float
    upwind_pop: float
    downup_ac_area: int
    downup_ac_pop: int


def default_sa_root() -> Path:
    configured = os.environ.get("SA_FIRES_ROOT")
    if configured:
        return Path(configured)
    if LOCAL_SA_ROOT.exists():
        return LOCAL_SA_ROOT
    return CLUSTER_SA_ROOT


def default_paths() -> dict[str, Path]:
    sa_root = default_sa_root()
    intermediate = (
        sa_root / "proj_bureaucrats_farms" / "data_output" / "intermediate"
    )
    population = intermediate / "small_grid_population_2010.parquet"
    local_fallback = (
        sa_root
        / "proj_downwind"
        / "data_output"
        / "intermediate"
        / "small_grid_population_2010.parquet"
    )
    if not population.exists() and local_fallback.exists():
        population = local_fallback
    repository = Path(__file__).resolve().parents[3]
    return {
        "panel": intermediate / "data_2012_2024_grid_ac_downup_pop.parquet",
        "population": population,
        "acs": intermediate / "_0_2_3_ACs_right_shapefile.shp",
        "grids": intermediate / "1-grid-generation.shp",
        "output": repository / "output" / "pdf",
    }


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    paths = default_paths()
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--panel-input", type=Path, default=paths["panel"])
    parser.add_argument("--grid-population", type=Path, default=paths["population"])
    parser.add_argument("--ac-shapefile", type=Path, default=paths["acs"])
    parser.add_argument("--grid-shapefile", type=Path, default=paths["grids"])
    parser.add_argument("--output-directory", type=Path, default=paths["output"])
    parser.add_argument("--metric-crs", default=METRIC_CRS)
    parser.add_argument("--candidate-rows", type=int, default=30_000)
    parser.add_argument("--minimum-margin-share", type=float, default=0.12)
    parser.add_argument("--grid-id", type=int, default=None)
    parser.add_argument("--year", type=int, default=None)
    parser.add_argument("--month", type=int, default=None)
    parser.add_argument("--no-compile", action="store_true")
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args(argv)


def sql_string(value: str | Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def find_column(columns: Sequence[str], candidates: Sequence[str]) -> str:
    lookup = {column.lower(): column for column in columns}
    for candidate in candidates:
        if candidate.lower() in lookup:
            return lookup[candidate.lower()]
    raise KeyError("None of the expected columns exists: " + ", ".join(candidates))


def circular_difference(first: np.ndarray, second: float) -> np.ndarray:
    """Signed shortest difference for East-referenced angles."""
    return (first - second + 180.0) % 360.0 - 180.0


def halfplane_radius(geometry: object, x: float, y: float) -> float:
    minx, miny, maxx, maxy = geometry.bounds
    return (
        math.hypot(
            max(abs(x - minx), abs(x - maxx)),
            max(abs(y - miny), abs(y - maxy)),
        )
        + 10.0
    )


def east_halfplane(
    x: float,
    y: float,
    angle: float,
    radius: float,
) -> Polygon:
    theta = math.radians(angle)
    wind_x, wind_y = math.cos(theta), math.sin(theta)
    tangent_x, tangent_y = math.sin(theta), -math.cos(theta)
    return Polygon(
        [
            (x - tangent_x * radius, y - tangent_y * radius),
            (x + tangent_x * radius, y + tangent_y * radius),
            (
                x + tangent_x * radius + wind_x * 2.0 * radius,
                y + tangent_y * radius + wind_y * 2.0 * radius,
            ),
            (
                x - tangent_x * radius + wind_x * 2.0 * radius,
                y - tangent_y * radius + wind_y * 2.0 * radius,
            ),
        ]
    )


def load_ac_geometries(
    path: Path,
    metric_crs: str,
) -> tuple[dict[int, object], dict[int, dict[str, str]]]:
    acs = gpd.read_file(path.resolve())
    if acs.crs is None or "ac_uq_id" not in acs.columns:
        raise ValueError("The AC shapefile needs a CRS and ac_uq_id.")
    assembly_column = find_column(list(acs.columns), ("ASSEMBLY_1", "ASSEMBLY"))
    district_column = find_column(list(acs.columns), ("DISTRICT", "district"))
    province_column = find_column(list(acs.columns), ("STATE_UT", "province"))
    acs = acs.to_crs(metric_crs)
    geometries: dict[int, object] = {}
    attributes: dict[int, dict[str, str]] = {}
    for row in acs[
        [
            "ac_uq_id",
            province_column,
            district_column,
            assembly_column,
            "geometry",
        ]
    ].itertuples(index=False, name=None):
        ac_id = int(row[0])
        geometries[ac_id] = area_builder.largest_polygon(row[4])
        attributes[ac_id] = {
            "province": str(row[1]).title(),
            "district": str(row[2]).title(),
            "assembly": str(row[3]).title(),
        }
    return geometries, attributes


def load_grid_geometry(path: Path, grid_id: int, metric_crs: str) -> object:
    grids = gpd.read_file(path.resolve())
    grid_column = find_column(
        list(grids.columns),
        ("unique_small_grid_id", "unq_s__", "unique_grid_id"),
    )
    identifiers = pd.to_numeric(grids[grid_column], errors="coerce")
    selected = grids.loc[identifiers == grid_id]
    if len(selected) != 1:
        raise ValueError(f"Expected one grid geometry for {grid_id}; found {len(selected)}.")
    return selected.to_crs(metric_crs).geometry.iloc[0]


def input_tables(
    args: argparse.Namespace,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    connection = duckdb.connect()
    try:
        panel = sql_string(args.panel_input.resolve())
        population = sql_string(args.grid_population.resolve())
        grid_info = connection.execute(
            f"""
            WITH membership AS (
                SELECT
                    unique_small_grid_id::BIGINT AS grid_id,
                    min(ac_uq_id)::BIGINT AS ac_uq_id
                FROM read_parquet({panel})
                GROUP BY unique_small_grid_id
                HAVING count(DISTINCT ac_uq_id) = 1
            )
            SELECT
                membership.grid_id,
                membership.ac_uq_id,
                source.population_2010::DOUBLE AS population_2010,
                source.centroid_x::DOUBLE AS centroid_x,
                source.centroid_y::DOUBLE AS centroid_y
            FROM membership
            INNER JOIN read_parquet({population}) AS source
                ON membership.grid_id = source.unique_small_grid_id::BIGINT
            """
        ).df()
        where = ["rollav_wind_direction_cellid_month IS NOT NULL"]
        parameters: list[int] = []
        if args.grid_id is not None:
            where.append("unique_small_grid_id = ?")
            parameters.append(args.grid_id)
        if args.year is not None:
            where.append('year = ?')
            parameters.append(args.year)
        if args.month is not None:
            where.append('month = ?')
            parameters.append(args.month)
        candidates = connection.execute(
            f"""
            SELECT
                unique_small_grid_id::BIGINT AS grid_id,
                ac_uq_id::BIGINT AS ac_uq_id,
                year::INTEGER AS observation_year,
                month::INTEGER AS observation_month,
                rollav_wind_direction_cellid_month::DOUBLE AS wind_angle_east
            FROM read_parquet({panel})
            WHERE {' AND '.join(where)}
            ORDER BY hash(unique_small_grid_id, year, month)
            LIMIT {int(args.candidate_rows)}
            """,
            parameters,
        ).df()
    finally:
        connection.close()
    if grid_info.empty or candidates.empty:
        raise ValueError("The requested inputs do not yield candidate observations.")
    if grid_info[["population_2010", "centroid_x", "centroid_y"]].isna().any().any():
        raise ValueError("Grid population/centroid inputs contain missing values.")
    return grid_info, candidates


def classify_candidate(
    candidate: object,
    focal: pd.Series,
    neighbors: pd.DataFrame,
    ac_geometry: object,
) -> dict[str, object]:
    wind = float(candidate.wind_angle_east) % 360.0
    dx = neighbors["centroid_x"].to_numpy() - float(focal["centroid_x"])
    dy = neighbors["centroid_y"].to_numpy() - float(focal["centroid_y"])
    bearings = (np.degrees(np.arctan2(dy, dx)) + 360.0) % 360.0
    difference = circular_difference(bearings, wind)
    downwind = np.abs(difference) < 90.0
    upwind = np.abs(difference) > 90.0
    boundary = ~(downwind | upwind)
    population = neighbors["population_2010"].to_numpy(dtype=np.float64)
    downwind_pop = float(population[downwind].sum())
    upwind_pop = float(population[upwind].sum())
    downwind_area, upwind_area = area_builder.scalar_halfplane_area(
        ac_geometry,
        tuple(map(float, ac_geometry.bounds)),
        float(ac_geometry.area),
        float(focal["centroid_x"]),
        float(focal["centroid_y"]),
        wind,
    )
    return {
        "wind": wind,
        "downwind": downwind,
        "upwind": upwind,
        "boundary": boundary,
        "downwind_pop": downwind_pop,
        "upwind_pop": upwind_pop,
        "downwind_area": downwind_area,
        "upwind_area": upwind_area,
        "area_flag": int(downwind_area > upwind_area),
        "pop_flag": int(downwind_pop > upwind_pop),
    }


def select_example(args: argparse.Namespace) -> ClassificationExample:
    logging.info("Searching for a real corrected classification example")
    grid_info, candidates = input_tables(args)
    ac_geometries, ac_attributes = load_ac_geometries(
        args.ac_shapefile, args.metric_crs
    )
    grid_lookup = grid_info.set_index("grid_id", drop=False)
    groups = {
        int(ac_id): frame
        for ac_id, frame in grid_info.groupby("ac_uq_id", sort=False)
    }
    fallback: tuple[object, pd.Series, pd.DataFrame, dict[str, object]] | None = None
    for candidate in candidates.itertuples(index=False):
        if candidate.grid_id not in grid_lookup.index:
            continue
        if int(candidate.ac_uq_id) not in ac_geometries:
            continue
        focal = grid_lookup.loc[candidate.grid_id]
        neighbors = groups[int(candidate.ac_uq_id)]
        neighbors = neighbors.loc[neighbors["grid_id"] != candidate.grid_id].copy()
        if neighbors.empty:
            continue
        result = classify_candidate(
            candidate,
            focal,
            neighbors,
            ac_geometries[int(candidate.ac_uq_id)],
        )
        if fallback is None:
            fallback = (candidate, focal, neighbors, result)
        area_total = float(result["downwind_area"]) + float(result["upwind_area"])
        pop_total = float(result["downwind_pop"]) + float(result["upwind_pop"])
        area_margin = abs(
            float(result["downwind_area"]) - float(result["upwind_area"])
        ) / area_total
        pop_margin = abs(
            float(result["downwind_pop"]) - float(result["upwind_pop"])
        ) / pop_total
        if (
            result["area_flag"] != result["pop_flag"]
            and area_margin >= args.minimum_margin_share
            and pop_margin >= args.minimum_margin_share
        ):
            fallback = (candidate, focal, neighbors, result)
            break
    if fallback is None:
        raise ValueError("No valid example was found.")
    candidate, focal, neighbors, result = fallback
    ac_id = int(candidate.ac_uq_id)
    attributes = ac_attributes[ac_id]
    return ClassificationExample(
        grid_id=int(candidate.grid_id),
        ac_uq_id=ac_id,
        year=int(candidate.observation_year),
        month=int(candidate.observation_month),
        wind_angle_east=float(candidate.wind_angle_east),
        province=attributes["province"],
        district=attributes["district"],
        assembly=attributes["assembly"],
        focal_x=float(focal["centroid_x"]),
        focal_y=float(focal["centroid_y"]),
        focal_population=float(focal["population_2010"]),
        ac_geometry=ac_geometries[ac_id],
        grid_geometry=load_grid_geometry(
            args.grid_shapefile, int(candidate.grid_id), args.metric_crs
        ),
        neighbors=neighbors.reset_index(drop=True),
        downwind_mask=np.asarray(result["downwind"]),
        upwind_mask=np.asarray(result["upwind"]),
        boundary_mask=np.asarray(result["boundary"]),
        downwind_area=float(result["downwind_area"]),
        upwind_area=float(result["upwind_area"]),
        downwind_pop=float(result["downwind_pop"]),
        upwind_pop=float(result["upwind_pop"]),
        downup_ac_area=int(result["area_flag"]),
        downup_ac_pop=int(result["pop_flag"]),
    )


def plot_geometry(ax: plt.Axes, geometry: object, **kwargs: object) -> None:
    gpd.GeoSeries([geometry], crs=METRIC_CRS).plot(ax=ax, **kwargs)


def add_focal_grid(ax: plt.Axes, example: ClassificationExample) -> None:
    plot_geometry(
        ax,
        example.grid_geometry,
        facecolor="#f2cb67",
        edgecolor="#8a6819",
        linewidth=1.0,
        alpha=0.95,
        zorder=7,
    )
    ax.scatter(
        [example.focal_x],
        [example.focal_y],
        s=32,
        color="#8a6819",
        edgecolor="white",
        linewidth=0.7,
        zorder=9,
    )


def add_wind_and_divider(
    ax: plt.Axes,
    example: ClassificationExample,
    arrow_length: float,
    line_length: float,
) -> None:
    theta = math.radians(example.wind_angle_east)
    wind_x, wind_y = math.cos(theta), math.sin(theta)
    tangent_x, tangent_y = math.sin(theta), -math.cos(theta)
    ax.annotate(
        "",
        xy=(
            example.focal_x + wind_x * arrow_length,
            example.focal_y + wind_y * arrow_length,
        ),
        xytext=(example.focal_x, example.focal_y),
        arrowprops={
            "arrowstyle": "-|>",
            "color": "#1769aa",
            "linewidth": 2.6,
            "mutation_scale": 14,
        },
        zorder=10,
    )
    ax.plot(
        [
            example.focal_x - tangent_x * line_length,
            example.focal_x + tangent_x * line_length,
        ],
        [
            example.focal_y - tangent_y * line_length,
            example.focal_y + tangent_y * line_length,
        ],
        color="#30343b",
        linestyle="--",
        linewidth=1.4,
        zorder=8,
    )


def set_map_extent(ax: plt.Axes, example: ClassificationExample) -> None:
    minx, miny, maxx, maxy = example.ac_geometry.bounds
    x_values = example.neighbors["centroid_x"].to_numpy()
    y_values = example.neighbors["centroid_y"].to_numpy()
    minx = min(minx, float(x_values.min()))
    maxx = max(maxx, float(x_values.max()))
    miny = min(miny, float(y_values.min()))
    maxy = max(maxy, float(y_values.max()))
    span = max(maxx - minx, maxy - miny)
    padding = span * 0.07
    ax.set_xlim(minx - padding, maxx + padding)
    ax.set_ylim(miny - padding, maxy + padding)
    ax.set_aspect("equal")
    ax.axis("off")


def create_method_figure(
    example: ClassificationExample,
    figure_pdf: Path,
    figure_png: Path,
) -> None:
    minx, miny, maxx, maxy = example.ac_geometry.bounds
    span = max(maxx - minx, maxy - miny)
    radius = halfplane_radius(
        example.ac_geometry, example.focal_x, example.focal_y
    )
    down_square = east_halfplane(
        example.focal_x,
        example.focal_y,
        example.wind_angle_east,
        radius,
    )
    up_square = east_halfplane(
        example.focal_x,
        example.focal_y,
        example.wind_angle_east + 180.0,
        radius,
    )
    down_geometry = example.ac_geometry.intersection(down_square)
    up_geometry = example.ac_geometry.intersection(up_square)

    plt.rcParams.update(
        {
            "font.family": "DejaVu Sans",
            "font.size": 9,
            "axes.titlesize": 10,
            "axes.titleweight": "bold",
        }
    )
    fig, axes = plt.subplots(2, 2, figsize=(10.8, 8.5), constrained_layout=True)

    first = axes[0, 0]
    first.add_patch(
        MplPolygon(
            np.asarray(up_square.exterior.coords),
            closed=True,
            facecolor="#f7df9b",
            edgecolor="none",
            alpha=0.45,
            zorder=1,
        )
    )
    first.add_patch(
        MplPolygon(
            np.asarray(down_square.exterior.coords),
            closed=True,
            facecolor="#a9d2ef",
            edgecolor="none",
            alpha=0.52,
            zorder=2,
        )
    )
    plot_geometry(
        first,
        example.ac_geometry,
        facecolor="none",
        edgecolor="#4d5560",
        linewidth=1.3,
        zorder=5,
    )
    add_focal_grid(first, example)
    add_wind_and_divider(first, example, span * 0.30, span)
    angle = example.wind_angle_east
    arc_start, arc_end = sorted((0.0, angle))
    first.add_patch(
        Arc(
            (example.focal_x, example.focal_y),
            span * 0.20,
            span * 0.20,
            theta1=arc_start,
            theta2=arc_end,
            color="#1769aa",
            linewidth=1.2,
            zorder=11,
        )
    )
    first.text(
        0.02,
        0.98,
        f"wind = {example.wind_angle_east:.1f} deg from East\n"
        "dashed line is perpendicular",
        transform=first.transAxes,
        ha="left",
        va="top",
        fontsize=8,
        bbox={"facecolor": "white", "edgecolor": "#1769aa", "alpha": 0.92},
        zorder=12,
    )
    first.set_title("(a) One East-referenced wind vector, two half-planes")
    set_map_extent(first, example)

    second = axes[0, 1]
    plot_geometry(
        second,
        up_geometry,
        facecolor="#f7df9b",
        edgecolor="none",
        alpha=0.90,
        zorder=1,
    )
    plot_geometry(
        second,
        down_geometry,
        facecolor="#a9d2ef",
        edgecolor="none",
        alpha=0.90,
        zorder=2,
    )
    plot_geometry(
        second,
        example.ac_geometry,
        facecolor="none",
        edgecolor="#4d5560",
        linewidth=1.3,
        zorder=5,
    )
    add_focal_grid(second, example)
    add_wind_and_divider(second, example, span * 0.24, span)
    second.text(
        0.02,
        0.02,
        f"downwind area = {example.downwind_area:.1f} km2\n"
        f"upwind area = {example.upwind_area:.1f} km2\n"
        f"downup_ac_area = {example.downup_ac_area}",
        transform=second.transAxes,
        ha="left",
        va="bottom",
        fontsize=8.3,
        fontweight="bold",
        bbox={"facecolor": "white", "edgecolor": "#4d5560", "alpha": 0.94},
        zorder=12,
    )
    second.set_title("(b) Exact AC intersections determine area treatment")
    set_map_extent(second, example)

    third = axes[1, 0]
    plot_geometry(
        third,
        example.ac_geometry,
        facecolor="#f4f1e9",
        edgecolor="#4d5560",
        linewidth=1.3,
        zorder=1,
    )
    population = example.neighbors["population_2010"].to_numpy(dtype=np.float64)
    sizes = 10.0 + 90.0 * np.sqrt(population / max(float(population.max()), 1.0))
    x = example.neighbors["centroid_x"].to_numpy()
    y = example.neighbors["centroid_y"].to_numpy()
    third.scatter(
        x[example.upwind_mask],
        y[example.upwind_mask],
        s=sizes[example.upwind_mask],
        marker="^",
        color="#e7b947",
        edgecolor="#7a5b10",
        linewidth=0.5,
        alpha=0.82,
        zorder=4,
    )
    third.scatter(
        x[example.downwind_mask],
        y[example.downwind_mask],
        s=sizes[example.downwind_mask],
        marker="o",
        color="#4f9bcf",
        edgecolor="#174f76",
        linewidth=0.5,
        alpha=0.82,
        zorder=5,
    )
    if example.boundary_mask.any():
        third.scatter(
            x[example.boundary_mask],
            y[example.boundary_mask],
            s=sizes[example.boundary_mask],
            marker="x",
            color="#4d5560",
            zorder=6,
        )
    add_focal_grid(third, example)
    add_wind_and_divider(third, example, span * 0.24, span)
    third.text(
        0.02,
        0.02,
        f"downwind population = {example.downwind_pop:,.0f}\n"
        f"upwind population = {example.upwind_pop:,.0f}\n"
        f"downup_ac_pop = {example.downup_ac_pop}",
        transform=third.transAxes,
        ha="left",
        va="bottom",
        fontsize=8.3,
        fontweight="bold",
        bbox={"facecolor": "white", "edgecolor": "#4d5560", "alpha": 0.94},
        zorder=12,
    )
    third.set_title("(c) Same-AC centroids determine population treatment")
    set_map_extent(third, example)

    fourth = axes[1, 1]
    area_total = example.downwind_area + example.upwind_area
    pop_total = example.downwind_pop + example.upwind_pop
    down_shares = [
        example.downwind_area * 100.0 / area_total,
        example.downwind_pop * 100.0 / pop_total,
    ]
    up_shares = [100.0 - value for value in down_shares]
    labels = ["Area", "Population"]
    positions = np.arange(2)
    fourth.barh(positions, down_shares, color="#a9d2ef", edgecolor="#1769aa")
    fourth.barh(
        positions,
        up_shares,
        left=down_shares,
        color="#f7df9b",
        edgecolor="#bc8d1c",
    )
    fourth.axvline(50.0, color="#30343b", linestyle="--", linewidth=1.2)
    for index, (down_share, flag) in enumerate(
        zip(down_shares, (example.downup_ac_area, example.downup_ac_pop))
    ):
        fourth.text(
            down_share / 2.0,
            index,
            f"Down {down_share:.1f}%",
            ha="center",
            va="center",
            fontsize=8.2,
            fontweight="bold",
        )
        fourth.text(
            down_share + (100.0 - down_share) / 2.0,
            index,
            f"Up {100.0 - down_share:.1f}%",
            ha="center",
            va="center",
            fontsize=8.2,
            fontweight="bold",
        )
        fourth.text(
            100.5,
            index,
            f"indicator = {flag}",
            ha="left",
            va="center",
            fontsize=8.5,
            fontweight="bold",
            color="#245c3a" if flag else "#7a3d17",
        )
    fourth.set_yticks(positions, labels)
    fourth.set_xlim(0.0, 119.0)
    fourth.set_xlabel("Share of AC total (%)")
    fourth.invert_yaxis()
    fourth.spines[["top", "right", "left"]].set_visible(False)
    fourth.grid(axis="x", color="#d8dadd", linewidth=0.6)
    fourth.set_axisbelow(True)
    fourth.set_title("(d) The two indicators compare different majorities")

    fig.legend(
        handles=[
            Patch(facecolor="#a9d2ef", edgecolor="#1769aa", label="Downwind"),
            Patch(facecolor="#f7df9b", edgecolor="#bc8d1c", label="Upwind"),
            Patch(facecolor="#f2cb67", edgecolor="#8a6819", label="Focal grid"),
            Line2D([0], [0], color="#1769aa", linewidth=2.5, label="Wind vector"),
            Line2D(
                [0],
                [0],
                color="#30343b",
                linestyle="--",
                label="Perpendicular divider",
            ),
        ],
        loc="outside lower center",
        ncol=5,
        frameon=False,
        fontsize=8,
    )
    fig.suptitle(
        "Corrected construction of downup_ac_area and downup_ac_pop",
        fontsize=13,
        fontweight="bold",
    )
    fig.savefig(figure_pdf, bbox_inches="tight")
    fig.savefig(figure_png, dpi=220, bbox_inches="tight")
    plt.close(fig)


def latex_escape(value: object) -> str:
    text = str(value)
    for old, new in {
        "\\": r"\textbackslash{}",
        "&": r"\&",
        "%": r"\%",
        "$": r"\$",
        "#": r"\#",
        "_": r"\_",
        "{": r"\{",
        "}": r"\}",
    }.items():
        text = text.replace(old, new)
    return text


def report_source(example: ClassificationExample, figure_pdf: Path) -> str:
    area_total = example.downwind_area + example.upwind_area
    pop_total = example.downwind_pop + example.upwind_pop
    down_area_share = example.downwind_area * 100.0 / area_total
    down_pop_share = example.downwind_pop * 100.0 / pop_total
    figure_name = latex_escape(figure_pdf.name)
    return rf"""\documentclass[10pt]{{article}}
\usepackage{{graphicx}}
\setlength{{\textwidth}}{{6.85in}}
\setlength{{\oddsidemargin}}{{-0.18in}}
\setlength{{\evensidemargin}}{{-0.18in}}
\setlength{{\textheight}}{{9.45in}}
\setlength{{\topmargin}}{{-0.65in}}
\setlength{{\parindent}}{{0pt}}
\setlength{{\parskip}}{{0.45em}}
\setlength{{\emergencystretch}}{{3em}}
\title{{\textbf{{How We Classify Downwind and Upwind AC Area and Population}}}}
\author{{Corrected East-referenced construction}}
\date{{August 2026}}

\begin{{document}}
\maketitle

\section*{{Executive summary}}
For each focal grid and month, one rolling wind direction divides its assigned
assembly constituency (AC) into a downwind half and an upwind half. We then
construct two related but distinct indicators:
\[
\texttt{{downup\_ac\_area}}
=\mathbf{{1}}[A_{{down}}>A_{{up}}],
\qquad
\texttt{{downup\_ac\_pop}}
=\mathbf{{1}}[P_{{down}}>P_{{up}}].
\]
The area indicator compares exact polygon areas. The population indicator
compares the sum of 2010 population assigned to other small-grid centroids in
the same AC. Therefore, the indicators can differ when population is unevenly
distributed across the AC.

\section*{{One angular convention throughout}}
Every directional calculation is a Cartesian angle measured counterclockwise
from East:
\[
0^\circ=\mathrm{{East}},\quad 90^\circ=\mathrm{{North}},\quad
180^\circ=\mathrm{{West}},\quad 270^\circ=\mathrm{{South}}.
\]
The wind is $w=\mathrm{{atan2}}(v10,u10)$. For a comparison-grid centroid $j$
relative to focal grid $i$, the bearing is
\[
\beta_{{ij}}=\mathrm{{atan2}}(y_j-y_i,x_j-x_i).
\]
No step interprets either angle as a clockwise-from-North compass bearing.
The normalized calculation angle remains East-referenced; normalization only
changes its numeric range to $[0,360)$.

\section*{{Real example used in the figure}}
The reproducible script selected grid \textbf{{{example.grid_id}}} in
\textbf{{{latex_escape(example.assembly)}}} AC
(AC ID \textbf{{{example.ac_uq_id}}}),
{latex_escape(example.district)}, {latex_escape(example.province)}, for
\textbf{{{example.year}-{example.month:02d}}}. The rolling wind direction is
\textbf{{{example.wind_angle_east:.3f}$^\circ$ from East}}.

\begin{{center}}
\begin{{tabular}}{{lrrr}}
\hline
Measure & Downwind & Upwind & Indicator \\
\hline
Area (km$^2$) & {example.downwind_area:.2f} & {example.upwind_area:.2f} &
{example.downup_ac_area} \\
Area share (\%) & {down_area_share:.1f} & {100.0-down_area_share:.1f} & \\
Population & {example.downwind_pop:.0f} & {example.upwind_pop:.0f} &
{example.downup_ac_pop} \\
Population share (\%) & {down_pop_share:.1f} & {100.0-down_pop_share:.1f} & \\
\hline
\end{{tabular}}
\end{{center}}
Here, the downwind side contains the majority of AC area but not the majority
of the comparison-grid population. Thus
\texttt{{downup\_ac\_area}}={example.downup_ac_area} and
\texttt{{downup\_ac\_pop}}={example.downup_ac_pop}.

\clearpage
\begin{{figure}}[p]
\centering
\includegraphics[width=\textwidth]{{{figure_name}}}
\caption{{Corrected construction for one real grid-month. Panel (a) uses the
East-referenced wind vector and a perpendicular line through the focal-grid
centroid. Panel (b) intersects the AC with the two complementary squares.
Panel (c) classifies every other same-AC population centroid using the same
wind direction; marker size represents population. Panel (d) shows why the
two majority indicators can differ.}}
\end{{figure}}
\clearpage

\section*{{Step 1: construct the area measure}}
Let $p=(x_i,y_i)$ be the focal-grid centroid and let $\theta$ be the rolling
wind direction from East. Define
\[
v=(\cos\theta,\sin\theta),\qquad
t=(\sin\theta,-\cos\theta),
\]
where $v$ points downwind and $t$ is perpendicular to the wind. Choose $R$
larger than the maximum distance from $p$ to the AC bounds. The downwind square
has corners
\[
p-Rt,\quad p+Rt,\quad p+Rt+2Rv,\quad p-Rt+2Rv.
\]
The upwind square uses $-v$. We compute the exact intersections
\[
A_{{down}}=\mathrm{{area}}(AC\cap S_{{down}}),\qquad
A_{{up}}=\mathrm{{area}}(AC\cap S_{{up}}).
\]
The binary indicator equals 1 only when $A_{{down}}>A_{{up}}$. An exact tie is
coded 0. A missing rolling direction produces a missing indicator.

\section*{{Step 2: construct the population measure}}
For every other grid $j$ assigned to the same AC, compute the signed circular
difference
\[
\delta_{{ij}}=((\beta_{{ij}}-\theta+180)\bmod 360)-180.
\]
Grid $j$ is downwind when $|\delta_{{ij}}|<90^\circ$ and upwind when
$|\delta_{{ij}}|>90^\circ$. The focal grid is excluded because its centroid is
on the dividing line. A comparison centroid exactly on that line is also
excluded from both sums. Population is then
\[
P_{{down}}=\sum_{{j:\,|\delta_{{ij}}|<90^\circ}} Pop_{{j,2010}},\qquad
P_{{up}}=\sum_{{j:\,|\delta_{{ij}}|>90^\circ}} Pop_{{j,2010}}.
\]
The binary indicator equals 1 only when $P_{{down}}>P_{{up}}$; ties are 0 and
missing rolling direction produces a missing value.

\section*{{What is shared and what is different}}
\begin{{center}}
\begin{{tabular}}{{lll}}
\hline
Component & Area construction & Population construction \\
\hline
Focal unit & grid centroid & grid centroid \\
Wind angle & rolling, from East & rolling, from East \\
Divider & perpendicular line & same perpendicular line \\
Objects classified & AC polygon surface & same-AC grid centroids \\
Weights & square kilometres & 2010 grid population \\
Indicator & down area $>$ up area & down pop. $>$ up pop. \\
\hline
\end{{tabular}}
\end{{center}}

\clearpage
\section*{{Implementation safeguards}}
The production code retains the unrounded rolling-direction float for every
grid-month. Area rows are never rounded, grouped, cached, or deduplicated by
wind direction. The population lookup uses circular intervals and an ASOF join
only after both the wind and centroid bearings have been placed in the same
East-referenced $[0,360)$ system.

The automated tests enforce the four cardinal cases:
\begin{{itemize}}
  \item East wind: the eastern half-plane is downwind.
  \item North wind: the northern half-plane is downwind.
  \item West wind: the western half-plane is downwind.
  \item South wind: the southern half-plane is downwind.
\end{{itemize}}
They also test the $179^\circ/-179^\circ$ wraparound to ensure that monthly and
rolling directions are calculated from eastward/northward vector components,
not arithmetic averages of degree values.

\section*{{Production sequence}}
The corrected files are generated in this order:
\begin{{enumerate}}
  \item \texttt{{build\_wind\_direction\_grid\_duckdb.py}}\par
  \item \texttt{{build\_downup\_ac\_pop\_cluster.py}}\par
  \item \texttt{{build\_downup\_ac\_area\_cluster.py}}\par
  \item \texttt{{build\_downup\_13kmpl\_cluster.py}}\par
  \item \texttt{{build\_0\_master\_dataset.py}}\par
  \item \texttt{{build\_all\_stacked\_datasets\_duckdb.py}}\par
\end{{enumerate}}
The one-job launcher is
\texttt{{rebuild\_corrected\_downup\_pipeline.sbatch}}.

\section*{{Interpretation}}
Both indicators describe exposure generated by a hypothetical fire at the
focal grid under the prevailing rolling wind. The area measure asks whether
most of the constituency's land lies downwind. The population measure asks
whether most of the measured same-AC population lies downwind. Neither measure
should be interpreted as the other, and disagreement between them is a valid
feature of the construction rather than a merge error.

\end{{document}}
"""


def compile_report(tex_path: Path) -> Path:
    pdflatex = shutil.which("pdflatex")
    if not pdflatex:
        raise FileNotFoundError(
            "pdflatex was not found. Rerun with --no-compile to create the "
            "figure and LaTeX source."
        )
    command = [
        pdflatex,
        "--disable-installer",
        "-interaction=nonstopmode",
        "-halt-on-error",
        "-file-line-error",
        tex_path.name,
    ]
    for _ in range(2):
        completed = subprocess.run(
            command,
            cwd=tex_path.parent,
            text=True,
            capture_output=True,
            check=False,
        )
        if completed.returncode:
            tail = "\n".join(completed.stdout.splitlines()[-40:])
            raise RuntimeError(f"pdflatex failed:\n{tail}\n{completed.stderr}")
    return tex_path.with_suffix(".pdf")


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    if args.candidate_rows <= 0:
        raise ValueError("--candidate-rows must be positive.")
    for source in (
        args.panel_input,
        args.grid_population,
        args.ac_shapefile,
        args.grid_shapefile,
    ):
        if not source.is_file():
            raise FileNotFoundError(source)
    output_directory = args.output_directory.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)
    stem = "downup_area_population_classification"
    figure_pdf = output_directory / f"{stem}_figure.pdf"
    figure_png = output_directory / f"{stem}_figure.png"
    tex_path = output_directory / f"{stem}_report.tex"
    report_pdf = output_directory / f"{stem}_report.pdf"
    targets = [figure_pdf, figure_png, tex_path]
    if not args.no_compile:
        targets.append(report_pdf)
    existing = [path for path in targets if path.exists()]
    if existing and not args.overwrite:
        raise FileExistsError(
            "Outputs already exist; pass --overwrite:\n"
            + "\n".join(str(path) for path in existing)
        )

    example = select_example(args)
    logging.info(
        "Selected grid=%s AC=%s period=%s-%02d wind=%.3f area=%s pop=%s",
        example.grid_id,
        example.ac_uq_id,
        example.year,
        example.month,
        example.wind_angle_east,
        example.downup_ac_area,
        example.downup_ac_pop,
    )
    create_method_figure(example, figure_pdf, figure_png)
    tex_path.write_text(report_source(example, figure_pdf), encoding="utf-8")
    if not args.no_compile:
        compiled = compile_report(tex_path)
        logging.info("Completed PDF report: %s", compiled)
    logging.info("LaTeX source: %s", tex_path)
    logging.info("Standalone figure: %s", figure_pdf)
    return 0


if __name__ == "__main__":
    sys.exit(main())

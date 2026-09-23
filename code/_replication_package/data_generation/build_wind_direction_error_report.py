#!/usr/bin/env python3
"""Build a reproducible report illustrating the wind-angle convention error.

The report selects a real Punjab assembly constituency and grid whose compass
bearing from the grid centroid to the AC representative point is closest to
165 degrees. It then compares the geometrically correct interpretation of wind
angles measured counterclockwise from East with the legacy R interpretation,
which passes the same numeric angles to geosphere functions as clockwise
bearings from North.
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
from matplotlib.patches import Arc, Polygon as MplPolygon, Patch
from shapely.geometry import Polygon


LOCAL_SA_ROOT = Path(r"C:\Users\eunic\Dropbox\sa_fires")
CLUSTER_SA_ROOT = Path("/groups/sgulzar/sa_fires")
METRIC_CRS = "EPSG:7755"


@dataclass(frozen=True)
class SelectedExample:
    unique_small_grid_id: int
    ac_uq_id: int
    province: str
    district: str
    assembly: str
    grid_x: float
    grid_y: float
    ac_x: float
    ac_y: float
    target_bearing: float
    distance_km: float
    ac_geometry: object
    grid_geometry: object


@dataclass(frozen=True)
class AreaObservation:
    year: int
    month: int
    angle_from_east: float
    correct_compass_toward: float
    stored_downwind_area: float
    stored_upwind_area: float
    stored_downup_ac_area: int
    corrected_downwind_area: float
    corrected_upwind_area: float
    corrected_downup_ac_area: int


def default_sa_root() -> Path:
    configured = os.environ.get("SA_FIRES_ROOT")
    if configured:
        return Path(configured)
    if LOCAL_SA_ROOT.exists():
        return LOCAL_SA_ROOT
    return CLUSTER_SA_ROOT


def defaults() -> dict[str, Path]:
    sa_root = default_sa_root()
    intermediate = (
        sa_root / "proj_bureaucrats_farms" / "data_output" / "intermediate"
    )
    repository = Path(__file__).resolve().parents[3]
    return {
        "panel": intermediate / "data_2012_2024_grid_ac_downup_pop.parquet",
        "area_panel": intermediate / "data_2012_2024_grid_ac_downup.parquet",
        "acs": intermediate / "_0_2_3_ACs_right_shapefile.shp",
        "grids": intermediate / "1-grid-generation.shp",
        "output": repository / "output" / "pdf",
    }


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    paths = defaults()
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--panel", type=Path, default=paths["panel"])
    parser.add_argument("--area-panel", type=Path, default=paths["area_panel"])
    parser.add_argument("--ac-shapefile", type=Path, default=paths["acs"])
    parser.add_argument("--grid-shapefile", type=Path, default=paths["grids"])
    parser.add_argument("--output-directory", type=Path, default=paths["output"])
    parser.add_argument("--province", default="Punjab")
    parser.add_argument("--target-bearing", type=float, default=165.0)
    parser.add_argument("--minimum-distance-km", type=float, default=5.0)
    parser.add_argument("--maximum-distance-km", type=float, default=40.0)
    parser.add_argument(
        "--wind-angles",
        type=float,
        nargs=2,
        default=(55.0, 135.0),
        metavar=("ANGLE_1", "ANGLE_2"),
        help="Two wind angles measured counterclockwise from East.",
    )
    parser.add_argument("--metric-crs", default=METRIC_CRS)
    parser.add_argument("--no-compile", action="store_true")
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args(argv)


def sql_string(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def find_column(columns: Sequence[str], candidates: Sequence[str]) -> str:
    lookup = {column.lower(): column for column in columns}
    for candidate in candidates:
        if candidate.lower() in lookup:
            return lookup[candidate.lower()]
    raise KeyError("None of the expected columns exists: " + ", ".join(candidates))


def compass_bearing(dx: np.ndarray, dy: np.ndarray) -> np.ndarray:
    """Return clockwise-from-North bearings in the interval [0, 360)."""
    return np.mod(np.degrees(np.arctan2(dx, dy)) + 360.0, 360.0)


def circular_separation(first: float, second: float) -> float:
    return abs((first - second + 180.0) % 360.0 - 180.0)


def mathematical_to_compass_toward(angle_from_east: float) -> float:
    return (90.0 - angle_from_east) % 360.0


def select_example(args: argparse.Namespace) -> SelectedExample:
    logging.info("Selecting a real AC/grid pair near %.1f degrees", args.target_bearing)
    connection = duckdb.connect()
    try:
        membership = connection.execute(
            f"""
            SELECT
                unique_small_grid_id::BIGINT AS unique_small_grid_id,
                ac_uq_id::BIGINT AS ac_uq_id,
                min(province)::VARCHAR AS province,
                mode(district)::VARCHAR AS panel_district
            FROM read_parquet({sql_string(args.panel.resolve())})
            WHERE lower(province) = lower(?)
            GROUP BY unique_small_grid_id, ac_uq_id
            """,
            [args.province],
        ).df()
    finally:
        connection.close()
    if membership.empty:
        raise ValueError(f"No panel rows found for province {args.province!r}.")

    grids = gpd.read_file(args.grid_shapefile.resolve())
    grid_id = find_column(
        list(grids.columns),
        ("unique_small_grid_id", "unq_s__", "unique_grid_id"),
    )
    grids = grids[[grid_id, "geometry"]].rename(
        columns={grid_id: "unique_small_grid_id"}
    )
    grids["unique_small_grid_id"] = pd.to_numeric(
        grids["unique_small_grid_id"], errors="raise"
    ).astype("int64")
    grids = grids[
        grids["unique_small_grid_id"].isin(membership["unique_small_grid_id"])
    ].to_crs(args.metric_crs)
    if grids.empty:
        raise ValueError("No panel grids were found in the grid shapefile.")
    grid_centroids = grids.geometry.centroid
    grid_lookup = pd.DataFrame(
        {
            "unique_small_grid_id": grids["unique_small_grid_id"].to_numpy(),
            "grid_x": grid_centroids.x.to_numpy(),
            "grid_y": grid_centroids.y.to_numpy(),
        }
    )

    acs = gpd.read_file(args.ac_shapefile.resolve())
    required_ac_columns = {"ac_uq_id", "geometry"}
    if not required_ac_columns.issubset(acs.columns):
        raise KeyError(f"AC shapefile must contain {sorted(required_ac_columns)}.")
    acs = acs[acs["ac_uq_id"].isin(membership["ac_uq_id"])].to_crs(
        args.metric_crs
    )
    representative_points = acs.geometry.representative_point()
    assembly_column = find_column(list(acs.columns), ("ASSEMBLY_1", "ASSEMBLY"))
    district_column = find_column(list(acs.columns), ("DISTRICT", "district"))
    ac_lookup = pd.DataFrame(
        {
            "ac_uq_id": pd.to_numeric(acs["ac_uq_id"], errors="raise").astype(
                "int64"
            ),
            "assembly": acs[assembly_column].astype(str),
            "ac_district": acs[district_column].astype(str),
            "ac_x": representative_points.x.to_numpy(),
            "ac_y": representative_points.y.to_numpy(),
        }
    )

    candidates = membership.merge(grid_lookup, on="unique_small_grid_id").merge(
        ac_lookup, on="ac_uq_id"
    )
    candidates["dx"] = candidates["ac_x"] - candidates["grid_x"]
    candidates["dy"] = candidates["ac_y"] - candidates["grid_y"]
    candidates["distance_km"] = np.hypot(
        candidates["dx"], candidates["dy"]
    ) / 1_000.0
    candidates["bearing"] = compass_bearing(
        candidates["dx"].to_numpy(), candidates["dy"].to_numpy()
    )
    candidates["target_error"] = np.abs(
        (candidates["bearing"] - args.target_bearing + 180.0) % 360.0 - 180.0
    )
    eligible = candidates[
        candidates["distance_km"].between(
            args.minimum_distance_km, args.maximum_distance_km
        )
    ].sort_values(["target_error", "distance_km"])
    if eligible.empty:
        raise ValueError("No candidate satisfies the requested distance range.")
    selected = eligible.iloc[0]

    selected_grid = grids.loc[
        grids["unique_small_grid_id"] == selected["unique_small_grid_id"],
        "geometry",
    ].iloc[0]
    selected_ac = acs.loc[
        pd.to_numeric(acs["ac_uq_id"]) == selected["ac_uq_id"], "geometry"
    ].iloc[0]
    return SelectedExample(
        unique_small_grid_id=int(selected["unique_small_grid_id"]),
        ac_uq_id=int(selected["ac_uq_id"]),
        province=str(selected["province"]),
        district=str(selected["ac_district"]),
        assembly=str(selected["assembly"]),
        grid_x=float(selected["grid_x"]),
        grid_y=float(selected["grid_y"]),
        ac_x=float(selected["ac_x"]),
        ac_y=float(selected["ac_y"]),
        target_bearing=float(selected["bearing"]),
        distance_km=float(selected["distance_km"]),
        ac_geometry=selected_ac,
        grid_geometry=selected_grid,
    )


def halfplane_polygon(
    focal_x: float,
    focal_y: float,
    compass_direction: float,
    radius: float,
) -> Polygon:
    theta = math.radians(compass_direction)
    wind_x, wind_y = math.sin(theta), math.cos(theta)
    tangent_x, tangent_y = math.cos(theta), -math.sin(theta)
    return Polygon(
        [
            (
                focal_x - tangent_x * radius,
                focal_y - tangent_y * radius,
            ),
            (
                focal_x + tangent_x * radius,
                focal_y + tangent_y * radius,
            ),
            (
                focal_x + tangent_x * radius + wind_x * 2.0 * radius,
                focal_y + tangent_y * radius + wind_y * 2.0 * radius,
            ),
            (
                focal_x - tangent_x * radius + wind_x * 2.0 * radius,
                focal_y - tangent_y * radius + wind_y * 2.0 * radius,
            ),
        ]
    )


def halfplane_radius(example: SelectedExample) -> float:
    minx, miny, maxx, maxy = example.ac_geometry.bounds
    return (
        math.hypot(
            max(abs(example.grid_x - minx), abs(example.grid_x - maxx)),
            max(abs(example.grid_y - miny), abs(example.grid_y - maxy)),
        )
        + 10.0
    )


def directional_area(
    example: SelectedExample,
    compass_direction: float,
) -> tuple[float, float, object]:
    square = halfplane_polygon(
        example.grid_x,
        example.grid_y,
        compass_direction,
        halfplane_radius(example),
    )
    downwind_geometry = example.ac_geometry.intersection(square)
    downwind_area = float(downwind_geometry.area) / 1_000_000.0
    total_area = float(example.ac_geometry.area) / 1_000_000.0
    return downwind_area, total_area - downwind_area, downwind_geometry


def select_area_observations(
    args: argparse.Namespace,
    example: SelectedExample,
) -> tuple[list[AreaObservation], dict[str, int]]:
    connection = duckdb.connect()
    try:
        rows = connection.execute(
            f"""
            SELECT
                year::INTEGER AS year,
                month::INTEGER AS month,
                rollav_wind_direction_cellid_month::DOUBLE AS angle_from_east,
                downwind_area::DOUBLE AS stored_downwind_area,
                upwind_area::DOUBLE AS stored_upwind_area,
                downup_ac_area::INTEGER AS stored_downup_ac_area
            FROM read_parquet({sql_string(args.area_panel.resolve())})
            WHERE unique_small_grid_id = ?
              AND rollav_wind_direction_cellid_month IS NOT NULL
            ORDER BY year, month
            """,
            [example.unique_small_grid_id],
        ).df()
    finally:
        connection.close()
    if rows.empty:
        raise ValueError("The selected grid has no nonmissing area observations.")

    observations: list[AreaObservation] = []
    for row in rows.itertuples(index=False):
        angle = float(row.angle_from_east)
        legacy_compass = angle % 360.0
        recreated_down, recreated_up, _ = directional_area(
            example, legacy_compass
        )
        if not (
            math.isclose(
                recreated_down,
                float(row.stored_downwind_area),
                rel_tol=0.0,
                abs_tol=1e-6,
            )
            and math.isclose(
                recreated_up,
                float(row.stored_upwind_area),
                rel_tol=0.0,
                abs_tol=1e-6,
            )
        ):
            raise ValueError(
                "The legacy half-plane does not reproduce the stored area "
                f"for {row.year}-{row.month:02d}."
            )
        corrected_compass = mathematical_to_compass_toward(angle)
        corrected_down, corrected_up, _ = directional_area(
            example, corrected_compass
        )
        observations.append(
            AreaObservation(
                year=int(row.year),
                month=int(row.month),
                angle_from_east=angle,
                correct_compass_toward=corrected_compass,
                stored_downwind_area=float(row.stored_downwind_area),
                stored_upwind_area=float(row.stored_upwind_area),
                stored_downup_ac_area=int(row.stored_downup_ac_area),
                corrected_downwind_area=corrected_down,
                corrected_upwind_area=corrected_up,
                corrected_downup_ac_area=int(corrected_down > corrected_up),
            )
        )

    disagreements = [
        observation
        for observation in observations
        if observation.stored_downup_ac_area
        != observation.corrected_downup_ac_area
    ]
    positive = [observation for observation in disagreements if observation.angle_from_east > 0]
    negative = [observation for observation in disagreements if observation.angle_from_east < 0]
    if not positive or not negative:
        raise ValueError(
            "A positive and a negative stored/corrected disagreement are required."
        )
    selected_positive = min(
        positive,
        key=lambda observation: abs(
            observation.angle_from_east - max(args.wind_angles)
        ),
    )
    selected_negative = min(
        negative,
        key=lambda observation: abs(observation.angle_from_east + 75.0),
    )
    summary = {
        "rows": len(observations),
        "disagreements": len(disagreements),
        "stored_0_corrected_0": sum(
            observation.stored_downup_ac_area == 0
            and observation.corrected_downup_ac_area == 0
            for observation in observations
        ),
        "stored_0_corrected_1": sum(
            observation.stored_downup_ac_area == 0
            and observation.corrected_downup_ac_area == 1
            for observation in observations
        ),
        "stored_1_corrected_0": sum(
            observation.stored_downup_ac_area == 1
            and observation.corrected_downup_ac_area == 0
            for observation in observations
        ),
        "stored_1_corrected_1": sum(
            observation.stored_downup_ac_area == 1
            and observation.corrected_downup_ac_area == 1
            for observation in observations
        ),
    }
    return [selected_positive, selected_negative], summary


def plot_geometry(ax: plt.Axes, geometry: object, **kwargs: object) -> None:
    series = gpd.GeoSeries([geometry], crs=METRIC_CRS)
    series.plot(ax=ax, **kwargs)


def draw_angle_arc(
    ax: plt.Axes,
    example: SelectedExample,
    angle_from_east: float,
    legacy: bool,
    radius: float,
) -> None:
    if legacy:
        direction_math = 90.0 - angle_from_east
        theta1, theta2 = sorted((direction_math, 90.0))
        ax.plot(
            [example.grid_x, example.grid_x],
            [example.grid_y, example.grid_y + radius * 1.35],
            color="#8a8f98",
            linewidth=1.0,
            linestyle="--",
            zorder=6,
        )
        label = f"R reads {angle_from_east:.0f} deg from North"
        label_angle = math.radians((theta1 + theta2) / 2.0)
    else:
        theta1, theta2 = sorted((0.0, angle_from_east))
        ax.plot(
            [example.grid_x, example.grid_x + radius * 1.35],
            [example.grid_y, example.grid_y],
            color="#8a8f98",
            linewidth=1.0,
            linestyle="--",
            zorder=6,
        )
        label = f"{angle_from_east:.0f} deg from East"
        label_angle = math.radians((theta1 + theta2) / 2.0)
    ax.add_patch(
        Arc(
            (example.grid_x, example.grid_y),
            2.0 * radius,
            2.0 * radius,
            theta1=theta1,
            theta2=theta2,
            color="#4a5564",
            linewidth=1.1,
            zorder=7,
        )
    )
    ax.text(
        example.grid_x + math.cos(label_angle) * radius * 1.1,
        example.grid_y + math.sin(label_angle) * radius * 1.1,
        label,
        fontsize=7.5,
        ha="center",
        va="center",
        color="#30343b",
        zorder=8,
        bbox={"facecolor": "white", "edgecolor": "none", "alpha": 0.82, "pad": 1.2},
    )


def annotate_target_direction(
    ax: plt.Axes,
    example: SelectedExample,
    *,
    compact: bool = False,
) -> None:
    """Draw and label the North-referenced grid-to-AC bearing."""
    ax.annotate(
        "",
        xy=(example.ac_x, example.ac_y),
        xytext=(example.grid_x, example.grid_y),
        arrowprops={
            "arrowstyle": "-|>",
            "color": "#20242a",
            "linewidth": 1.8,
            "mutation_scale": 12,
        },
        zorder=7,
    )
    midpoint_x = (example.grid_x + example.ac_x) / 2.0
    midpoint_y = (example.grid_y + example.ac_y) / 2.0
    label = (
        f"AC direction = {example.target_bearing:.1f} deg\n"
        "clockwise from North"
    )
    ax.annotate(
        label,
        xy=(midpoint_x, midpoint_y),
        xytext=(5, 4 if compact else 7),
        textcoords="offset points",
        fontsize=6.6 if compact else 7.2,
        color="#20242a",
        ha="left",
        va="bottom",
        bbox={
            "facecolor": "white",
            "edgecolor": "none",
            "alpha": 0.82,
            "pad": 1.0,
        },
        zorder=8,
    )


def draw_compass_axes(ax: plt.Axes) -> None:
    """Add small North and East arrows to remove axis ambiguity."""
    ax.annotate(
        "",
        xy=(0.91, 0.22),
        xytext=(0.91, 0.10),
        xycoords="axes fraction",
        textcoords="axes fraction",
        arrowprops={"arrowstyle": "-|>", "color": "#515862", "linewidth": 1.0},
    )
    ax.text(
        0.91,
        0.235,
        "N",
        transform=ax.transAxes,
        ha="center",
        va="bottom",
        fontsize=7,
        color="#515862",
    )
    ax.annotate(
        "",
        xy=(0.98, 0.10),
        xytext=(0.91, 0.10),
        xycoords="axes fraction",
        textcoords="axes fraction",
        arrowprops={"arrowstyle": "-|>", "color": "#515862", "linewidth": 1.0},
    )
    ax.text(
        0.99,
        0.10,
        "E",
        transform=ax.transAxes,
        ha="left",
        va="center",
        fontsize=7,
        color="#515862",
    )


def create_figure(
    example: SelectedExample,
    wind_angles: Sequence[float],
    figure_pdf: Path,
    figure_png: Path,
) -> pd.DataFrame:
    minx, miny, maxx, maxy = example.ac_geometry.bounds
    span = max(maxx - minx, maxy - miny)
    radius = span * 2.5
    arrow_length = span * 0.28
    arc_radius = span * 0.095
    displayed_directions = [
        direction
        for angle in wind_angles
        for direction in (
            mathematical_to_compass_toward(angle),
            angle % 360.0,
        )
    ]
    arrow_endpoints = [
        (
            example.grid_x + math.sin(math.radians(direction)) * arrow_length,
            example.grid_y + math.cos(math.radians(direction)) * arrow_length,
        )
        for direction in displayed_directions
    ]
    padding = span * 0.07
    extent = (
        min([minx, *[point[0] for point in arrow_endpoints]]) - padding,
        max([maxx, *[point[0] for point in arrow_endpoints]]) + padding,
        min([miny, *[point[1] for point in arrow_endpoints]]) - padding,
        max([maxy, *[point[1] for point in arrow_endpoints]]) + padding,
    )

    rows: list[dict[str, object]] = []
    for angle in wind_angles:
        correct_compass = mathematical_to_compass_toward(angle)
        legacy_compass = angle % 360.0
        correct_difference = circular_separation(
            example.target_bearing, correct_compass
        )
        legacy_difference = circular_separation(
            example.target_bearing, legacy_compass
        )
        rows.append(
            {
                "wind_angle_from_east": angle,
                "correct_compass_toward": correct_compass,
                "legacy_compass_interpretation": legacy_compass,
                "target_compass_bearing": example.target_bearing,
                "correct_difference": correct_difference,
                "legacy_difference": legacy_difference,
                "correct_classification": (
                    "Downwind" if correct_difference < 90.0 else "Upwind"
                ),
                "legacy_classification": (
                    "Downwind" if legacy_difference < 90.0 else "Upwind"
                ),
            }
        )
    scenarios = pd.DataFrame(rows)

    plt.rcParams.update(
        {
            "font.family": "DejaVu Sans",
            "font.size": 9,
            "axes.titlesize": 10,
            "axes.titleweight": "bold",
        }
    )
    fig, axes = plt.subplots(2, 2, figsize=(10.8, 8.4), constrained_layout=True)
    panel_labels = ("a", "b", "c", "d")
    panel_index = 0
    for row_index, scenario in scenarios.iterrows():
        angle = float(scenario["wind_angle_from_east"])
        for column_index, legacy in enumerate((False, True)):
            ax = axes[row_index, column_index]
            direction = float(
                scenario[
                    "legacy_compass_interpretation"
                    if legacy
                    else "correct_compass_toward"
                ]
            )
            difference = float(
                scenario["legacy_difference" if legacy else "correct_difference"]
            )
            classification = str(
                scenario[
                    "legacy_classification" if legacy else "correct_classification"
                ]
            )
            halfplane = halfplane_polygon(
                example.grid_x, example.grid_y, direction, radius
            )
            downwind_ac = example.ac_geometry.intersection(halfplane)
            if not downwind_ac.is_empty:
                plot_geometry(
                    ax,
                    downwind_ac,
                    color="#f5b9ae" if legacy else "#b9d9f4",
                    alpha=0.62,
                    edgecolor="none",
                    zorder=1,
                )
            plot_geometry(
                ax,
                example.ac_geometry,
                facecolor="none",
                edgecolor="#4d5560",
                linewidth=1.2,
                zorder=2,
            )
            plot_geometry(
                ax,
                example.grid_geometry,
                facecolor="#f2cb67",
                edgecolor="#8a6819",
                linewidth=0.9,
                alpha=0.9,
                zorder=4,
            )
            annotate_target_direction(ax, example)
            theta = math.radians(direction)
            wind_dx = math.sin(theta) * arrow_length
            wind_dy = math.cos(theta) * arrow_length
            ax.annotate(
                "",
                xy=(example.grid_x + wind_dx, example.grid_y + wind_dy),
                xytext=(example.grid_x, example.grid_y),
                arrowprops={
                    "arrowstyle": "-|>",
                    "color": "#c94232" if legacy else "#1769aa",
                    "linewidth": 2.5,
                    "mutation_scale": 14,
                },
                zorder=8,
            )
            ax.scatter(
                [example.grid_x],
                [example.grid_y],
                s=26,
                color="#8a6819",
                edgecolor="white",
                linewidth=0.6,
                zorder=9,
            )
            ax.scatter(
                [example.ac_x],
                [example.ac_y],
                s=40,
                marker="D",
                color="#20242a",
                edgecolor="white",
                linewidth=0.6,
                zorder=9,
            )
            draw_angle_arc(ax, example, angle, legacy, arc_radius)
            interpretation = "Legacy R interpretation" if legacy else "Correct geometry"
            ax.set_title(
                f"({panel_labels[panel_index]}) Input {angle:.0f} deg from East: {interpretation}"
            )
            panel_index += 1
            result_color = "#a12622" if legacy and classification == "Downwind" else "#245c3a"
            ax.text(
                0.02,
                0.02,
                f"{classification.upper()}  |  angular separation = {difference:.0f} deg",
                transform=ax.transAxes,
                fontsize=8.5,
                fontweight="bold",
                color=result_color,
                ha="left",
                va="bottom",
                bbox={"facecolor": "white", "edgecolor": result_color, "alpha": 0.92, "pad": 3.0},
                zorder=10,
            )
            draw_compass_axes(ax)
            ax.set_xlim(extent[0], extent[1])
            ax.set_ylim(extent[2], extent[3])
            ax.set_aspect("equal")
            ax.axis("off")

    legend = [
        Patch(facecolor="#b9d9f4", edgecolor="none", label="Correct downwind half of AC"),
        Patch(facecolor="#f5b9ae", edgecolor="none", label="Legacy-R downwind half of AC"),
        Patch(facecolor="#f2cb67", edgecolor="#8a6819", label="Selected grid"),
        Line2D([0], [0], marker="D", color="none", markerfacecolor="#20242a", label="AC representative point"),
        Line2D([0], [0], color="#20242a", linewidth=1.8, label="Grid-to-AC direction (165 deg compass)"),
        Line2D([0], [0], color="#1769aa", linewidth=2.5, label="Correct wind vector"),
        Line2D([0], [0], color="#c94232", linewidth=2.5, label="Numeric angle misread as compass bearing"),
    ]
    fig.legend(
        handles=legend,
        loc="outside lower center",
        ncol=3,
        frameon=False,
        fontsize=8,
    )
    fig.suptitle(
        "Same numeric angle, different reference axis: why the legacy classification fails",
        fontsize=13,
        fontweight="bold",
    )
    fig.savefig(figure_pdf, bbox_inches="tight")
    fig.savefig(figure_png, dpi=220, bbox_inches="tight")
    plt.close(fig)
    return scenarios


def map_extent(
    example: SelectedExample,
    directions: Sequence[float],
    arrow_length: float,
) -> tuple[float, float, float, float]:
    minx, miny, maxx, maxy = example.ac_geometry.bounds
    span = max(maxx - minx, maxy - miny)
    endpoints = [
        (
            example.grid_x + math.sin(math.radians(direction)) * arrow_length,
            example.grid_y + math.cos(math.radians(direction)) * arrow_length,
        )
        for direction in directions
    ]
    padding = span * 0.07
    return (
        min([minx, *[point[0] for point in endpoints]]) - padding,
        max([maxx, *[point[0] for point in endpoints]]) + padding,
        min([miny, *[point[1] for point in endpoints]]) - padding,
        max([maxy, *[point[1] for point in endpoints]]) + padding,
    )


def draw_wind_arrow(
    ax: plt.Axes,
    example: SelectedExample,
    compass_direction: float,
    arrow_length: float,
    color: str,
) -> None:
    theta = math.radians(compass_direction)
    ax.annotate(
        "",
        xy=(
            example.grid_x + math.sin(theta) * arrow_length,
            example.grid_y + math.cos(theta) * arrow_length,
        ),
        xytext=(example.grid_x, example.grid_y),
        arrowprops={
            "arrowstyle": "-|>",
            "color": color,
            "linewidth": 2.5,
            "mutation_scale": 14,
        },
        zorder=9,
    )


def draw_grid_and_ac_points(ax: plt.Axes, example: SelectedExample) -> None:
    plot_geometry(
        ax,
        example.grid_geometry,
        facecolor="#f2cb67",
        edgecolor="#8a6819",
        linewidth=0.9,
        alpha=0.92,
        zorder=5,
    )
    ax.scatter(
        [example.grid_x],
        [example.grid_y],
        s=26,
        color="#8a6819",
        edgecolor="white",
        linewidth=0.6,
        zorder=10,
    )
    ax.scatter(
        [example.ac_x],
        [example.ac_y],
        s=40,
        marker="D",
        color="#20242a",
        edgecolor="white",
        linewidth=0.6,
        zorder=10,
    )


def create_actual_area_figure(
    example: SelectedExample,
    observations: Sequence[AreaObservation],
    figure_pdf: Path,
    figure_png: Path,
) -> None:
    """Compare stored legacy areas with exact corrected areas for two months."""
    minx, miny, maxx, maxy = example.ac_geometry.bounds
    span = max(maxx - minx, maxy - miny)
    arrow_length = span * 0.28
    all_directions = [
        direction
        for observation in observations
        for direction in (
            observation.angle_from_east % 360.0,
            observation.correct_compass_toward,
        )
    ]
    extent = map_extent(example, all_directions, arrow_length)
    fig, axes = plt.subplots(2, 2, figsize=(10.8, 8.4), constrained_layout=True)
    panel_labels = ("a", "b", "c", "d")
    panel_index = 0
    for row_index, observation in enumerate(observations):
        for column_index, corrected in enumerate((False, True)):
            ax = axes[row_index, column_index]
            if corrected:
                direction = observation.correct_compass_toward
                down_area = observation.corrected_downwind_area
                up_area = observation.corrected_upwind_area
                flag = observation.corrected_downup_ac_area
                shade = "#a9d2ef"
                line_color = "#1769aa"
                method = "Corrected convention"
                direction_text = (
                    f"wind: {observation.angle_from_east:.1f} deg from East"
                    f"  ->  {direction:.1f} deg compass"
                )
            else:
                direction = observation.angle_from_east % 360.0
                down_area = observation.stored_downwind_area
                up_area = observation.stored_upwind_area
                flag = observation.stored_downup_ac_area
                shade = "#f2afa5"
                line_color = "#c94232"
                method = "Stored legacy result"
                direction_text = (
                    f"wind: {observation.angle_from_east:.1f} deg from East"
                    f" misread as {direction:.1f} deg compass"
                )
            _, _, downwind_geometry = directional_area(example, direction)
            plot_geometry(
                ax,
                example.ac_geometry,
                facecolor="#f4f1e9",
                edgecolor="#4d5560",
                linewidth=1.2,
                zorder=1,
            )
            if not downwind_geometry.is_empty:
                plot_geometry(
                    ax,
                    downwind_geometry,
                    color=shade,
                    alpha=0.78,
                    edgecolor="none",
                    zorder=2,
                )
            plot_geometry(
                ax,
                example.ac_geometry,
                facecolor="none",
                edgecolor="#4d5560",
                linewidth=1.2,
                zorder=3,
            )
            draw_grid_and_ac_points(ax, example)
            annotate_target_direction(ax, example, compact=True)
            draw_wind_arrow(
                ax, example, direction, arrow_length, line_color
            )
            draw_compass_axes(ax)
            ax.set_title(
                f"({panel_labels[panel_index]}) {method}: "
                f"{observation.year}-{observation.month:02d}"
            )
            panel_index += 1
            ax.text(
                0.02,
                0.98,
                direction_text,
                transform=ax.transAxes,
                fontsize=7.5,
                color=line_color,
                ha="left",
                va="top",
                bbox={
                    "facecolor": "white",
                    "edgecolor": line_color,
                    "alpha": 0.92,
                    "pad": 2.2,
                },
                zorder=11,
            )
            ax.text(
                0.02,
                0.02,
                f"downwind = {down_area:.1f} km2 | upwind = {up_area:.1f} km2\n"
                f"downup_ac_area = {flag}",
                transform=ax.transAxes,
                fontsize=8.5,
                fontweight="bold",
                color=line_color,
                ha="left",
                va="bottom",
                bbox={
                    "facecolor": "white",
                    "edgecolor": line_color,
                    "alpha": 0.94,
                    "pad": 3.0,
                },
                zorder=11,
            )
            ax.set_xlim(extent[0], extent[1])
            ax.set_ylim(extent[2], extent[3])
            ax.set_aspect("equal")
            ax.axis("off")

    fig.legend(
        handles=[
            Patch(facecolor="#f2afa5", label="Area stored as downwind"),
            Patch(facecolor="#a9d2ef", label="Corrected downwind area"),
            Patch(facecolor="#f4f1e9", edgecolor="#4d5560", label="Upwind remainder"),
            Line2D(
                [0],
                [0],
                color="#20242a",
                linewidth=1.8,
                label="AC direction: clockwise from North",
            ),
        ],
        loc="outside lower center",
        ncol=2,
        frameon=False,
        fontsize=8,
    )
    fig.suptitle(
        "Actual downup_ac_area values versus the corrected classifications",
        fontsize=13,
        fontweight="bold",
    )
    fig.savefig(figure_pdf, bbox_inches="tight")
    fig.savefig(figure_png, dpi=220, bbox_inches="tight")
    plt.close(fig)


def create_square_method_figure(
    example: SelectedExample,
    observation: AreaObservation,
    figure_pdf: Path,
    figure_png: Path,
) -> None:
    """Show the complementary square construction used for exact AC areas."""
    direction = observation.correct_compass_toward
    opposite_direction = (direction + 180.0) % 360.0
    radius = halfplane_radius(example)
    down_square = halfplane_polygon(
        example.grid_x, example.grid_y, direction, radius
    )
    up_square = halfplane_polygon(
        example.grid_x, example.grid_y, opposite_direction, radius
    )
    down_intersection = example.ac_geometry.intersection(down_square)
    up_intersection = example.ac_geometry.intersection(up_square)
    minx, miny, maxx, maxy = example.ac_geometry.bounds
    span = max(maxx - minx, maxy - miny)
    arrow_length = span * 0.28
    extent = map_extent(example, [direction, opposite_direction], arrow_length)
    fig, axes = plt.subplots(1, 3, figsize=(12.6, 4.6), constrained_layout=True)

    first = axes[0]
    first.add_patch(
        MplPolygon(
            np.asarray(up_square.exterior.coords),
            closed=True,
            facecolor="#f7df9b",
            edgecolor="#bc8d1c",
            linewidth=1.1,
            alpha=0.38,
            zorder=1,
        )
    )
    first.add_patch(
        MplPolygon(
            np.asarray(down_square.exterior.coords),
            closed=True,
            facecolor="#a9d2ef",
            edgecolor="#1769aa",
            linewidth=1.1,
            alpha=0.45,
            zorder=2,
        )
    )
    theta = math.radians(direction)
    tangent_x, tangent_y = math.cos(theta), -math.sin(theta)
    first.plot(
        [
            example.grid_x - tangent_x * span,
            example.grid_x + tangent_x * span,
        ],
        [
            example.grid_y - tangent_y * span,
            example.grid_y + tangent_y * span,
        ],
        color="#30343b",
        linestyle="--",
        linewidth=1.4,
        zorder=5,
    )
    plot_geometry(
        first,
        example.ac_geometry,
        facecolor="none",
        edgecolor="#4d5560",
        linewidth=1.3,
        zorder=4,
    )
    draw_grid_and_ac_points(first, example)
    draw_wind_arrow(first, example, direction, arrow_length, "#1769aa")
    first.text(
        0.02,
        0.98,
        "Two large squares share a boundary\nperpendicular to the wind vector",
        transform=first.transAxes,
        ha="left",
        va="top",
        fontsize=7.8,
        bbox={"facecolor": "white", "edgecolor": "none", "alpha": 0.88},
        zorder=10,
    )
    first.set_title("(a) Construct downwind and upwind squares")

    for ax, geometry, color, title, area in (
        (
            axes[1],
            down_intersection,
            "#a9d2ef",
            "(b) AC intersect downwind square",
            observation.corrected_downwind_area,
        ),
        (
            axes[2],
            up_intersection,
            "#f7df9b",
            "(c) AC intersect upwind square",
            observation.corrected_upwind_area,
        ),
    ):
        plot_geometry(
            ax,
            example.ac_geometry,
            facecolor="#f4f1e9",
            edgecolor="#4d5560",
            linewidth=1.2,
            zorder=1,
        )
        if not geometry.is_empty:
            plot_geometry(
                ax,
                geometry,
                color=color,
                alpha=0.85,
                edgecolor="none",
                zorder=2,
            )
        plot_geometry(
            ax,
            example.ac_geometry,
            facecolor="none",
            edgecolor="#4d5560",
            linewidth=1.2,
            zorder=3,
        )
        draw_grid_and_ac_points(ax, example)
        ax.text(
            0.02,
            0.02,
            f"exact intersection area = {area:.1f} km2",
            transform=ax.transAxes,
            ha="left",
            va="bottom",
            fontsize=8.2,
            fontweight="bold",
            bbox={
                "facecolor": "white",
                "edgecolor": "#4d5560",
                "alpha": 0.92,
                "pad": 2.5,
            },
            zorder=10,
        )
        ax.set_title(title)

    for ax in axes:
        ax.set_xlim(extent[0], extent[1])
        ax.set_ylim(extent[2], extent[3])
        ax.set_aspect("equal")
        ax.axis("off")
    axes[2].text(
        0.02,
        0.98,
        f"{observation.corrected_downwind_area:.2f} < "
        f"{observation.corrected_upwind_area:.2f}, so corrected\n"
        f"downup_ac_area = {observation.corrected_downup_ac_area}",
        transform=axes[2].transAxes,
        ha="left",
        va="top",
        fontsize=8.0,
        fontweight="bold",
        color="#245c3a",
        bbox={
            "facecolor": "white",
            "edgecolor": "#245c3a",
            "alpha": 0.94,
            "pad": 2.4,
        },
        zorder=10,
    )
    fig.legend(
        handles=[
            Patch(facecolor="#a9d2ef", edgecolor="#1769aa", label="Downwind square / intersection"),
            Patch(facecolor="#f7df9b", edgecolor="#bc8d1c", label="Upwind square / intersection"),
            Line2D([0], [0], color="#30343b", linestyle="--", label="Perpendicular dividing line"),
        ],
        loc="outside lower center",
        ncol=3,
        frameon=False,
        fontsize=8,
    )
    fig.suptitle(
        f"Corrected two-square method ({observation.year}-{observation.month:02d}, "
        f"wind = {observation.angle_from_east:.1f} deg from East)",
        fontsize=12.5,
        fontweight="bold",
    )
    fig.savefig(figure_pdf, bbox_inches="tight")
    fig.savefig(figure_png, dpi=220, bbox_inches="tight")
    plt.close(fig)


def latex_escape(value: object) -> str:
    text = str(value)
    replacements = {
        "\\": r"\textbackslash{}",
        "&": r"\&",
        "%": r"\%",
        "$": r"\$",
        "#": r"\#",
        "_": r"\_",
        "{": r"\{",
        "}": r"\}",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    return text


def report_source(
    example: SelectedExample,
    scenarios: pd.DataFrame,
    figure_pdf: Path,
    area_observations: Sequence[AreaObservation],
    area_summary: dict[str, int],
    actual_area_figure_pdf: Path,
    square_method_figure_pdf: Path,
) -> str:
    rows = []
    for _, row in scenarios.iterrows():
        correct = str(row["correct_classification"])
        legacy = str(row["legacy_classification"])
        if correct != legacy:
            legacy = r"\textbf{" + legacy + " (WRONG)}"
        rows.append(
            "{angle:.0f} & {correct_bearing:.0f} & {legacy_bearing:.0f} & "
            "{target:.1f} & {correct_difference:.0f} & {legacy_difference:.0f} & "
            "{correct} & {legacy} \\\\".format(
                angle=float(row["wind_angle_from_east"]),
                correct_bearing=float(row["correct_compass_toward"]),
                legacy_bearing=float(row["legacy_compass_interpretation"]),
                target=float(row["target_compass_bearing"]),
                correct_difference=float(row["correct_difference"]),
                legacy_difference=float(row["legacy_difference"]),
                correct=correct,
                legacy=legacy,
            )
        )
    table_rows = "\n".join(rows)
    area_rows = []
    for observation in area_observations:
        stored_flag = str(observation.stored_downup_ac_area)
        corrected_flag = str(observation.corrected_downup_ac_area)
        if stored_flag != corrected_flag:
            stored_flag = r"\textbf{" + stored_flag + " (WRONG)}"
            corrected_flag = r"\textbf{" + corrected_flag + "}"
        area_rows.append(
            "{year}-{month:02d} & {angle:.1f} & {stored_down:.1f} & "
            "{stored_up:.1f} & {stored_flag} & {compass:.1f} & "
            "{corrected_down:.1f} & {corrected_up:.1f} & "
            "{corrected_flag} \\\\".format(
                year=observation.year,
                month=observation.month,
                angle=observation.angle_from_east,
                stored_down=observation.stored_downwind_area,
                stored_up=observation.stored_upwind_area,
                stored_flag=stored_flag,
                compass=observation.correct_compass_toward,
                corrected_down=observation.corrected_downwind_area,
                corrected_up=observation.corrected_upwind_area,
                corrected_flag=corrected_flag,
            )
        )
    actual_area_rows = "\n".join(area_rows)
    figure_name = latex_escape(figure_pdf.name)
    actual_area_figure_name = latex_escape(actual_area_figure_pdf.name)
    square_method_figure_name = latex_escape(square_method_figure_pdf.name)
    assembly = latex_escape(example.assembly)
    district = latex_escape(example.district)
    province = latex_escape(example.province)
    return rf"""\documentclass[10pt]{{article}}
\usepackage{{graphicx}}
\setlength{{\textwidth}}{{6.85in}}
\setlength{{\oddsidemargin}}{{-0.18in}}
\setlength{{\evensidemargin}}{{-0.18in}}
\setlength{{\textheight}}{{9.45in}}
\setlength{{\topmargin}}{{-0.65in}}
\setlength{{\parindent}}{{0pt}}
\setlength{{\parskip}}{{0.4em}}
\setlength{{\emergencystretch}}{{3em}}
\title{{\textbf{{Wind Direction Convention Error in the Downwind/Upwind Construction}}}}
\author{{Reproducible diagnostic for the bureaucrats and farms project}}
\date{{August 2026}}

\begin{{document}}
\maketitle

\section*{{Executive finding}}
The legacy pipeline combines two angular coordinate systems without converting
between them. The wind variable is constructed with
$\mathrm{{atan2}}(v,u)$, which is a mathematical angle measured
counterclockwise from \textbf{{East}}. The geographic functions
\texttt{{geosphere::bearing()}} and \texttt{{geosphere::destPoint()}} interpret
their angles as compass bearings measured clockwise from \textbf{{North}}. Both values are
expressed in degrees, but they are not directly comparable.

This is not a cosmetic labeling issue. In the second scenario below, the true
wind points northwest and the AC representative point lies south-southeast of
the grid, so the representative point is unambiguously upwind. The legacy code
instead interprets the same numeric value as a southeast-pointing wind and
classifies the representative point as downwind.

\section*{{A real project example}}
The script searches the project shapefiles rather than inventing coordinates.
It selects grid \textbf{{{example.unique_small_grid_id}}} in the
\textbf{{{assembly}}} assembly constituency
(AC ID \textbf{{{example.ac_uq_id}}}), {district}, {province}. The grid centroid
is {example.distance_km:.2f} km from the AC representative point. The compass
bearing from the grid centroid to that point is
\textbf{{{example.target_bearing:.3f}$^\circ$}}, effectively the requested
165$^\circ$ example.

For a mathematical angle $\alpha$ measured from East, the corresponding
clockwise-from-North direction toward which the wind travels is
\[
  B_{{\mathrm{{toward}}}} = (90^\circ - \alpha) \bmod 360^\circ.
\]
The legacy code instead uses the numeric value $\alpha$ directly as if it were
a compass bearing.

\begin{{table}}[ht]
\centering
\small
\resizebox{{\textwidth}}{{!}}{{%
\begin{{tabular}}{{rrrrrrll}}
\hline
$\alpha$ from East & Correct compass & Legacy compass & AC bearing &
$\Delta$ correct & $\Delta$ legacy & Correct & Legacy \\
\hline
{table_rows}
\hline
\end{{tabular}}
}}
\caption{{Angles and classifications. A point is downwind only when its circular
angular separation from the wind-toward direction is less than 90$^\circ$.}}
\end{{table}}

\clearpage
\begin{{figure}}[p]
\centering
\includegraphics[width=\textwidth]{{{figure_name}}}
\caption{{Four views of the same real AC/grid pair. Blue panels use the correct
conversion from an East-referenced mathematical angle to a compass bearing.
Red panels reproduce the legacy interpretation. The shaded portion is the AC
half-plane labeled downwind; the black arrow points from the grid to the AC
representative point. With a 55$^\circ$ input, both procedures call the point
upwind, but only by chance. With a 135$^\circ$ input, the correct wind points
northwest while the legacy interpretation points southeast, producing the
incorrect downwind classification.}}
\end{{figure}}
\clearpage

\section*{{What is actually stored in \texttt{{downup\_ac\_area}}}}
The area indicator is defined as 1 when the area stored as downwind is larger
than the area stored as upwind, and 0 otherwise. The diagnostic script reads
the actual area parquet, selects the same real grid, and recomputes both
half-plane intersections from the shapefile. Treating the raw wind number as a
North-referenced compass bearing reproduces the stored areas to within
$10^{{-6}}$ km$^2$. This proves that the convention error is present in the
saved data, not only in a hypothetical reconstruction.

\begin{{table}}[ht]
\centering
\scriptsize
\resizebox{{\textwidth}}{{!}}{{%
\begin{{tabular}}{{rrrrrrrrr}}
\hline
Period & Wind from East & Stored down & Stored up & Stored flag &
Correct compass & Correct down & Correct up & Correct flag \\
\hline
{actual_area_rows}
\hline
\end{{tabular}}
}}
\caption{{Actual saved areas and classifications versus exact corrected
intersections. Areas are in km$^2$; \texttt{{downup\_ac\_area}} equals 1
when downwind area is larger than upwind area.}}
\end{{table}}

For this selected grid, {area_summary['disagreements']} of
{area_summary['rows']} nonmissing monthly observations change classification.
The complete stored-by-corrected count is:
\begin{{center}}
\begin{{tabular}}{{lrr}}
\hline
 & Corrected 0 & Corrected 1 \\
\hline
Stored 0 & {area_summary['stored_0_corrected_0']} &
{area_summary['stored_0_corrected_1']} \\
Stored 1 & {area_summary['stored_1_corrected_0']} &
{area_summary['stored_1_corrected_1']} \\
\hline
\end{{tabular}}
\end{{center}}
These counts describe this one diagnostic grid only; they are not an estimate
of the error rate in the full sample.

\section*{{Why the negative angle is also misclassified}}
In March 2017, the stored raw direction is
{area_observations[1].angle_from_east:.3f}$^\circ$ from East. A negative
Cartesian angle is valid: it points clockwise below the East axis. The correct
compass-toward direction is
$(90-({area_observations[1].angle_from_east:.3f}))\bmod 360=
{area_observations[1].correct_compass_toward:.3f}^\circ$. The legacy code
instead normalizes the unconverted number to
{area_observations[1].angle_from_east % 360.0:.3f}$^\circ$ and reads it from
North. It therefore stores \texttt{{downup\_ac\_area}} =
{area_observations[1].stored_downup_ac_area}, whereas the corrected majority-area
classification is {area_observations[1].corrected_downup_ac_area}.

\clearpage
\begin{{figure}}[p]
\centering
\includegraphics[width=\textwidth]{{{actual_area_figure_name}}}
\caption{{The values actually stored in the parquet (left column) versus
the corrected calculations (right column). The first row is a positive wind
angle; the second row is a negative wind angle. In every panel the black arrow
to the AC representative point is a compass bearing measured clockwise from
North. The wind input printed at the top is a mathematical angle measured from
East. Red shading is the area stored as downwind; blue shading is the corrected
downwind area. Both examples reverse \texttt{{downup\_ac\_area}}.}}
\end{{figure}}
\clearpage

\section*{{Corrected two-square area method}}
The corrected method first converts the wind angle to the compass-toward
direction $B$. At the focal grid centroid $p$, define the unit wind vector
$w=(\sin B,\cos B)$ and its perpendicular tangent
$t=(\cos B,-\sin B)$. A large downwind square has corners

\[
p-Rt,\quad p+Rt,\quad p+Rt+2Rw,\quad p-Rt+2Rw,
\]

and the upwind square is constructed in the opposite direction, using $-w$.
The radius $R$ is chosen larger than the maximum distance from the grid
centroid to the AC bounds. Therefore, the two squares cover the two complete
halves of the AC and share only the perpendicular dividing line.

The exact areas are then
\[
A_{{down}}=\mathrm{{area}}(AC\cap S_{{down}}),\qquad
A_{{up}}=\mathrm{{area}}(AC\cap S_{{up}}),\qquad
\texttt{{downup\_ac\_area}}=\mathbf{{1}}[A_{{down}}>A_{{up}}].
\]
This construction is equivalent to clipping the AC by complementary
half-planes, but showing the two finite squares makes the implementation and
area accounting explicit.

\begin{{figure}}[ht]
\centering
\includegraphics[width=\textwidth]{{{square_method_figure_name}}}
\caption{{The corrected two-square construction for the July 2017 example.
Panel (a) shows the complementary squares and their shared line, which is
perpendicular to the corrected wind vector. Panels (b) and (c) show the exact
AC intersections whose areas determine the binary classification.}}
\end{{figure}}
\clearpage

\section*{{Where the error enters}}
The wind-cleaning code calculates
\begin{{verbatim}}
wind_direction = atan2(v10, u10) * 180 / pi
\end{{verbatim}}
This returns a Cartesian angle: 0$^\circ$ is East, 90$^\circ$ is North,
180$^\circ$ is West, and -90$^\circ$ is South. The downstream R code then uses
\begin{{verbatim}}
angle1 = wind_direction + 90
angle2 = wind_direction - 90
destPoint(grid_centroid, angle1, ...)
bearing_relative = bearing(grid_centroid, ac_point)
\end{{verbatim}}
Here, 0$^\circ$ is North and 90$^\circ$ is East. The subsequent numeric
comparison therefore mixes an East-referenced angle with a North-referenced
bearing. In addition, ordinary inequalities do not correctly handle intervals
that cross 0$^\circ$/360$^\circ$.

\section*{{Required correction}}
The wind should first be represented as a compass direction toward which the
air moves:
\begin{{verbatim}}
wind_direction_to = (atan2(u10, v10) * 180 / pi + 360) %% 360
\end{{verbatim}}
The downwind test should use circular angular distance:
\begin{{verbatim}}
angle_difference = ((bearing_relative - wind_direction_to + 180) %% 360) - 180
downwind = as.integer(abs(angle_difference) < 90)
\end{{verbatim}}
Monthly and rolling directions should also use circular means, preferably by
aggregating vector components, rather than arithmetic means of degree values.
For example, the arithmetic mean of 359$^\circ$ and 1$^\circ$ is 180$^\circ$,
while their circular mean is 0$^\circ$.

\section*{{Implications for existing outputs}}
\begin{{itemize}}
  \item The population and area routines can agree with each other while both
        label the wrong geographical half-plane.
  \item Existing \texttt{{downup\_ac\_pop}} and \texttt{{downup\_ac\_area}}
        values should not be treated as directionally validated.
  \item Corrected wind directions require regenerating the wind panel,
        population measures, area measures, master dataset, and stacked data.
  \item Cardinal and diagonal unit tests should be retained so that East,
        North, West, South, 55$^\circ$, and 135$^\circ$ cannot silently change
        convention again.
\end{{itemize}}

\section*{{Source documentation}}
ECMWF defines positive $u$ as west-to-east flow and positive $v$ as
south-to-north flow. See
\begin{{flushleft}}\small\ttfamily
\detokenize{{https://confluence.ecmwf.int/spaces/FCST/pages/111155337/}}
\end{{flushleft}}
ECMWF's discussion of meteorological wind angles and the special care required
with \texttt{{atan2}} is available at
\begin{{flushleft}}\small\ttfamily
\detokenize{{https://confluence.ecmwf.int/pages/viewpage.action?pageId=226500971}}
\end{{flushleft}}

\end{{document}}
"""


def compile_report(tex_path: Path) -> Path:
    pdflatex = shutil.which("pdflatex")
    if not pdflatex:
        raise FileNotFoundError(
            "pdflatex was not found. Rerun with --no-compile to create only "
            "the figure and LaTeX source."
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
    for source in (
        args.panel,
        args.area_panel,
        args.ac_shapefile,
        args.grid_shapefile,
    ):
        if not source.is_file():
            raise FileNotFoundError(source)
    output_directory = args.output_directory.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)
    stem = "wind_direction_convention_error"
    figure_pdf = output_directory / f"{stem}_figure.pdf"
    figure_png = output_directory / f"{stem}_figure.png"
    actual_area_figure_pdf = output_directory / f"{stem}_actual_area_figure.pdf"
    actual_area_figure_png = output_directory / f"{stem}_actual_area_figure.png"
    square_method_figure_pdf = output_directory / f"{stem}_square_method_figure.pdf"
    square_method_figure_png = output_directory / f"{stem}_square_method_figure.png"
    tex_path = output_directory / f"{stem}.tex"
    report_pdf = output_directory / f"{stem}.pdf"
    final_targets = [
        figure_pdf,
        figure_png,
        actual_area_figure_pdf,
        actual_area_figure_png,
        square_method_figure_pdf,
        square_method_figure_png,
        tex_path,
    ]
    if not args.no_compile:
        final_targets.append(report_pdf)
    existing = [path for path in final_targets if path.exists()]
    if existing and not args.overwrite:
        raise FileExistsError(
            "Outputs already exist; pass --overwrite:\n"
            + "\n".join(str(path) for path in existing)
        )

    example = select_example(args)
    logging.info(
        "Selected grid=%s AC=%s assembly=%s bearing=%.3f distance=%.2f km",
        example.unique_small_grid_id,
        example.ac_uq_id,
        example.assembly,
        example.target_bearing,
        example.distance_km,
    )
    scenarios = create_figure(
        example, args.wind_angles, figure_pdf, figure_png
    )
    area_observations, area_summary = select_area_observations(args, example)
    create_actual_area_figure(
        example,
        area_observations,
        actual_area_figure_pdf,
        actual_area_figure_png,
    )
    create_square_method_figure(
        example,
        area_observations[0],
        square_method_figure_pdf,
        square_method_figure_png,
    )
    tex_path.write_text(
        report_source(
            example,
            scenarios,
            figure_pdf,
            area_observations,
            area_summary,
            actual_area_figure_pdf,
            square_method_figure_pdf,
        ),
        encoding="utf-8",
    )
    if not args.no_compile:
        compiled = compile_report(tex_path)
        logging.info("Completed PDF report: %s", compiled)
    logging.info("LaTeX source: %s", tex_path)
    logging.info(
        "Selected-grid stored/corrected area disagreements: %s of %s",
        area_summary["disagreements"],
        area_summary["rows"],
    )
    logging.info("Standalone figures: %s", output_directory)
    return 0


if __name__ == "__main__":
    sys.exit(main())

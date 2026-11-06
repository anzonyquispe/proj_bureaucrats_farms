#!/usr/bin/env python3
"""Build the grid-level first-protest file from ACLED (8_grids_ac_pr_5km.csv).

Script version of the computation in 8_grids_ac_pr_5km.ipynb. Protests are
ACLED events between 2020-06-01 and 2021-12-09 located inside an assembly
constituency. Each grid within 5 km of a protest receives its first protest
(``protest_id``), the protest area of that protest within its constituency
(``protest_place``) and the year and month of that protest
(``yr_pr_5km``, ``mt_pr_5km``).

Without --events, protests are selected by the notebook's keyword rule: an
associated actor or note containing a word that starts with "farm". With
--events, they are the ACLED rows whose ``event_id_cnty`` has --flag-col = 1 in
that file (e.g. the Gemini-based acled_protest2_events.csv). Duplicated ACLED
rows are kept in both modes, as in the notebook.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

import geopandas as gpd
import pandas as pd
from shapely.geometry import MultiPolygon, Polygon


SHARED_ROOT = Path("/groups/sgulzar/sa_fires")
START_DATE = pd.Timestamp("2020-06-01")
END_DATE = pd.Timestamp("2021-12-09")
BUFFER_METERS = 5000
METRIC_CRS = 7755
KEYWORD = r"\bfarm\w*"


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    intermediate = SHARED_ROOT / "proj_bureaucrats_farms" / "data_output" / "intermediate"
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument(
        "--acled",
        type=Path,
        default=SHARED_ROOT / "data" / "input" / "acled"
        / "2000-01-01-2025-05-13-South_Asia-India.csv",
    )
    parser.add_argument(
        "--acs", type=Path, default=intermediate / "_0_2_3_ACs_right_shapefile.shp"
    )
    parser.add_argument(
        "--grids",
        type=Path,
        default=SHARED_ROOT / "proj_downwind" / "data_output" / "intermediate"
        / "1-grid-generation.shp",
    )
    parser.add_argument("--events", type=Path, default=None)
    parser.add_argument("--flag-col", default="protest2")
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args(argv)


def select_protests(acled: Path, events: Path | None, flag_col: str) -> pd.DataFrame:
    protests = pd.read_csv(acled, sep=";")
    protests["event_date"] = pd.to_datetime(protests["event_date"], dayfirst=True)
    window = protests[
        (protests["event_date"] >= START_DATE) & (protests["event_date"] <= END_DATE)
    ].copy()
    if events is None:
        window["assoc_actor_1"] = window["assoc_actor_1"].str.lower()
        actor = window["assoc_actor_1"].str.contains(KEYWORD, na=False)
        notes = window["notes"].str.lower().str.contains(KEYWORD, na=False)
        return window[actor | notes].copy()

    flags = pd.read_csv(events, usecols=["event_id_cnty", flag_col])
    if flags["event_id_cnty"].duplicated().any():
        raise ValueError(f"{events} has duplicated event_id_cnty values.")
    selected = set(flags.loc[flags[flag_col] == 1, "event_id_cnty"])
    return window[window["event_id_cnty"].isin(selected)].copy()


def protest_areas(acs: gpd.GeoDataFrame, acs_pro: gpd.GeoDataFrame) -> gpd.GeoDataFrame:
    """Union of the 5 km buffers of each AC's protests, split into polygons."""
    pieces = []
    for ac_val in acs_pro["ac_uq_id"].unique().tolist():
        geom = acs_pro.query(f"ac_uq_id == {ac_val}").copy()
        geom_proj = geom.to_crs(epsg=METRIC_CRS)
        geom_proj["geometry"] = geom_proj.geometry.buffer(BUFFER_METERS)
        geom_proj = geom_proj.to_crs(epsg=4326)
        intersected = gpd.overlay(acs, geom_proj, how="intersection")
        if intersected.empty:
            continue
        # union_all replaces the deprecated unary_union from geopandas 1.0.
        unified = (
            intersected.union_all()
            if hasattr(intersected, "union_all")
            else intersected.unary_union
        )
        if isinstance(unified, Polygon):
            gdf = gpd.GeoDataFrame(geometry=[unified], crs=acs.crs)
        elif isinstance(unified, MultiPolygon):
            gdf = gpd.GeoDataFrame(geometry=list(unified.geoms), crs=acs.crs)
        else:
            continue
        gdf["ac_uq_id"] = ac_val
        pieces.append(gdf)
    combined = gpd.GeoDataFrame(pd.concat(pieces, ignore_index=True), geometry="geometry", crs=acs.crs)
    return combined.reset_index().rename(columns={"index": "protest_place"})


def build_grid_file(args: argparse.Namespace) -> pd.DataFrame:
    selected = select_protests(args.acled, args.events, args.flag_col)
    acs = gpd.read_file(args.acs)
    acs["area_ac"] = acs.to_crs(METRIC_CRS).area

    points = gpd.points_from_xy(selected.longitude, selected.latitude)
    protest_info = gpd.GeoDataFrame(selected, geometry=points, crs="EPSG:4326")
    acs_pro = gpd.overlay(protest_info, acs, keep_geom_type=True)
    acs_pro = acs_pro.reset_index(drop=True).reset_index().rename(columns={"index": "protest_id"})
    print(
        f"selected ACLED rows: {len(selected):,} | inside ACs: {len(acs_pro):,} "
        f"({acs_pro['event_id_cnty'].nunique():,} unique events)"
    )

    places = protest_areas(acs, acs_pro)

    grids = gpd.read_file(args.grids)
    protest_buffers = acs_pro.copy()
    protest_buffers["geometry"] = acs_pro.to_crs(METRIC_CRS).buffer(BUFFER_METERS).to_crs(4326)
    grids_protest = gpd.overlay(grids, protest_buffers)
    grids_protest["event_date"] = pd.to_datetime(grids_protest["event_date"])
    first = grids_protest.loc[grids_protest.groupby("unq_s__")["event_date"].idxmin()]
    grid_protest = first[["unq_s__", "protest_id", "event_date"]].copy()

    protest_place = gpd.overlay(acs_pro, places)
    protest_place = protest_place.query("ac_uq_id_1 == ac_uq_id_2")[["protest_id", "protest_place"]]

    out = grid_protest.merge(protest_place, on="protest_id", how="left")
    if not out["unq_s__"].is_unique:
        raise ValueError("A grid received more than one first protest.")
    out["yr_pr_5km"] = out["event_date"].dt.year
    out["mt_pr_5km"] = out["event_date"].dt.month
    return out.drop(columns="event_date")


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    out = build_grid_file(args)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(args.output, index=False)
    print(f"treated grids: {len(out):,} | protest areas: {out['protest_place'].nunique():,}")
    print(f"written: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

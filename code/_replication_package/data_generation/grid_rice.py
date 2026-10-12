#!/usr/bin/env python3
"""Build grid-cell rice production weights from MapSPAM 2010.

Mirror of ``grid_population.ipynb``, but the payload is rice production instead
of population. The output is the drop-in ``--grid-population`` input for
``build_downup_ac_pop_cluster.py --weight-column rice_prod_2010``, which then
classifies each grid's same-AC neighbours as upwind or downwind of it.

Two differences from the population notebook matter:

* MapSPAM pixels store **totals** (metric tonnes per pixel), not a density, so
  the extraction is a plain coverage-weighted ``sum``. The population raster is
  persons/km2 and needs ``sum(coverage_weight=area_spherical_km2)`` instead.
  Using the wrong branch rescales everything silently.
* Extraction is by exact fractional coverage. The AC-level notebook
  ``9_rice_info_ac_lvl.ipynb`` instead collapses each pixel to its centroid and
  does a point-in-polygon join, which drops up to half a pixel at every
  boundary. Do not copy that here: MapSPAM pixels are ~9.3 km against a ~2.2 km
  analysis grid, so centroid assignment would be badly lossy.

The rice band is ``P`` (production) ``RICE`` ``A`` (all technologies), the same
series the AC-level file uses through its ``RICE_A`` column.
"""

from __future__ import annotations

import argparse
import logging
import sys
import zipfile
from pathlib import Path

try:
    import geopandas as gpd
    import pandas as pd
    import rasterio
    from exactextract import exact_extract
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "This script requires geopandas, rasterio, pandas and exactextract."
    ) from exc


SA_FIRES = Path(
    r"C:\Users\rjbar\Saadgulzar Dropbox\rbarreraf@fen.uchile.cl\sa_fires"
)
DEFAULT_GRID = (
    SA_FIRES / "proj_downwind" / "data_output" / "intermediate"
    / "1-grid-generation.shp"
)
DEFAULT_SPAM_ZIP = (
    SA_FIRES / "data" / "input" / "crop-production-2010-mapspam"
    / "spam2010v2r0_global_prod.geotiff.zip"
)
RICE_BAND = "spam2010V2r0_global_P_RICE_A.tif"
# Written where the downup stages read from, not where grid_population.ipynb
# writes; that notebook targets proj_downwind and needs a manual copy across.
DEFAULT_OUTPUT = (
    SA_FIRES / "proj_bureaucrats_farms" / "data_output" / "intermediate"
    / "small_grid_rice_2010.parquet"
)

METRIC_CRS = "EPSG:7755"
MEASURE = "rice_prod_2010"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--grid", type=Path, default=DEFAULT_GRID)
    parser.add_argument("--spam-zip", type=Path, default=DEFAULT_SPAM_ZIP)
    parser.add_argument(
        "--raster",
        type=Path,
        default=None,
        help="Pre-extracted rice GeoTIFF; unzipped from --spam-zip when absent.",
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def resolve_raster(args: argparse.Namespace) -> Path:
    if args.raster is not None:
        if not args.raster.is_file():
            raise FileNotFoundError(args.raster)
        return args.raster
    if not args.spam_zip.is_file():
        raise FileNotFoundError(args.spam_zip)
    target_dir = args.spam_zip.parent / "geotiff_rice"
    raster = target_dir / RICE_BAND
    if not raster.is_file():
        logging.info("Extracting %s from %s", RICE_BAND, args.spam_zip.name)
        with zipfile.ZipFile(args.spam_zip) as archive:
            archive.extract(RICE_BAND, target_dir)
    return raster


def read_grids(grid_path: Path) -> gpd.GeoDataFrame:
    grids = gpd.read_file(grid_path, engine="pyogrio", use_arrow=True)

    # Shapefiles truncate long column names
    if "unique_small_grid_id" not in grids.columns:
        if "unq_s__" in grids.columns:
            grids = grids.rename(columns={"unq_s__": "unique_small_grid_id"})
        else:
            raise KeyError("Could not find unique_small_grid_id or unq_s__.")

    grids["unique_small_grid_id"] = pd.to_numeric(
        grids["unique_small_grid_id"], errors="raise"
    ).astype("int64")

    if grids["unique_small_grid_id"].duplicated().any():
        examples = (
            grids.loc[
                grids["unique_small_grid_id"].duplicated(False),
                "unique_small_grid_id",
            ]
            .drop_duplicates()
            .head(10)
            .tolist()
        )
        raise ValueError(
            f"The grid shapefile has duplicated grid IDs. Examples: {examples}"
        )
    if grids.crs is None:
        raise ValueError("The grid shapefile has no CRS.")

    return grids[["unique_small_grid_id", "geometry"]].copy()


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    output = args.output.resolve()
    if output.exists() and not args.overwrite:
        raise FileExistsError(f"{output} exists; use --overwrite.")
    output.parent.mkdir(parents=True, exist_ok=True)

    raster_path = resolve_raster(args)
    grids = read_grids(args.grid)
    logging.info("Grids: %s", f"{len(grids):,}")

    with rasterio.open(raster_path) as src:
        raster_crs = src.crs
        logging.info(
            "Raster CRS=%s shape=%s res=%s nodata=%s",
            raster_crs,
            src.shape,
            src.res,
            src.nodata,
        )
    if raster_crs is None:
        raise ValueError("The rice raster has no CRS.")

    # MapSPAM stores per-pixel totals, so coverage-weighted sum, NOT the
    # area_spherical_km2 form the density-valued population raster requires.
    grid_rice = exact_extract(
        str(raster_path),
        grids.to_crs(raster_crs),
        f"{MEASURE}=sum",
        include_cols="unique_small_grid_id",
        output="pandas",
    )
    grid_rice["unique_small_grid_id"] = pd.to_numeric(
        grid_rice["unique_small_grid_id"], errors="raise"
    ).astype("int64")
    grid_rice[MEASURE] = (
        pd.to_numeric(grid_rice[MEASURE], errors="coerce")
        .fillna(0.0)
        .clip(lower=0.0)
        .astype("float64")
    )

    grids_metric = grids.to_crs(METRIC_CRS)
    centroids = grids_metric.geometry.centroid
    grid_coordinates = pd.DataFrame(
        {
            "unique_small_grid_id": grids_metric[
                "unique_small_grid_id"
            ].to_numpy(),
            "centroid_x": centroids.x.to_numpy(dtype="float64"),
            "centroid_y": centroids.y.to_numpy(dtype="float64"),
            "grid_area_km2": grids_metric.geometry.area.to_numpy(
                dtype="float64"
            )
            / 1_000_000,
        }
    )

    grid_rice = (
        grid_rice.merge(
            grid_coordinates,
            on="unique_small_grid_id",
            how="left",
            validate="one_to_one",
        )
        .sort_values("unique_small_grid_id")
        .reset_index(drop=True)
    )

    if grid_rice[["centroid_x", "centroid_y"]].isna().any().any():
        raise ValueError("Some grids have no centroid after the merge.")
    if len(grid_rice) != len(grids):
        raise ValueError(
            f"Extraction returned {len(grid_rice):,} rows for "
            f"{len(grids):,} grids."
        )

    grid_rice.to_parquet(output, index=False)

    nonzero = int((grid_rice[MEASURE] > 0).sum())
    logging.info("Wrote %s", output)
    logging.info("Rows: %s", f"{len(grid_rice):,}")
    logging.info(
        "Grids with rice: %s (%.1f%%)",
        f"{nonzero:,}",
        100.0 * nonzero / len(grid_rice),
    )
    logging.info("Total rice production (mt): %s", f"{grid_rice[MEASURE].sum():,.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

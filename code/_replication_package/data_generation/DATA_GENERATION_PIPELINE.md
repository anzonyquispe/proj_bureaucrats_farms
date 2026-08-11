# Master data-generation dependency inventory

This document inventories the inputs used to construct
`0_master_dataset.parquet` and classifies them as either source data or
generated intermediate data. Its purpose is to make
`code/_replication_package/data_generation` the single location for all code
that creates project intermediates.

## Classification rule

- **Raw/curated source**: externally obtained data stored under `data/input`,
  or another explicitly frozen source that this project does not regenerate.
- **Intermediate**: any file created by this project or by the upstream
  `proj_downwind` workflow. Every intermediate must either have its producer
  in this folder or be explicitly declared a frozen upstream source.
- DuckDB work databases, temporary Parquets, logs, and shapefile sidecars are
  implementation artifacts rather than separate pipeline inputs.

## Pipeline

```text
raw/curated sources
    -> foundational geographic and panel intermediates
    -> population, area, placebo, protest, election, fire, and rice inputs
    -> build_0_master_dataset.py
    -> 0_master_dataset.parquet / 0_master_dataset.csv
    -> build_all_stacked_datasets_duckdb.py -> five standard stacked datasets
    -> build_politicians_characteristics_byprov.py
       -> politicians_characteristics_byprov.csv / cohort manifest
```

## Wind-direction convention

All directional construction code uses one Cartesian convention throughout:

- `0` degrees is East.
- `90` degrees is North.
- `180` degrees is West.
- `270` degrees is South.
- Angles increase counterclockwise and are normalized to `[0, 360)` only when
  needed by the directional lookup.

ERA5 components therefore enter as `atan2(v10, u10)`. Grid-to-grid bearings
use `atan2(delta_y, delta_x)`, and AC area vectors use
`(cos(theta), sin(theta))`. No downstream step interprets these values as
clockwise-from-North compass bearings. Monthly and rolling directions are
calculated from mean eastward/northward components, not arithmetic means of
degree values.

The tests in `tests/test_downup_direction_convention.py` enforce the four
cardinal cases for population and area, while `tests/test_fire_wind_duckdb.py`
checks a 179/-179 degree wraparound.

## Direct inputs to the master builder

| Intermediate | Producer in this folder | Producer status |
| --- | --- | --- |
| `data_2012_2024_grid_ac_downup_pop.parquet` | `build_downup_ac_pop_cluster.py` | Present |
| `data_2012_2024_grid_ac_downup.parquet` | `build_downup_ac_area_cluster.py` | Present; canonical seven-column area panel |
| `data_2012_2024_grid_ac_13kmpl.parquet` | `build_downup_13kmpl_cluster.py` | Present |
| `8_grids_ac_pr_5km.csv` | `8_grids_ac_pr_5km.ipynb` | Present; local-path notebook |
| `panel_data_election_year.parquet` | `panel_data_election_year.ipynb` | Present; local-path notebook |
| `_3_fire_grid.csv` | `build_fire_grid_duckdb.py` | Present; DuckDB Spatial |
| `9_rice_info_ac_lvl.parquet` | `9_rice_info_ac_lvl.ipynb` | Present; local-path notebook |

`build_0_master_dataset.py` left-joins all seven files above to the retained
wind-complete population base. The population Parquet is the sole source of
population, wind, and base-panel columns. The AC-area Parquet contains only
the four merge keys and `downup_ac_area`, `downwind_area`, and `upwind_area`.
`normalize_downup_ac_area_panel.py` migrates a legacy wide area Parquet to
this schema without recalculating geometry.

## Derived stacked datasets

All stacked-data producers and their cluster launchers are contained in this
folder. `build_all_stacked_datasets_duckdb.py` creates the five standard
treatment stacks. `build_politicians_characteristics_byprov.py` creates the
alternative politician-characteristics stack within province-election
cohorts from the same `0_master_dataset.parquet`.

The province-election stack is part of both shared rebuild entry points:

```bash
qsub build_stacked_datasets.sbatch
qsub build_master_and_stacked_datasets.sh
```

The first command rebuilds all stacks from an existing master. The second
rebuilds the master first and then all standard and province-election stacks.
The dedicated `build_politicians_characteristics_byprov.sbatch` remains
available when only the alternative stack needs to be rebuilt.

## Inputs to each direct-input producer

| Producer | Input | Classification | Producer coverage |
| --- | --- | --- | --- |
| `build_downup_ac_pop_cluster.py` | `data_2012_2024_grid_ac.parquet` | Intermediate | `build_grid_ac_panel_2012_2024.py` present |
| `build_downup_ac_pop_cluster.py` | `_2_wind_direction_grid.parquet` | Intermediate | `build_wind_direction_grid_duckdb.py` present |
| `build_downup_ac_pop_cluster.py` | `small_grid_population_2010.parquet` | Intermediate | `grid_population.ipynb` present; output path needs correction |
| `build_downup_ac_area_cluster.py` | `data_2012_2024_grid_ac_downup_pop.parquet` | Intermediate | `build_downup_ac_pop_cluster.py` present |
| `build_downup_ac_area_cluster.py` | `small_grid_population_2010.parquet` | Intermediate | `grid_population.ipynb` present; output path needs correction |
| `build_downup_ac_area_cluster.py` | `_0_2_3_ACs_right_shapefile.shp` | Raw/curated source | No producer required |
| `build_downup_13kmpl_cluster.py` | `data_2012_2024_grid_ac_downup_pop.parquet` | Intermediate | `build_downup_ac_pop_cluster.py` present |
| `build_downup_13kmpl_cluster.py` | `small_grid_population_2010.parquet` | Intermediate | `grid_population.ipynb` present; output path needs correction |
| `8_grids_ac_pr_5km.ipynb` | ACLED protest CSV | Raw/curated source | No producer required |
| `8_grids_ac_pr_5km.ipynb` | `1-grid-generation.shp` | Raw/curated source | No producer required |
| `8_grids_ac_pr_5km.ipynb` | `_0_2_3_ACs_right_shapefile.shp` | Raw/curated source | No producer required |
| `panel_data_election_year.ipynb` | `_ac_covs_myneta.csv` | Raw/curated source | No producer required |
| `panel_data_election_year.ipynb` | `ac_india_elec_yr_clean.csv` | Raw/curated source | No producer required |
| `9_rice_info_ac_lvl.ipynb` | three MapSPAM 2010 DBF files | Raw/curated source | No producer required |
| `9_rice_info_ac_lvl.ipynb` | `_0_2_3_ACs_right_shapefile.shp` | Raw/curated source | No producer required |
| `build_fire_grid_duckdb.py` | `1-fires20002024.csv` | Raw/curated source | No producer required |
| `build_fire_grid_duckdb.py` | `1-grid-generation.shp` | Raw/curated source | No producer required |
| `build_wind_direction_grid_duckdb.py` | `era5-land-19902021-wind.nc` | Raw/curated source | No producer required |
| `build_wind_direction_grid_duckdb.py` | `era5-land-2022-wind.nc` | Raw/curated source | No producer required |
| `build_wind_direction_grid_duckdb.py` | `era5-land-2023-2024.csv` | Raw/curated source | No producer required |
| `build_wind_direction_grid_duckdb.py` | `1-grid-generation.shp` | Raw/curated source | No producer required |

## Foundational intermediate producers

### `data_2012_2024_grid_ac.parquet`

Produced by `build_grid_ac_panel_2012_2024.py` from:

| Input | Classification | Producer coverage |
| --- | --- | --- |
| `proj_downwind/replication/data_output/data_2012_2022_downup.dta` | Upstream intermediate | **Missing here or must be declared frozen** |
| `1-grid-generation.shp` | Raw/curated source | No producer required |
| `_0_2_3_ACs_right_shapefile.shp` | Raw/curated source | No producer required |

### `small_grid_population_2010.parquet`

Produced by `grid_population.ipynb` from:

| Input | Classification | Producer coverage |
| --- | --- | --- |
| GPW v4 2010 population-density GeoTIFF | Raw/curated source | No producer required |
| `1-grid-generation.shp` | Raw/curated source | No producer required |

The notebook currently writes the Parquet to the `proj_downwind` intermediate
directory, while the Python consumers expect it under the
`proj_bureaucrats_farms` intermediate directory. The producer exists, but the
path must be aligned before the pipeline is self-contained.

## Raw/curated source inventory

These inputs do not require producer code in this folder, but their versions
and acquisition instructions should be preserved:

| Source | Used by |
| --- | --- |
| `1-grid-generation.shp` | grid/AC panel, population, protest, fire, and wind producers |
| `_0_2_3_ACs_right_shapefile.shp` | grid/AC panel, AC area, protest, and rice producers |
| `_ac_covs_myneta.csv` | `panel_data_election_year.ipynb` |
| ACLED India protest CSV, dated `2000-01-01-2025-05-13` | `8_grids_ac_pr_5km.ipynb` |
| `ac_india_elec_yr_clean.csv` | `panel_data_election_year.ipynb` |
| `1-fires20002024.csv` | `build_fire_grid_duckdb.py` |
| ERA5-Land 1990-2021 u10/v10 NetCDF | `build_wind_direction_grid_duckdb.py` |
| ERA5-Land 2022 u10/v10 NetCDF | `build_wind_direction_grid_duckdb.py` |
| ERA5-Land 2023-2024 u10/v10 CSV | `build_wind_direction_grid_duckdb.py` |
| MapSPAM 2010 physical-area DBF | `9_rice_info_ac_lvl.ipynb` |
| MapSPAM 2010 production DBF | `9_rice_info_ac_lvl.ipynb` |
| MapSPAM 2010 harvested-area DBF | `9_rice_info_ac_lvl.ipynb` |
| GPW v4 revision 11, 2010, 30 arc-second population-density GeoTIFF | `grid_population.ipynb` |

The four project-specific files explicitly classified as raw are
`1-grid-generation.shp`, `_0_2_3_ACs_right_shapefile.shp`,
`_ac_covs_myneta.csv`, and `ac_india_elec_yr_clean.csv`.

## Fire and wind producer commands

The replacements for the two R producers use DuckDB for aggregation and
DuckDB Spatial for grid assignment:

```bash
python build_fire_grid_duckdb.py --overwrite
python build_wind_direction_grid_duckdb.py --overwrite
```

Cluster launchers:

```bash
qsub build_fire_grid_duckdb.sbatch
qsub build_wind_direction_grid_duckdb.sbatch
```

To regenerate the corrected wind panel, AC population and area measures,
13 km placebo, master dataset, and both standard downup stacks in one cluster
job, use:

```bash
qsub rebuild_corrected_downup_pipeline.sbatch
```

The default stacked outputs are `combined_dt.csv`/`combined_dt.db` and
`combined_dt_pop.csv`/`combined_dt_pop.db`. Set `STACK_SPECS=all` at submission
time to rebuild every registered stack.

The wind producer combines the calculations formerly split between
`1-clean-wind.R` and `_2_wind_direction_grid.R`. It reads the original two
NetCDF files in bounded chunks, reads the 2023-2024 CSV with DuckDB, applies
the original R formulas and calendar-month rolling windows, and performs the
grid intersection with DuckDB Spatial. Directions are averaged as vector
components, so wraparound at -180/180 degrees is handled correctly. Its only retained products are
`_2_wind_direction_grid.parquet` and `_2_wind_direction_grid.duckdb`; no
cleaned hourly table, RDS/RData object, or `pyreadr` dependency is used.

## Missing producer code

After adding the raw-to-grid wind producer and applying the supplied raw-data
classifications, one upstream intermediate remains uncovered:

1. `data_2012_2022_downup.dta`, unless it is deliberately treated as a frozen
   upstream input from `proj_downwind`

## Existing producer code needing portability work

The following producer notebooks are present but use hard-coded local Windows
paths and do not currently have cluster launchers:

- `8_grids_ac_pr_5km.ipynb`
- `panel_data_election_year.ipynb`
- `9_rice_info_ac_lvl.ipynb`
- `grid_population.ipynb`

For a complete replication package, these should eventually be converted to
parameterized Python entry points or given reproducible notebook launchers.

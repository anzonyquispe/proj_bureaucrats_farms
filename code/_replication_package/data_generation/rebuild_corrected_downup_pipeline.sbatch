#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N corrected_downup_pipeline
#$ -pe smp 20
#$ -cwd

set -euo pipefail

ROOT="${PROJECT_ROOT:-/users/aquisper/proj_bureaucrats_farms}"
SA_ROOT="${SA_FIRES_ROOT:-/groups/sgulzar/sa_fires}"
CODE_DIR="${ROOT}/code/_replication_package/data_generation"
INTERMEDIATE="${PIPELINE_INTERMEDIATE:-${SA_ROOT}/proj_bureaucrats_farms/data_output/intermediate}"
CONDA_ENV="${DOWNUP_ENV_PREFIX:-/groups/sgulzar/india_forest_land/downup_geo}"
CONDA_SH="/afs/crc.nd.edu/x86_64_linux/c/conda/24.7.1/etc/profile.d/conda.sh"
BRANCH="${PIPELINE_BRANCH:-replication_data}"
MEMORY_LIMIT="${PIPELINE_MEMORY_LIMIT:-120GB}"
THREADS="${NSLOTS:-20}"

if [[ ! -f "${CONDA_SH}" ]]; then
    echo "ERROR: conda initialization script was not found at ${CONDA_SH}." >&2
    exit 1
fi
if [[ ! -d "${ROOT}/.git" ]]; then
    echo "ERROR: project Git checkout was not found at ${ROOT}." >&2
    exit 1
fi

source "${CONDA_SH}"
conda activate "${CONDA_ENV}"
PYTHON="$(command -v python)"
export PYTHONUNBUFFERED=1

cd "${ROOT}"
echo "[$(date '+%F %T')] host=$(hostname) job=${JOB_ID:-NA} pwd=$(pwd)"
echo "[$(date '+%F %T')] branch=${BRANCH} environment=${CONDA_ENV}"
echo "[$(date '+%F %T')] threads=${THREADS} memory=${MEMORY_LIMIT}"
echo "[$(date '+%F %T')] intermediate=${INTERMEDIATE}"

exec 9>"${ROOT}.git-update.lock"
flock 9
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "ERROR: ${ROOT} contains uncommitted tracked changes." >&2
    git status --short --untracked-files=no >&2
    exit 1
fi
git fetch origin "${BRANCH}"
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    git switch "${BRANCH}"
else
    git switch --track -c "${BRANCH}" "origin/${BRANCH}"
fi
git pull --ff-only origin "${BRANCH}"
echo "[$(date '+%F %T')] git HEAD: $(git rev-parse --short HEAD)"
flock -u 9

cd "${CODE_DIR}"
"${PYTHON}" -c "from pathlib import Path; import duckdb, geopandas, netCDF4, numpy, pandas, pyarrow, pyproj, shapely; data=Path(pyproj.datadir.get_data_dir()); assert (data / 'proj.db').is_file(); pyproj.CRS.from_epsg(4326); assert int(shapely.__version__.split('.')[0]) >= 2; print('dependency check passed')"
"${PYTHON}" tests/test_downup_direction_convention.py -v

if [[ "${REBUILD_WIND:-1}" == "1" ]]; then
    echo "[$(date '+%F %T')] stage 1/6: East-referenced vector wind panel"
    "${PYTHON}" build_wind_direction_grid_duckdb.py \
        --historical-netcdf "${HISTORICAL_WIND_NETCDF:-${SA_ROOT}/data/input/wind/ecmwf/era5-land-19902021-wind.nc}" \
        --year-2022-netcdf "${WIND_2022_NETCDF:-${SA_ROOT}/data/input/wind/ecmwf/era5-land-2022-wind.nc}" \
        --years-2023-2024-csv "${WIND_2023_2024_CSV:-${SA_ROOT}/data/input/wind/ecmwf/era5-land-2023-2024.csv}" \
        --grid-shapefile "${GRID_SHAPEFILE:-${INTERMEDIATE}/1-grid-generation.shp}" \
        --output "${INTERMEDIATE}/_2_wind_direction_grid.parquet" \
        --threads "${THREADS}" \
        --memory-limit "${MEMORY_LIMIT}" \
        --overwrite \
        > build_wind_direction_grid_duckdb.out 2>&1
else
    echo "[$(date '+%F %T')] stage 1/6 skipped because REBUILD_WIND=0"
fi

echo "[$(date '+%F %T')] stage 2/6: corrected AC population measures"
"${PYTHON}" build_downup_ac_pop_cluster.py \
    --panel "${INTERMEDIATE}/data_2012_2024_grid_ac.parquet" \
    --wind-input "${INTERMEDIATE}/_2_wind_direction_grid.parquet" \
    --grid-population "${INTERMEDIATE}/small_grid_population_2010.parquet" \
    --output "${INTERMEDIATE}/data_2012_2024_grid_ac_downup_pop.parquet" \
    --threads "${THREADS}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --overwrite \
    > build_downup_ac_pop_cluster.out 2>&1

echo "[$(date '+%F %T')] stage 3/6: corrected exact AC area measures"
"${PYTHON}" build_downup_ac_area_cluster.py \
    --population-input "${INTERMEDIATE}/data_2012_2024_grid_ac_downup_pop.parquet" \
    --grid-population "${INTERMEDIATE}/small_grid_population_2010.parquet" \
    --ac-shapefile "${INTERMEDIATE}/_0_2_3_ACs_right_shapefile.shp" \
    --output "${INTERMEDIATE}/data_2012_2024_grid_ac_downup.parquet" \
    --workers "${THREADS}" \
    --threads "${THREADS}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --area-chunk-rows "${AREA_CHUNK_ROWS:-5000}" \
    --overwrite \
    > build_downup_ac_area_cluster.out 2>&1

echo "[$(date '+%F %T')] stage 4/6: corrected 13 km directional placebo"
"${PYTHON}" build_downup_13kmpl_cluster.py \
    --panel "${INTERMEDIATE}/data_2012_2024_grid_ac_downup_pop.parquet" \
    --grid-population "${INTERMEDIATE}/small_grid_population_2010.parquet" \
    --output "${INTERMEDIATE}/data_2012_2024_grid_ac_13kmpl.parquet" \
    --threads "${THREADS}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --overwrite \
    > build_downup_13kmpl_cluster.out 2>&1

echo "[$(date '+%F %T')] stage 5/6: rebuild master dataset"
"${PYTHON}" build_0_master_dataset.py \
    --intermediate "${INTERMEDIATE}" \
    --threads "${THREADS}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --overwrite \
    > build_0_master_dataset.out 2>&1

SPEC_ARGS=()
IFS=',' read -r -a REQUESTED_SPECS \
    <<< "${STACK_SPECS:-downup_ac,downup_ac_pop}"
for spec in "${REQUESTED_SPECS[@]}"; do
    if [[ "${spec}" == "all" ]]; then
        SPEC_ARGS=()
        break
    fi
    SPEC_ARGS+=(--spec "${spec}")
done

echo "[$(date '+%F %T')] stage 6/6: rebuild stacked datasets"
"${PYTHON}" build_all_stacked_datasets_duckdb.py \
    --intermediate "${INTERMEDIATE}" \
    --threads "${THREADS}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --overwrite \
    "${SPEC_ARGS[@]}" \
    > build_stacked_datasets.out 2>&1

echo "[$(date '+%F %T')] corrected downup pipeline completed"

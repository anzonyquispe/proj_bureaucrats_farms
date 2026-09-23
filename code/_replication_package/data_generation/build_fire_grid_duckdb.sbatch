#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N build_fire_grid
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

if [[ ! -f "${CONDA_SH}" ]]; then
    echo "ERROR: conda initialization script was not found at ${CONDA_SH}." >&2
    exit 1
fi
source "${CONDA_SH}"
conda activate "${CONDA_ENV}"
PYTHON="$(command -v python)"

cd "${ROOT}"
echo "[$(date '+%F %T')] host=$(hostname) job=${JOB_ID:-NA} pwd=$(pwd)"
echo "[$(date '+%F %T')] conda environment=${CONDA_ENV}"
echo "[$(date '+%F %T')] python=${PYTHON}"

exec 9>"${ROOT}.git-update.lock"
flock 9
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "ERROR: tracked files contain uncommitted changes." >&2
    git status --short --untracked-files=no >&2
    exit 1
fi
git fetch origin "${BRANCH}"
git switch "${BRANCH}"
git pull --ff-only origin "${BRANCH}"
echo "[$(date '+%F %T')] git HEAD: $(git rev-parse --short HEAD)"
flock -u 9

cd "${CODE_DIR}"
"${PYTHON}" -c "import duckdb; print('duckdb:', duckdb.__version__)"

"${PYTHON}" build_fire_grid_duckdb.py \
    --fires "${FIRE_INPUT:-${SA_ROOT}/data/input/fires/1-fires20002024.csv}" \
    --grid-shapefile "${GRID_SHAPEFILE:-${INTERMEDIATE}/1-grid-generation.shp}" \
    --output "${INTERMEDIATE}/_3_fire_grid.csv" \
    --threads "${NSLOTS:-20}" \
    --memory-limit "${PIPELINE_MEMORY_LIMIT:-120GB}" \
    --overwrite \
    > build_fire_grid_duckdb.out 2>&1

echo "[$(date '+%F %T')] fire-grid intermediate completed"


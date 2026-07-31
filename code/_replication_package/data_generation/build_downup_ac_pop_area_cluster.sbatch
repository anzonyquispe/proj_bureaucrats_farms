#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N build_downup_ac_pop_area
#$ -pe smp 10
#$ -cwd

set -euo pipefail

ROOT="/users/aquisper/proj_bureaucrats_farms"
CODE_DIR="${ROOT}/code/_replication_package/data_generation"
CONDA_ENV="${DOWNUP_ENV_PREFIX:-/groups/sgulzar/india_forest_land/downup_geo}"
CONDA_SH="/afs/crc.nd.edu/x86_64_linux/c/conda/24.7.1/etc/profile.d/conda.sh"
BRANCH="replication_data"

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
if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git is unavailable on this compute node." >&2
    exit 1
fi
if [[ ! -x "${PYTHON}" ]]; then
    echo "ERROR: Python was not found at ${PYTHON}." >&2
    exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "ERROR: ${ROOT} contains uncommitted changes to tracked files." >&2
    git status --short --untracked-files=no >&2
    exit 1
fi

echo "[$(date '+%F %T')] updating origin/${BRANCH}"
git fetch origin "${BRANCH}"
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    git switch "${BRANCH}"
else
    git switch --track -c "${BRANCH}" "origin/${BRANCH}"
fi
git pull --ff-only origin "${BRANCH}"
echo "[$(date '+%F %T')] git HEAD: $(git rev-parse --short HEAD)"

cd "${CODE_DIR}"

echo "[$(date '+%F %T')] checking Python dependencies"
"${PYTHON}" -c "from pathlib import Path; import duckdb, geopandas, numpy, pandas, pyarrow, pyproj, shapely; data=pyproj.datadir.get_data_dir(); print('pyproj:', pyproj.__version__, 'PROJ:', pyproj.proj_version_str, flush=True); print('PROJ data:', data, flush=True); assert (Path(data) / 'proj.db').is_file(); pyproj.datadir.set_data_dir(data); pyproj.CRS.from_epsg(4326); assert int(shapely.__version__.split('.')[0]) >= 2"

echo "[$(date '+%F %T')] stage 1/2: downwind/upwind population"
"${PYTHON}" build_downup_ac_pop_cluster.py \
    --threads "${NSLOTS:-60}" \
    --memory-limit "90GB" \
    --overwrite \
    > build_downup_ac_pop_cluster.out 2>&1

echo "[$(date '+%F %T')] stage 2/2: exact parallel AC areas"
"${PYTHON}" build_downup_ac_area_cluster.py \
    --workers "${NSLOTS:-60}" \
    --threads "${NSLOTS:-60}" \
    --memory-limit "90GB" \
    --area-chunk-rows 5000 \
    --overwrite \
    > build_downup_ac_area_cluster.out 2>&1

echo "[$(date '+%F %T')] completed both stages"

#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N build_downup_13kmpl
#$ -pe smp 10
#$ -cwd

set -euo pipefail

ROOT="/users/aquisper/proj_bureaucrats_farms"
CODE_DIR="${ROOT}/code/_replication_package/data_generation"
CONDA_ENV="${DOWNUP_ENV_PREFIX:-/groups/sgulzar/india_forest_land/downup_geo}"
CONDA_SH="/afs/crc.nd.edu/x86_64_linux/c/conda/24.7.1/etc/profile.d/conda.sh"
BRANCH="replication_data"

if [[ ! -f "${CONDA_SH}" ]]; then
    echo "ERROR: conda initialization was not found at ${CONDA_SH}." >&2
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

"${PYTHON}" build_downup_13kmpl_cluster.py \
    --threads "${NSLOTS:-10}" \
    --memory-limit "90GB" \
    --radius-metres 13000 \
    --overwrite \
    > build_downup_13kmpl_cluster.out 2>&1

echo "[$(date '+%F %T')] 13 km placebo intermediate completed"

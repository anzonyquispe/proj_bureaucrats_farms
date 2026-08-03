#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N build_all_stacks
#$ -pe smp 10
#$ -cwd

set -euo pipefail

ROOT="/users/aquisper/proj_bureaucrats_farms"
CODE_DIR="${ROOT}/code/_replication_package/data_generation"
CONDA_ENV="${DOWNUP_ENV_PREFIX:-/groups/sgulzar/india_forest_land/downup_geo}"
CONDA_SH="/afs/crc.nd.edu/x86_64_linux/c/conda/24.7.1/etc/profile.d/conda.sh"
BRANCH="replication_data"

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

SPEC_ARGS=()
if [[ -n "${STACK_SPECS:-}" && "${STACK_SPECS}" != "all" ]]; then
    IFS=',' read -r -a REQUESTED_SPECS <<< "${STACK_SPECS}"
    for spec in "${REQUESTED_SPECS[@]}"; do
        SPEC_ARGS+=(--spec "${spec}")
    done
fi

OVERWRITE_ARGS=()
if [[ "${STACK_OVERWRITE:-0}" == "1" ]]; then
    OVERWRITE_ARGS+=(--overwrite)
fi

"${PYTHON}" build_stacked_downup_13kmpl_duckdb.py \
    --threads "${NSLOTS:-10}" \
    --memory-limit "${STACK_MEMORY_LIMIT:-90GB}" \
    "${SPEC_ARGS[@]}" \
    "${OVERWRITE_ARGS[@]}" \
    > build_stacked_datasets.out 2>&1

echo "[$(date '+%F %T')] completed configured stacked datasets"

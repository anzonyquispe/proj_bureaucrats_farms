#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N master_and_stacks
#$ -pe smp 10
#$ -cwd

set -euo pipefail

ROOT="${PROJECT_ROOT:-/users/aquisper/proj_bureaucrats_farms}"
CODE_DIR="${ROOT}/code/_replication_package/data_generation"
INTERMEDIATE="${PIPELINE_INTERMEDIATE:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate}"
CONDA_ENV="${DOWNUP_ENV_PREFIX:-/groups/sgulzar/india_forest_land/downup_geo}"
CONDA_SH="/afs/crc.nd.edu/x86_64_linux/c/conda/24.7.1/etc/profile.d/conda.sh"
BRANCH="${PIPELINE_BRANCH:-replication_data}"
MEMORY_LIMIT="${PIPELINE_MEMORY_LIMIT:-90GB}"

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

cd "${ROOT}"
echo "[$(date '+%F %T')] host=$(hostname) job=${JOB_ID:-NA} pwd=$(pwd)"
echo "[$(date '+%F %T')] conda environment=${CONDA_ENV}"
echo "[$(date '+%F %T')] python=${PYTHON}"
echo "[$(date '+%F %T')] intermediate=${INTERMEDIATE}"

exec 9>"${ROOT}.git-update.lock"
flock 9
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "ERROR: ${ROOT} contains uncommitted changes to tracked files." >&2
    git status --short --untracked-files=no >&2
    exit 1
fi
git fetch origin "${BRANCH}"
git switch "${BRANCH}"
git pull --ff-only origin "${BRANCH}"
echo "[$(date '+%F %T')] git HEAD: $(git rev-parse --short HEAD)"
flock -u 9

cd "${CODE_DIR}"

echo "[$(date '+%F %T')] building 0_master_dataset.parquet and CSV"
"${PYTHON}" build_0_master_dataset.py \
    --intermediate "${INTERMEDIATE}" \
    --threads "${NSLOTS:-10}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --overwrite \
    > build_0_master_dataset.out 2>&1
echo "[$(date '+%F %T')] master dataset completed"

SPEC_ARGS=()
if [[ -n "${STACK_SPECS:-}" && "${STACK_SPECS}" != "all" ]]; then
    IFS=',' read -r -a REQUESTED_SPECS <<< "${STACK_SPECS}"
    for spec in "${REQUESTED_SPECS[@]}"; do
        SPEC_ARGS+=(--spec "${spec}")
    done
fi

echo "[$(date '+%F %T')] building stacked datasets"
"${PYTHON}" build_all_stacked_datasets_duckdb.py \
    --intermediate "${INTERMEDIATE}" \
    --threads "${NSLOTS:-10}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --overwrite \
    "${SPEC_ARGS[@]}" \
    > build_stacked_datasets.out 2>&1

echo "[$(date '+%F %T')] completed master and configured stacked datasets"

#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N master_and_stacks
#$ -pe smp 10
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

set -euo pipefail

ROOT="${PROJECT_ROOT:-/users/aquisper/proj_bureaucrats_farms}"
CODE_DIR="${ROOT}/code/_replication_package/data_generation"
INTERMEDIATE="${PIPELINE_INTERMEDIATE:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate}"
CONDA_ENV="${DOWNUP_ENV_PREFIX:-/groups/sgulzar/india_forest_land/downup_geo}"
CONDA_SH="/afs/crc.nd.edu/x86_64_linux/c/conda/24.7.1/etc/profile.d/conda.sh"
BRANCH="${PIPELINE_BRANCH:-replication_data}"
MEMORY_LIMIT="${PIPELINE_MEMORY_LIMIT:-90GB}"
NEIGH_INPUT="${NEIGH_INPUT:-${INTERMEDIATE}/0_ac_neighs_downup.csv}"
NEIGH_OUTPUT="${NEIGH_OUTPUT:-${INTERMEDIATE}/stacked_downup_neigh.csv}"
NEIGH_DATABASE="${NEIGH_DATABASE:-${INTERMEDIATE}/stacked_downup_neigh.db}"
NEIGH_TEMP_DIRECTORY="${NEIGH_TEMP_DIRECTORY:-${INTERMEDIATE}/stacked_downup_neigh_duckdb_tmp}"
LOG_DIR="${PIPELINE_LOG_DIR:-${CODE_DIR}/logs/data_generation}"

mkdir -p "${LOG_DIR}"
PIPELINE_LOG="${LOG_DIR}/00_master_and_stacked_pipeline.log"
exec > >(tee "${PIPELINE_LOG}") 2>&1

run_stage() {
    local label="$1"
    local log_file="$2"
    shift 2

    echo "[$(date '+%F %T')] START: ${label}"
    echo "[$(date '+%F %T')] LOG:   ${log_file}"
    if "$@" > "${log_file}" 2>&1; then
        echo "[$(date '+%F %T')] DONE:  ${label}"
    else
        local status=$?
        echo "[$(date '+%F %T')] ERROR: ${label} failed with exit code ${status}" >&2
        echo "[$(date '+%F %T')] Last 80 lines from ${log_file}:" >&2
        tail -n 80 "${log_file}" >&2 || true
        exit "${status}"
    fi
}

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

run_stage "master dataset" "${LOG_DIR}/01_master_dataset.log" \
    "${PYTHON}" build_0_master_dataset.py \
    --intermediate "${INTERMEDIATE}" \
    --threads "${NSLOTS:-10}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --overwrite

SPEC_ARGS=()
if [[ -n "${STACK_SPECS:-}" && "${STACK_SPECS}" != "all" ]]; then
    IFS=',' read -r -a REQUESTED_SPECS <<< "${STACK_SPECS}"
    for spec in "${REQUESTED_SPECS[@]}"; do
        SPEC_ARGS+=(--spec "${spec}")
    done
fi

run_stage "five standard stacked datasets" "${LOG_DIR}/02_standard_stacks.log" \
    "${PYTHON}" build_all_stacked_datasets_duckdb.py \
    --intermediate "${INTERMEDIATE}" \
    --threads "${NSLOTS:-10}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --overwrite \
    "${SPEC_ARGS[@]}"

run_stage "province-election politician stack" "${LOG_DIR}/03_politicians_byprov.log" \
    "${PYTHON}" build_politicians_characteristics_byprov.py \
    --intermediate "${INTERMEDIATE}" \
    --threads "${NSLOTS:-10}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --last-cohort-year 2022 \
    --last-cohort-month 12 \
    --expected-cohorts 8 \
    --overwrite

if [[ ! -f "${NEIGH_INPUT}" ]]; then
    echo "ERROR: neighbour-panel input was not found at ${NEIGH_INPUT}." >&2
    exit 1
fi
run_stage "neighbour-border stacked dataset" "${LOG_DIR}/04_neighbour_stack.log" \
    "${PYTHON}" build_stacked_duckdb_unique_pair.py \
    --input "${NEIGH_INPUT}" \
    --output "${NEIGH_OUTPUT}" \
    --database "${NEIGH_DATABASE}" \
    --temp-directory "${NEIGH_TEMP_DIRECTORY}" \
    --treatment-col downwind_neighbours \
    --pair-cols unique_small_grid_id ac_uq_id_neighbor \
    --unit-cols unique_pair \
    --cutoff-year 2022 \
    --cutoff-month 8 \
    --pre-periods 6 \
    --post-periods 6 \
    --post-definition include_event \
    --threads "${NSLOTS:-10}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --write-manifest \
    --overwrite

echo "[$(date '+%F %T')] completed master, standard stacks, province-election stack, and neighbour stack"
echo "[$(date '+%F %T')] pipeline summary log: ${PIPELINE_LOG}"

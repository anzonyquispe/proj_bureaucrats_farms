#!/bin/bash
#$ -m abe
#$ -q largemem
#$ -N build_downup_ac_pop_rice
#$ -pe smp 10
#$ -cwd

set -euo pipefail

ROOT="${PROJECT_ROOT:-/users/aquisper/proj_bureaucrats_farms}"
SA_ROOT="${SA_FIRES_ROOT:-/groups/sgulzar/sa_fires}"
CODE_DIR="${ROOT}/code/_replication_package/data_generation"
INTERMEDIATE="${PIPELINE_INTERMEDIATE:-${SA_ROOT}/proj_bureaucrats_farms/data_output/intermediate}"
CONDA_ENV="${DOWNUP_ENV_PREFIX:-/groups/sgulzar/india_forest_land/downup_geo}"
CONDA_SH="/afs/crc.nd.edu/x86_64_linux/c/conda/24.7.1/etc/profile.d/conda.sh"
BRANCH="${PIPELINE_BRANCH:-replication_data}"
MEMORY_LIMIT="${PIPELINE_MEMORY_LIMIT:-90GB}"
THREADS="${NSLOTS:-10}"
RICE_PERCENTILE="${RICE_PERCENTILE:-0.5}"

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
"${PYTHON}" tests/test_downup_pop_rice.py -v

echo "[$(date '+%F %T')] AC-month population downwind of rice zones"
"${PYTHON}" build_downup_ac_pop_rice.py \
    --panel "${INTERMEDIATE}/data_2012_2024_grid_ac_downup_pop.parquet" \
    --grid-population "${INTERMEDIATE}/small_grid_population_2010.parquet" \
    --grid-rice "${INTERMEDIATE}/small_grid_rice_2010.parquet" \
    --rice-percentile "${RICE_PERCENTILE}" \
    --rice-sample-percentile "${RICE_SAMPLE_PERCENTILE:-0.5}" \
    --output "${INTERMEDIATE}/data_2012_2024_ac_downup_pop_rice.parquet" \
    --output-dta "${INTERMEDIATE}/data_2012_2024_ac_downup_pop_rice.dta" \
    --threads "${THREADS}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --overwrite \
    > build_downup_ac_pop_rice.out 2>&1

echo "[$(date '+%F %T')] rice-source population stage completed"

#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N rebuild_distr_stacks
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
THREADS="${NSLOTS:-10}"
MEMORY_LIMIT="${PIPELINE_MEMORY_LIMIT:-120GB}"

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
"${PYTHON}" -c "import duckdb, numpy, pandas, pyarrow; print('dependency check passed')"

case "${REBUILD_POPULATION:-1}" in
    1)
        echo "[$(date '+%F %T')] stage 1/4: preserve distr_id in population panel"
        "${PYTHON}" build_downup_ac_pop_cluster.py \
            --panel "${INTERMEDIATE}/data_2012_2024_grid_ac.parquet" \
            --wind-input "${INTERMEDIATE}/_2_wind_direction_grid.parquet" \
            --grid-population "${INTERMEDIATE}/small_grid_population_2010.parquet" \
            --output "${INTERMEDIATE}/data_2012_2024_grid_ac_downup_pop.parquet" \
            --threads "${THREADS}" \
            --memory-limit "${MEMORY_LIMIT}" \
            --overwrite \
            > rebuild_distr_id_population.out 2>&1
        ;;
    0)
        echo "[$(date '+%F %T')] stage 1/4 skipped; validating existing population panel"
        "${PYTHON}" -c '
import sys
import duckdb
path = sys.argv[1]
columns = {
    row[0]
    for row in duckdb.connect().execute(
        "DESCRIBE SELECT * FROM read_parquet(?)", [path]
    ).fetchall()
}
if "distr_id" not in columns:
    raise SystemExit(f"ERROR: distr_id is absent from {path}")
print(f"Existing population panel contains distr_id: {path}")
' "${INTERMEDIATE}/data_2012_2024_grid_ac_downup_pop.parquet"
        ;;
    *)
        echo "ERROR: REBUILD_POPULATION must be 0 or 1." >&2
        exit 1
        ;;
esac

echo "[$(date '+%F %T')] stage 2/4: normalize AC-area panel schema"
"${PYTHON}" normalize_downup_ac_area_panel.py \
    --population "${INTERMEDIATE}/data_2012_2024_grid_ac_downup_pop.parquet" \
    --area "${INTERMEDIATE}/data_2012_2024_grid_ac_downup.parquet" \
    --threads "${THREADS}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --overwrite \
    > normalize_downup_ac_area_panel.out 2>&1

echo "[$(date '+%F %T')] stage 3/4: rebuild master only"
"${PYTHON}" build_0_master_dataset.py \
    --intermediate "${INTERMEDIATE}" \
    --threads "${THREADS}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --overwrite \
    > rebuild_distr_id_master.out 2>&1

echo "[$(date '+%F %T')] stage 4/4: rebuild downup area/pop stacks only"
"${PYTHON}" build_all_stacked_datasets_duckdb.py \
    --intermediate "${INTERMEDIATE}" \
    --spec downup_ac \
    --spec downup_ac_pop \
    --threads "${THREADS}" \
    --memory-limit "${MEMORY_LIMIT}" \
    --overwrite \
    > rebuild_distr_id_stacks.out 2>&1

echo "[$(date '+%F %T')] distr_id master/stack rebuild completed"

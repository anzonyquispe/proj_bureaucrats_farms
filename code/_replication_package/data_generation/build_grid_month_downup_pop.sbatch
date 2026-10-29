#!/usr/bin/env bash
#$ -N downup_pop_xwalk
#$ -q largemem
#$ -pe smp 2
#$ -cwd
#$ -j y
#$ -o /dev/null

set -euo pipefail

ROOT="${PROJECT_ROOT:-/users/aquisper/proj_bureaucrats_farms}"
CODE_DIR="${ROOT}/code/_replication_package/data_generation"
INTERMEDIATE="${PIPELINE_INTERMEDIATE:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate}"
CONDA_ENV="${DOWNUP_ENV_PREFIX:-/groups/sgulzar/india_forest_land/downup_geo}"
PYTHON="${CONDA_ENV}/bin/python"
LOG_DIR="${CODE_DIR}/logs/data_generation"
LOG_FILE="${LOG_DIR}/03b_downup_pop_crosswalk.log"

mkdir -p "${LOG_DIR}"
exec > >(tee "${LOG_FILE}") 2>&1

echo "[$(date '+%F %T')] generating grid-month district downup_pop crosswalk"
"${PYTHON}" "${CODE_DIR}/build_grid_month_downup_pop.py" \
  --source-csv "${INTERMEDIATE}/data_2012_2022_downup.csv" \
  --master-parquet "${INTERMEDIATE}/0_master_dataset.parquet" \
  --output "${INTERMEDIATE}/grid_month_downup_pop.dta" \
  --threads "${NSLOTS:-2}" \
  --memory-limit "${MEMORY_LIMIT:-20GB}" \
  --overwrite

echo "[$(date '+%F %T')] completed: ${INTERMEDIATE}/grid_month_downup_pop.dta"

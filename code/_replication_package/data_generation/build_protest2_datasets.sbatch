#!/bin/bash
#$ -N protest2_data
#$ -q long
#$ -pe smp 10
#$ -cwd
#$ -j y

# Build the protest2 analysis inputs without touching the production files:
#   1. 0_master_dataset_protest2.parquet from 8_grids_ac_pr2_5km.csv
#   2. check that it differs from 0_master_dataset.parquet only in protest columns
#   3. grid_month_ac_area_tr_protest2.dta (clusters recomputed from protest2 areas)
#   4. stacked_data_protest2_5km_election_sameterm.csv (the RA's same-term rules)
# Submit from this directory:
#   qsub build_protest2_datasets.sbatch
# Overrides: PYTHON_ENV, INTERMEDIATE, MEMORY_LIMIT. To reuse an existing protest2
# master and start at the check: qsub -v SKIP_MASTER=1 build_protest2_datasets.sbatch

set -euo pipefail

CODE_DIR="$(pwd)"
PYTHON_ENV="${PYTHON_ENV:-${HOME}/envs/downup_geo}"
INTERMEDIATE="${INTERMEDIATE:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate}"
MEMORY_LIMIT="${MEMORY_LIMIT:-60GB}"
THREADS="${NSLOTS:-10}"
PYTHON="${PYTHON_ENV}/bin/python"
MASTER="${INTERMEDIATE}/0_master_dataset_protest2.parquet"

LOG_DIR="${CODE_DIR}/logs/data_generation"
mkdir -p "${LOG_DIR}"
exec > >(tee "${LOG_DIR}/protest2_datasets.log") 2>&1

echo "[$(date '+%F %T')] host=$(hostname) job=${JOB_ID:-NA}"
echo "[$(date '+%F %T')] git HEAD=$(git rev-parse --short HEAD) branch=$(git rev-parse --abbrev-ref HEAD)"
for input in "${INTERMEDIATE}/8_grids_ac_pr2_5km.csv" "${INTERMEDIATE}/0_master_dataset.parquet"; do
    [[ -f "${input}" ]] || { echo "ERROR: missing ${input}" >&2; exit 1; }
done

if [[ "${SKIP_MASTER:-0}" == "1" && -f "${MASTER}" ]]; then
    echo "[$(date '+%F %T')] 1/4 reusing ${MASTER} (SKIP_MASTER=1)"
else
    echo "[$(date '+%F %T')] 1/4 master dataset with protest2"
    "${PYTHON}" build_0_master_dataset.py \
        --intermediate "${INTERMEDIATE}" \
        --protests "${INTERMEDIATE}/8_grids_ac_pr2_5km.csv" \
        --output-parquet "${MASTER}" \
        --skip-csv \
        --database "${INTERMEDIATE}/0_master_dataset_protest2.duckdb" \
        --temp-directory "${INTERMEDIATE}/0_master_dataset_protest2_duckdb_tmp" \
        --threads "${THREADS}" \
        --memory-limit "${MEMORY_LIMIT}" \
        --overwrite
fi

echo "[$(date '+%F %T')] 2/4 check against the production master"
"${PYTHON}" compare_master_datasets.py \
    --reference "${INTERMEDIATE}/0_master_dataset.parquet" \
    --candidate "${MASTER}" \
    --report "${LOG_DIR}/protest2_master_check.txt" \
    --threads "${THREADS}" \
    --memory-limit "${MEMORY_LIMIT}"

echo "[$(date '+%F %T')] 3/4 clustering crosswalk"
"${PYTHON}" build_grid_month_ac_area_tr.py \
    --master-parquet "${MASTER}" \
    --output "${INTERMEDIATE}/grid_month_ac_area_tr_protest2.dta" \
    --threads "${THREADS}" \
    --overwrite

echo "[$(date '+%F %T')] 4/4 same-term protest2 stack"
"${PYTHON}" build_stacked_protest_election_sameterm.py \
    --intermediate "${INTERMEDIATE}" \
    --input "${MASTER}" \
    --treatment-col protest5km \
    --treatment-name protest2_5km \
    --output-stem stacked_data_protest2_5km_election_sameterm \
    --overwrite \
    --threads "${THREADS}" \
    --memory-limit "${MEMORY_LIMIT}"

echo "[$(date '+%F %T')] done"

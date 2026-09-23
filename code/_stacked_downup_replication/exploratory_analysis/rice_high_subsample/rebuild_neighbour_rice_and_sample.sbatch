#!/usr/bin/env bash
#$ -N rh_neigh_prep
#$ -q largemem
#$ -pe smp 8
#$ -cwd
#$ -j y
#$ -o /dev/null

set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
INTERMEDIATE="${INTERMEDIATE:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate}"
PYTHON="${PYTHON_BIN:-/groups/sgulzar/india_forest_land/downup_geo/bin/python}"
DATA_CODE="${REPO}/code/_replication_package/data_generation"
SAMPLE_CODE="${REPO}/code/_stacked_downup_replication/exploratory_analysis/sample_data"
LOG_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/rice_high_subsample/logs"
LOG_FILE="${LOG_DIR}/rebuild_neighbour_rice_and_sample.log"

mkdir -p "${LOG_DIR}"
exec > >(tee "${LOG_FILE}") 2>&1

echo "[$(date '+%F %T')] rebuilding neighbour stack with master rice flag"

"${PYTHON}" "${DATA_CODE}/build_stacked_duckdb_unique_pair.py" \
  --input "${INTERMEDIATE}/0_ac_neighs_downup.csv" \
  --master-parquet "${INTERMEDIATE}/0_master_dataset.parquet" \
  --output "${INTERMEDIATE}/stacked_downup_neigh.csv" \
  --database "${INTERMEDIATE}/stacked_downup_neigh.db" \
  --temp-directory "${TMPDIR:-${INTERMEDIATE}/stacked_downup_neigh_duckdb_tmp}" \
  --treatment-col downwind_neighbours \
  --pair-cols unique_small_grid_id ac_uq_id_neighbor \
  --unit-cols unique_pair \
  --cutoff-year 2022 \
  --cutoff-month 8 \
  --pre-periods 6 \
  --post-periods 6 \
  --post-definition include_event \
  --threads "${NSLOTS:-8}" \
  --memory-limit "${MEMORY_LIMIT:-90GB}" \
  --write-manifest \
  --overwrite

echo "[$(date '+%F %T')] regenerating neighbour _sample"
"${PYTHON}" "${SAMPLE_CODE}/build_main_analysis_samples.py" \
  --intermediate "${INTERMEDIATE}" \
  --dataset stacked_downup_neigh.csv \
  --rate 0.005 \
  --minimum-units 30 \
  --seed 20260824 \
  --threads "${NSLOTS:-8}" \
  --memory-limit "${MEMORY_LIMIT:-90GB}" \
  --temp-directory "${TMPDIR:-${INTERMEDIATE}/main_analysis_sample_duckdb_tmp}" \
  --overwrite

head -n 1 "${INTERMEDIATE}/stacked_downup_neigh_sample.csv" | \
  grep -q 'rice_prod_aclvl_ahigh'

echo "[$(date '+%F %T')] neighbour full and sample datasets are ready"

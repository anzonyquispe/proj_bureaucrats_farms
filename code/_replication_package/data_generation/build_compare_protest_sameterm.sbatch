#!/bin/bash
#$ -N protest_sameterm
#$ -q long
#$ -pe smp 10
#$ -cwd
#$ -j y

# Rebuild the RA's same-election-term protest stack from 0_master_dataset.parquet
# and compare it with stacked_data_protest5km_election_sameterm.csv. Submit from
# this directory:
#   qsub build_compare_protest_sameterm.sbatch
# Overrides: PYTHON_ENV, INTERMEDIATE, MEMORY_LIMIT.
# Report: logs/data_generation/protest_sameterm_comparison/report.txt

set -euo pipefail

CODE_DIR="$(pwd)"
PYTHON_ENV="${PYTHON_ENV:-${HOME}/envs/downup_geo}"
INTERMEDIATE="${INTERMEDIATE:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate}"
MEMORY_LIMIT="${MEMORY_LIMIT:-60GB}"
THREADS="${NSLOTS:-10}"
STEM="stacked_data_protest5km_election_sameterm_rebuilt"
PYTHON="${PYTHON_ENV}/bin/python"

LOG_DIR="${CODE_DIR}/logs/data_generation"
mkdir -p "${LOG_DIR}"
exec > >(tee "${LOG_DIR}/protest_sameterm_rebuild.log") 2>&1

echo "[$(date '+%F %T')] host=$(hostname) job=${JOB_ID:-NA}"
echo "[$(date '+%F %T')] git HEAD=$(git rev-parse --short HEAD) branch=$(git rev-parse --abbrev-ref HEAD)"
echo "[$(date '+%F %T')] python=${PYTHON} intermediate=${INTERMEDIATE}"
"${PYTHON}" -c "import duckdb, pandas; print('duckdb', duckdb.__version__, 'pandas', pandas.__version__)"

echo "[$(date '+%F %T')] rebuilding the protest5km same-term stack"
"${PYTHON}" build_stacked_protest_election_sameterm.py \
    --intermediate "${INTERMEDIATE}" \
    --treatment-col protest5km \
    --output-stem "${STEM}" \
    --no-csv \
    --overwrite \
    --threads "${THREADS}" \
    --memory-limit "${MEMORY_LIMIT}"

echo "[$(date '+%F %T')] comparing with the RA's file"
"${PYTHON}" compare_protest_sameterm_stacks.py \
    --intermediate "${INTERMEDIATE}" \
    --candidate "${INTERMEDIATE}/${STEM}.parquet" \
    --threads "${THREADS}" \
    --memory-limit "${MEMORY_LIMIT}"

echo "[$(date '+%F %T')] done"

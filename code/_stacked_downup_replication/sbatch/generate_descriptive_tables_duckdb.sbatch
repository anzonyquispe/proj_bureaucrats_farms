#!/usr/bin/env bash
#SBATCH --job-name=descriptive_tables
#SBATCH --cpus-per-task=10
#SBATCH --mem=120G
#SBATCH --time=12:00:00
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
#$ -N descriptive_tables
#$ -q largemem
#$ -pe smp 10
#$ -cwd
#$ -j y
#$ -o /dev/null

set -euo pipefail

REPLICATION_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
REPLICATION_CODE="${REPLICATION_CODE:-${REPLICATION_REPO}/code/_stacked_downup_replication}"
PYTHON_ENV="${PYTHON_ENV:-/groups/sgulzar/india_forest_land/downup_geo}"
PYTHON_BIN="${PYTHON_ENV}/bin/python"
LOG_DIR="${REPLICATION_CODE}/logs"
LOG_FILE="${LOG_DIR}/generate_descriptive_tables_duckdb.log"

mkdir -p "${LOG_DIR}"
exec > >(tee "${LOG_FILE}") 2>&1

echo "[$(date '+%F %T')] Generating the three full-sample descriptive tables"
echo "Python: ${PYTHON_BIN}"
echo "Threads: 10; memory limit: 100GB"

if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "ERROR: Python is missing: ${PYTHON_BIN}" >&2
  exit 69
fi

export PATH="${PYTHON_ENV}/bin:${PATH}"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1

"${PYTHON_BIN}" "${REPLICATION_CODE}/python/generate_descriptive_tables_duckdb.py" \
  --root "${REPLICATION_ROOT}" \
  --output-root "${REPLICATION_REPO}" \
  --sample "" \
  --threads 10 \
  --memory-limit 100GB

echo "[$(date '+%F %T')] Completed descriptive tables"
echo "Outputs: ${REPLICATION_REPO}/tables"

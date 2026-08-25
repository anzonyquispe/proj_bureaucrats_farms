#!/usr/bin/env bash
# Regenerate only panelview_self_profession.png from the updated cluster master.

#SBATCH --job-name=panelview_selfprof
#SBATCH --cpus-per-task=1
#SBATCH --mem=120G
#SBATCH --time=12:00:00
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
#$ -N panelview_selfprof
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -j y
#$ -o /dev/null

set -euo pipefail

DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-${REPO}/code/_stacked_downup_replication}"
PYTHON_ENV="${PYTHON_ENV:-/groups/sgulzar/india_forest_land/downup_geo}"
PYTHON_BIN="${PYTHON_ENV}/bin/python"
LOG_DIR="${CODE}/logs"
LOG_FILE="${LOG_DIR}/panelview_self_profession.log"

mkdir -p "${LOG_DIR}" "${REPO}/figures"
exec > >(tee "${LOG_FILE}") 2>&1

echo "[$(date '+%F %T')] Regenerating panelview_self_profession.png"
echo "Input: ${DATA_ROOT}/data_output/intermediate/0_master_dataset.parquet"

if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "ERROR: Python executable is missing: ${PYTHON_BIN}" >&2
  exit 69
fi

export PATH="${PYTHON_ENV}/bin:${PATH}"
export MPLBACKEND=Agg
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1

"${PYTHON_BIN}" "${CODE}/python/generate_descriptive_figures.py" \
  --root "${DATA_ROOT}" \
  --output-root "${REPO}" \
  --only panelview

test -s "${REPO}/figures/panelview_self_profession.png"
echo "[$(date '+%F %T')] Completed: ${REPO}/figures/panelview_self_profession.png"

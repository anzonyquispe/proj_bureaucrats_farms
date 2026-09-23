#!/usr/bin/env bash
#$ -N main_samples
#$ -q largemem
#$ -pe smp 8
#$ -cwd
#$ -j y
#$ -o /dev/null
#$ -e /dev/null

set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
INTERMEDIATE="${INTERMEDIATE:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate}"
PYTHON="${PYTHON_BIN:-/groups/sgulzar/india_forest_land/downup_geo/bin/python}"
SCRIPT="${REPO}/code/_stacked_downup_replication/exploratory_analysis/sample_data/build_main_analysis_samples.py"
LOG_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/sample_data/logs"
LOG_FILE="${LOG_DIR}/build_main_analysis_samples.log"

mkdir -p "${LOG_DIR}"
exec > >(tee "${LOG_FILE}") 2>&1

echo "[$(date '+%F %T')] host=$(hostname) job=${JOB_ID:-local}"
echo "[$(date '+%F %T')] python=${PYTHON}"
echo "[$(date '+%F %T')] intermediate=${INTERMEDIATE}"
echo "[$(date '+%F %T')] sample rate=${SAMPLE_RATE:-0.005} minimum units/arm/cohort=${MINIMUM_UNITS:-30} seed=${SAMPLE_SEED:-20260824}"

if [[ ! -x "${PYTHON}" ]]; then
  echo "ERROR: Python executable not found: ${PYTHON}" >&2
  exit 66
fi
if [[ ! -f "${SCRIPT}" ]]; then
  echo "ERROR: sampling script not found: ${SCRIPT}" >&2
  exit 66
fi

"${PYTHON}" -c 'import duckdb; print("duckdb", duckdb.__version__)'

declare -a sample_args=(
  --intermediate "${INTERMEDIATE}"
  --rate "${SAMPLE_RATE:-0.005}"
  --minimum-units "${MINIMUM_UNITS:-30}"
  --seed "${SAMPLE_SEED:-20260824}"
  --threads "${NSLOTS:-8}"
  --memory-limit "${MEMORY_LIMIT:-48GB}"
  --temp-directory "${TMPDIR:-${INTERMEDIATE}/main_analysis_sample_duckdb_tmp}"
  --overwrite
)

# Normally the cluster samples stacked_downup_13kmpl.csv in INTERMEDIATE.  A
# retained pipeline database can be used directly when the CSV is unavailable.
if [[ -n "${SOURCE_13KM_DB:-}" ]]; then
  sample_args+=(
    --source-override
    "stacked_downup_13kmpl.csv=${SOURCE_13KM_DB}"
  )
fi

"${PYTHON}" "${SCRIPT}" "${sample_args[@]}"

echo "[$(date '+%F %T')] completed main-analysis samples"

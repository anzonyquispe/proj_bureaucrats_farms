#!/usr/bin/env bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N dcdh_pop
#$ -pe smp 60
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/dcdh_pop/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/dcdh_pop/logs

set -euo pipefail

ROOT="${ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
CODE_ROOT="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
DCDH_CODE="${CODE_ROOT}/exploratory_analysis/dcdh_pop"
PYTHON="${DCDH_PYTHON:-/groups/sgulzar/india_forest_land/did_stat/bin/python}"
DRIVER="${DRIVER:?Set DRIVER to noreset, reset6, or reset12}"
VARIANT="${VARIANT:?Set VARIANT to notrend or actrend}"
SWITCHERS="${SWITCHERS:-}"
REQUIRE_JOB_ID="${REQUIRE_JOB_ID:-}"

case "${DRIVER}" in
  noreset|reset6|reset12) ;;
  *) echo "ERROR: invalid DRIVER=${DRIVER}" >&2; exit 2 ;;
esac
case "${VARIANT}" in
  notrend|actrend) ;;
  *) echo "ERROR: invalid VARIANT=${VARIANT}" >&2; exit 2 ;;
esac
case "${SWITCHERS}" in
  ""|in|out) ;;
  *) echo "ERROR: invalid SWITCHERS=${SWITCHERS}" >&2; exit 2 ;;
esac

mkdir -p "${DCDH_CODE}/logs" "${DCDH_CODE}/results"
if [[ -n "${REQUIRE_JOB_ID}" && ! -f "${DCDH_CODE}/logs/${REQUIRE_JOB_ID}.success" ]]; then
  echo "ERROR: predecessor ${REQUIRE_JOB_ID} did not finish successfully." >&2
  exit 3
fi
test -x "${PYTHON}"
test -f "${ROOT}/data_output/intermediate/0_master_dataset.parquet"
test -f "${DCDH_CODE}/dCDH_downup_ac_pop_${DRIVER}.py"

export ROOT VARIANT SWITCHERS
export DCDH_LOCAL_OUT="${DCDH_CODE}/results"
export PYTHONUNBUFFERED=1
export POLARS_MAX_THREADS="${NSLOTS:-60}"
export OMP_NUM_THREADS="${NSLOTS:-60}"

echo "[$(date '+%F %T')] host=$(hostname) driver=${DRIVER} variant=${VARIANT} switchers=${SWITCHERS:-all}"
echo "[$(date '+%F %T')] master=${ROOT}/data_output/intermediate/0_master_dataset.parquet"
echo "[$(date '+%F %T')] python=${PYTHON} slots=${NSLOTS:-60}"

cd "${DCDH_CODE}"
"${PYTHON}" "dCDH_downup_ac_pop_${DRIVER}.py"
touch "${DCDH_CODE}/logs/${JOB_ID:-manual}.success"
echo "[$(date '+%F %T')] completed successfully"

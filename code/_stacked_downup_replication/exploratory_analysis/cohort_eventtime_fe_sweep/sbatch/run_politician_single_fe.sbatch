#!/usr/bin/env bash
#$ -N pol_fe
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
FE_ID="${FE_ID:?FE_ID must be an integer from 1 through 32}"
SAMPLE_SUFFIX="${ANALYSIS_SAMPLE_SUFFIX:-}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/cohort_eventtime_fe_sweep"
DOFILE="${ANALYSIS_DIR}/_politician_byprov_cohort_eventtime_fe_sweep.do"
LOG_DIR="${ANALYSIS_DIR}/logs/politician_current"
TABLE_DIR="${REPO}/tables/exploratory_analysis/cohort_eventtime_fe_sweep"
TAG=$(printf '%02d' "${FE_ID}")
LOG_FILE="${LOG_DIR}/politician_fe${TAG}.log"
EVENT_OUTPUT="${TABLE_DIR}/politician_byprov_cohorttime_fe${TAG}_event_rural_acpop_all.ster"
DID_OUTPUT="${TABLE_DIR}/politician_byprov_cohorttime_fe${TAG}_did_interaction_rural_acpop_all.ster"
WORK_DIR="${TMPDIR:-/tmp}/pol_fe${TAG}_${JOB_ID:-manual}"

[[ "${FE_ID}" =~ ^([1-9]|[12][0-9]|3[0-2])$ ]] || {
    echo "FE_ID must be an integer from 1 through 32; received ${FE_ID}." >&2
    exit 198
}
mkdir -p "${LOG_DIR}" "${TABLE_DIR}" "${WORK_DIR}"
exec > >(tee "${LOG_FILE}") 2>&1
cd "${WORK_DIR}"
ulimit -c 0 || true

[[ -f "${DOFILE}" ]] || { echo "Missing dofile: ${DOFILE}" >&2; exit 66; }

if ! type module >/dev/null 2>&1; then
    for init in /etc/profile.d/modules.sh /usr/share/Modules/init/bash; do
        [[ -r "${init}" ]] && source "${init}" && break
    done
fi
if ! type module >/dev/null 2>&1; then
    [[ "${FARMS_LOGIN_RETRY:-0}" == "1" ]] && exit 127
    export FARMS_LOGIN_RETRY=1
    exec /bin/bash -l "$0" "$@"
fi
module purge 2>/dev/null || true
module load stata gcc

STATA_BIN="${STATA_BIN:-stata-mp}"
command -v "${STATA_BIN}" >/dev/null 2>&1 || {
    echo "Stata executable not found: ${STATA_BIN}" >&2
    exit 127
}

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1 JULIA_NUM_THREADS=1
export POL_CTIME_FE_LIST="${FE_ID}"
export POL_CTIME_STAGE="both"
export ANALYSIS_SAMPLE_SUFFIX="${SAMPLE_SUFFIX}"

rm -f "${EVENT_OUTPUT}" "${DID_OUTPUT}"
echo "[$(date '+%F %T')] START politician FE=${FE_ID}; event study + DiD interaction; cores=${NSLOTS:-1}"
echo "[$(date '+%F %T')] INPUT politicians_characteristics_byprov${SAMPLE_SUFFIX}.csv"
"${STATA_BIN}" -b do "${DOFILE}" "${FE_ID}"

STATA_LOG=$(find . -maxdepth 1 -type f \
    -name '*politician_byprov_cohort_eventtime_fe_sweep.log' -print -quit)
if [[ -n "${STATA_LOG}" ]]; then
    printf '\n===== STATA TRANSCRIPT =====\n'
    cat "${STATA_LOG}"
fi

missing=0
for output in "${EVENT_OUTPUT}" "${DID_OUTPUT}"; do
    [[ -s "${output}" ]] || { echo "Missing or empty output: ${output}" >&2; missing=1; }
done
(( missing == 0 )) || exit 1
echo "[$(date '+%F %T')] COMPLETED politician FE=${FE_ID}"
echo "[$(date '+%F %T')] EVENT OUTPUT ${EVENT_OUTPUT}"
echo "[$(date '+%F %T')] DID OUTPUT   ${DID_OUTPUT}"

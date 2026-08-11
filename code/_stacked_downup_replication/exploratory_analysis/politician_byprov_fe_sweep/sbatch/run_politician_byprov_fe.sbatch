#!/usr/bin/env bash
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -j y
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep/logs

set -euo pipefail

: "${FE_ID:?Submit this job with FE_ID set to an integer from 1 through 32}"
if ! [[ "${FE_ID}" =~ ^([1-9]|[12][0-9]|3[0-2])$ ]]; then
    echo "Invalid FE_ID=${FE_ID}; expected 1,...,32" >&2
    exit 198
fi

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep"
DOFILE="${ANALYSIS_DIR}/_politician_byprov_fe_sweep.do"
LOG_DIR="${ANALYSIS_DIR}/logs"
WORK_DIR="${TMPDIR:-/tmp}/politician_byprov_fe_${JOB_ID:-manual}_${FE_ID}"

mkdir -p "${LOG_DIR}" "${WORK_DIR}"
cd "${WORK_DIR}"

if ! type module >/dev/null 2>&1; then
    for module_init in /etc/profile.d/modules.sh /usr/share/Modules/init/bash; do
        if [[ -r "${module_init}" ]]; then
            # shellcheck disable=SC1090
            source "${module_init}"
            break
        fi
    done
fi
if ! type module >/dev/null 2>&1; then
    if [[ "${FARMS_LOGIN_RETRY:-0}" == "1" ]]; then
        echo "The module command is unavailable even in a login shell." >&2
        exit 127
    fi
    export FARMS_LOGIN_RETRY=1
    exec /bin/bash -l "$0" "$@"
fi

module load stata gcc

STATA_BIN="${STATA_BIN:-stata-mp}"
if ! command -v "${STATA_BIN}" >/dev/null 2>&1; then
    echo "Stata executable not found: ${STATA_BIN}" >&2
    exit 127
fi

echo "[$(date '+%F %T')] job=${JOB_ID:-manual} host=$(hostname) FE=${FE_ID} cores=${NSLOTS:-1}"
echo "[$(date '+%F %T')] dofile=${DOFILE}"
export POL_BYPROV_FE_ID="${FE_ID}"
set +e
"${STATA_BIN}" -b do "${DOFILE}"
stata_status=$?
set -e

STATA_LOG="_politician_byprov_fe_sweep.log"
SAVED_LOG="${LOG_DIR}/politician_byprov_fe$(printf '%02d' "${FE_ID}")_${JOB_ID:-manual}.stata.log"
if [[ -f "${STATA_LOG}" ]]; then
    cp "${STATA_LOG}" "${SAVED_LOG}"
    cat "${STATA_LOG}"
else
    echo "Stata did not create its expected log: ${WORK_DIR}/${STATA_LOG}" >&2
    exit 66
fi
echo "[$(date '+%F %T')] FE=${FE_ID} Stata exit status=${stata_status} log=${SAVED_LOG}"
exit "${stata_status}"

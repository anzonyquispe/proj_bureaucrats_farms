#!/usr/bin/env bash
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

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
TABLE_DIR="${REPO}/tables/exploratory_analysis/politician_byprov_fe_sweep"
FIGURE_DIR="${REPO}/figures/exploratory_analysis/politician_byprov_fe_sweep"
FE_TAG=$(printf '%02d' "${FE_ID}")
EVENT_STEM="${TABLE_DIR}/politician_byprov_fe${FE_TAG}_event_rural_acpop_all"
DID_STEM="${TABLE_DIR}/politician_byprov_fe${FE_TAG}_did_interaction_rural_acpop_all"
DID_FIGURE="${FIGURE_DIR}/politician_byprov_fe${FE_TAG}_did_interaction_rural_acpop_all_1.png"
BASELINE_ORIGINAL="${FIGURE_DIR}/politician_byprov_fe${FE_TAG}_rural_acpop_all_baseline_ori.png"
BASELINE_ROTATED="${FIGURE_DIR}/politician_byprov_fe${FE_TAG}_rural_acpop_all_baseline_rotated.png"

mkdir -p "${LOG_DIR}" "${WORK_DIR}" "${TABLE_DIR}" "${FIGURE_DIR}"
cd "${WORK_DIR}"

# Do not allow a failed replacement job to leave an old result masquerading as
# a corrected cohort_id estimate. These are the exact outputs for this FE only.
if [[ "${REPLACE_RESULTS:-1}" == "1" ]]; then
    rm -f \
        "${EVENT_STEM}.ster" "${EVENT_STEM}.csv" \
        "${EVENT_STEM}_scalars.csv" \
        "${DID_STEM}.ster" "${DID_STEM}.csv" \
        "${DID_STEM}_scalars.csv" \
        "${DID_FIGURE}" "${BASELINE_ORIGINAL}" "${BASELINE_ROTATED}"
fi

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
echo "[$(date '+%F %T')] cohort identifier=cohort_id replacement=${REPLACE_RESULTS:-1}"
export POL_BYPROV_FE_ID="${FE_ID}"
set +e
"${STATA_BIN}" -b do "${DOFILE}"
stata_status=$?
set -e

STATA_LOG="_politician_byprov_fe_sweep.log"
SAVED_LOG="${LOG_DIR}/_politician_byprov_fe_sweep_fe${FE_TAG}.log"
if [[ -f "${STATA_LOG}" ]]; then
    cp "${STATA_LOG}" "${SAVED_LOG}"
    cat "${STATA_LOG}"
else
    echo "Stata did not create its expected log: ${WORK_DIR}/${STATA_LOG}" >&2
    exit 66
fi
if (( stata_status == 0 )); then
    for output in \
        "${EVENT_STEM}.ster" "${EVENT_STEM}.csv" \
        "${EVENT_STEM}_scalars.csv" \
        "${DID_STEM}.ster" "${DID_STEM}.csv" \
        "${DID_STEM}_scalars.csv" "${DID_FIGURE}"; do
        if [[ ! -s "${output}" ]]; then
            echo "Missing or empty corrected FE output: ${output}" >&2
            exit 1
        fi
    done
    for scalar_file in "${EVENT_STEM}_scalars.csv" "${DID_STEM}_scalars.csv"; do
        if ! grep -q "cohort_id" "${scalar_file}"; then
            echo "Corrected cohort_id tag absent from scalar output: ${scalar_file}" >&2
            exit 1
        fi
    done
fi
echo "[$(date '+%F %T')] FE=${FE_ID} Stata exit status=${stata_status} log=${SAVED_LOG}"
exit "${stata_status}"

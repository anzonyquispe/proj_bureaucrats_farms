#!/usr/bin/env bash
#$ -N rec_pol_fe
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

# Recover one politician FE and only the requested event/DiD stage.
set -euo pipefail
: "${RECOVERY_FE:?RECOVERY_FE must be an integer from 1 through 32}"
: "${CONTROL_SAMPLE:?CONTROL_SAMPLE must be never, both, or notyet}"
: "${ANALYSIS_STAGE:?ANALYSIS_STAGE must be event, did, or both}"
[[ "${RECOVERY_FE}" =~ ^([1-9]|[12][0-9]|3[0-2])$ ]] || exit 198
case "${CONTROL_SAMPLE}" in never|both|notyet) ;; *) exit 198 ;; esac
case "${ANALYSIS_STAGE}" in event|did|both) ;; *) exit 198 ;; esac

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep"
DOFILE="${ANALYSIS_DIR}/_run_politician_original_control_all32.do"
TAG=$(printf '%02d' "${RECOVERY_FE}")
LOG_DIR="${ANALYSIS_DIR}/logs/recovery/${CONTROL_SAMPLE}_fe${TAG}_${ANALYSIS_STAGE}"
WORK_DIR="${TMPDIR:-/tmp}/rec_pol_${JOB_ID:-manual}_${CONTROL_SAMPLE}_${TAG}_${ANALYSIS_STAGE}"
mkdir -p "${LOG_DIR}" "${WORK_DIR}"
cd "${WORK_DIR}"
ulimit -c 0 || true

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
command -v "${STATA_BIN}" >/dev/null 2>&1 || exit 127

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1 JULIA_NUM_THREADS=1
export POL_ORIGINAL_CONTROL_SAMPLE="${CONTROL_SAMPLE}"
export POL_ORIGINAL_FE_LIST="${RECOVERY_FE}"
export ANALYSIS_STAGE
unset ANALYSIS_SAMPLE_SUFFIX

TABLE_DIR="${REPO}/tables/exploratory_analysis/politician_original_controls_fe_sweep"
stem="politician_original_fe${TAG}_controls_${CONTROL_SAMPLE}"
outputs=()
if [[ "${ANALYSIS_STAGE}" == event || "${ANALYSIS_STAGE}" == both ]]; then
    outputs+=("${TABLE_DIR}/${stem}_event_rural_acpop_all.ster")
fi
if [[ "${ANALYSIS_STAGE}" == did || "${ANALYSIS_STAGE}" == both ]]; then
    outputs+=("${TABLE_DIR}/${stem}_did_interaction_rural_acpop_all.ster")
fi
rm -f "${outputs[@]}"

set +e
"${STATA_BIN}" -b do "${DOFILE}"
status=$?
set -e
LOG="_run_politician_original_control_all32.log"
[[ -f "${LOG}" ]] && cp "${LOG}" "${LOG_DIR}/${LOG}"
for output in "${outputs[@]}"; do
    [[ -s "${output}" ]] || { echo "Missing recovery output: ${output}" >&2; exit 1; }
done
(( status == 0 )) || { echo "Stata recovery failed with status ${status}" >&2; exit "${status}"; }
echo "Completed politician controls=${CONTROL_SAMPLE}, FE=${RECOVERY_FE}, stage=${ANALYSIS_STAGE}"

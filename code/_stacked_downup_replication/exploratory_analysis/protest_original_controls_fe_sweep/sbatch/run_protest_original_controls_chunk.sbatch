#!/usr/bin/env bash
#$ -N pr_orig_chunk
#$ -q largemem
#$ -pe smp 5
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

# One scheduler job and one Stata process run one FE chunk for one control group.
set -euo pipefail
: "${FE_LIST:?FE_LIST must be 1/15 or 16/32}"
: "${CONTROL_SAMPLE:?CONTROL_SAMPLE must be never, both, or notyet}"
case "${FE_LIST}" in 1/15|16/32) ;; *) exit 198 ;; esac
case "${CONTROL_SAMPLE}" in never|both|notyet) ;; *) exit 198 ;; esac

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/protest_original_controls_fe_sweep"
DOFILE="${ANALYSIS_DIR}/_protest_original_controls_fe_sweep.do"
LOG_DIR="${ANALYSIS_DIR}/logs"
TAG="${FE_LIST//\//_}"
WORK_DIR="${TMPDIR:-/tmp}/protest_original_${JOB_ID:-manual}_${CONTROL_SAMPLE}_${TAG}"
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

export OMP_NUM_THREADS=5 OPENBLAS_NUM_THREADS=5 MKL_NUM_THREADS=5
export NUMEXPR_NUM_THREADS=5 JULIA_NUM_THREADS=5
export PROTEST_FE_LIST="${FE_LIST}" PROTEST_CONTROL_SAMPLE="${CONTROL_SAMPLE}"
echo "[$(date '+%F %T')] one Stata process: controls=${CONTROL_SAMPLE}, FE=${FE_LIST}, cores=${NSLOTS:-5}"

set +e
"${STATA_BIN}" -b do "${DOFILE}"
status=$?
set -e
LOG="_protest_original_controls_fe_sweep.log"
FINAL_LOG_DIR="${LOG_DIR}/${CONTROL_SAMPLE}_${TAG}"
mkdir -p "${FINAL_LOG_DIR}"
[[ -f "${LOG}" ]] && cp "${LOG}" "${FINAL_LOG_DIR}/${LOG}"

case "${FE_LIST}" in 1/15) first=1; last=15 ;; 16/32) first=16; last=32 ;; esac
TABLE_DIR="${REPO}/tables/exploratory_analysis/protest_original_controls_fe_sweep"
FIGURE_DIR="${REPO}/figures/exploratory_analysis/protest_original_controls_fe_sweep"
missing=0
for n in $(seq "${first}" "${last}"); do
    fe=$(printf '%02d' "${n}")
    stem="protest_original_fe${fe}_controls_${CONTROL_SAMPLE}"
    for output in \
        "${TABLE_DIR}/${stem}_event_rural_acpop_all.csv" \
        "${TABLE_DIR}/${stem}_did_interaction_rural_acpop_all.csv" \
        "${FIGURE_DIR}/${stem}_did_interaction_rural_acpop_all_1.png"; do
        [[ -s "${output}" ]] || { echo "Missing: ${output}" >&2; missing=1; }
    done
done
if (( missing != 0 )); then
    (( status != 0 )) && exit "${status}"
    exit 1
fi
(( status == 0 )) || echo "WARNING: Stata exited ${status} after all outputs were verified." >&2

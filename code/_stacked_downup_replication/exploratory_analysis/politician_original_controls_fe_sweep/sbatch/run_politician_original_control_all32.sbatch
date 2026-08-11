#!/usr/bin/env bash
#$ -N pol_orig_32
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -j y
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep/logs

# One scheduler job and one Stata process run all 32 FEs for one control group.
set -euo pipefail
: "${CONTROL_SAMPLE:?CONTROL_SAMPLE must be never, both, or notyet}"
case "${CONTROL_SAMPLE}" in never|both|notyet) ;; *) exit 198 ;; esac

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep"
DOFILE="${ANALYSIS_DIR}/_run_politician_original_control_all32.do"
LOG_DIR="${ANALYSIS_DIR}/logs"
WORK_DIR="${TMPDIR:-/tmp}/pol_original_${JOB_ID:-manual}_${CONTROL_SAMPLE}"
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
echo "[$(date '+%F %T')] one Stata process: controls=${CONTROL_SAMPLE}, FE=1/32"

set +e
"${STATA_BIN}" -b do "${DOFILE}"
status=$?
set -e
LOG="_run_politician_original_control_all32.log"
[[ -f "${LOG}" ]] && cp "${LOG}" "${LOG_DIR}/politician_original_${CONTROL_SAMPLE}_all32_${JOB_ID:-manual}.stata.log"
[[ -f "${LOG}" ]] && cat "${LOG}"

TABLE_DIR="${REPO}/tables/exploratory_analysis/politician_original_controls_fe_sweep"
FIGURE_DIR="${REPO}/figures/exploratory_analysis/politician_original_controls_fe_sweep"
missing=0
for fe in $(seq -w 1 32); do
    stem="politician_original_fe${fe}_controls_${CONTROL_SAMPLE}"
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

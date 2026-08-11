#!/usr/bin/env bash
#$ -N pol_orig_32
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -j y
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep/logs

# One scheduler job runs all 32 politician FE specifications sequentially for
# one control definition.  Three copies of this job use three cores in total.

set -euo pipefail

: "${CONTROL_SAMPLE:?CONTROL_SAMPLE must be never, both, or notyet}"
case "${CONTROL_SAMPLE}" in
    never|both|notyet) ;;
    *) echo "Invalid CONTROL_SAMPLE=${CONTROL_SAMPLE}" >&2; exit 198 ;;
esac

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep"
DOFILE="${ANALYSIS_DIR}/_politician_original_controls_fe_sweep.do"
LOG_DIR="${ANALYSIS_DIR}/logs"
WORK_ROOT="${TMPDIR:-/tmp}/pol_original_${JOB_ID:-manual}_${CONTROL_SAMPLE}"
mkdir -p "${LOG_DIR}" "${WORK_ROOT}"

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

module purge 2>/dev/null || true
module load stata gcc
STATA_BIN="${STATA_BIN:-stata-mp}"
command -v "${STATA_BIN}" >/dev/null 2>&1 || {
    echo "Stata executable not found: ${STATA_BIN}" >&2
    exit 127
}

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1 JULIA_NUM_THREADS=1
export POL_ORIGINAL_CONTROL_SAMPLE="${CONTROL_SAMPLE}"

for FE_ID in $(seq 1 32); do
    FE_TAG=$(printf '%02d' "${FE_ID}")
    WORK_DIR="${WORK_ROOT}/fe${FE_TAG}"
    mkdir -p "${WORK_DIR}"
    cd "${WORK_DIR}"
    export POL_ORIGINAL_FE_ID="${FE_ID}"
    echo "[$(date '+%F %T')] controls=${CONTROL_SAMPLE} FE=${FE_ID}/32"
    "${STATA_BIN}" -b do "${DOFILE}"
    STATA_LOG="_politician_original_controls_fe_sweep.log"
    if [[ ! -f "${STATA_LOG}" ]]; then
        echo "Stata log missing for FE ${FE_ID}" >&2
        exit 66
    fi
    cp "${STATA_LOG}" \
        "${LOG_DIR}/politician_original_${CONTROL_SAMPLE}_fe${FE_TAG}_${JOB_ID:-manual}.stata.log"
    cat "${STATA_LOG}"
done

echo "[$(date '+%F %T')] completed controls=${CONTROL_SAMPLE}, FE 1-32"

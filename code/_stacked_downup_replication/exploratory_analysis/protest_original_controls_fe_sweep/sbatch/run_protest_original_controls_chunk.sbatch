#!/usr/bin/env bash
#$ -N pr_orig_chunk
#$ -q largemem
#$ -pe smp 5
#$ -cwd
#$ -j y
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/protest_original_controls_fe_sweep/logs

set -euo pipefail
: "${FE_LIST:?FE_LIST must be 1/15 or 16/32}"
: "${CONTROL_SAMPLE:?CONTROL_SAMPLE must be never, both, or notyet}"
case "${FE_LIST}" in 1/15|16/32) ;; *) echo "Invalid FE_LIST=${FE_LIST}" >&2; exit 198 ;; esac
case "${CONTROL_SAMPLE}" in never|both|notyet) ;; *) echo "Invalid controls" >&2; exit 198 ;; esac

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/protest_original_controls_fe_sweep"
DOFILE="${ANALYSIS_DIR}/_protest_original_controls_fe_sweep.do"
LOG_DIR="${ANALYSIS_DIR}/logs"
CHUNK_TAG="${FE_LIST//\//_}"
WORK_DIR="${TMPDIR:-/tmp}/protest_original_${JOB_ID:-manual}_${CONTROL_SAMPLE}_${CHUNK_TAG}"
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
module purge 2>/dev/null || true
module load stata gcc
STATA_BIN="${STATA_BIN:-stata-mp}"
command -v "${STATA_BIN}" >/dev/null 2>&1 || exit 127

export OMP_NUM_THREADS=5 OPENBLAS_NUM_THREADS=5 MKL_NUM_THREADS=5
export NUMEXPR_NUM_THREADS=5 JULIA_NUM_THREADS=5 PROTEST_FE_LIST="${FE_LIST}"
export PROTEST_CONTROL_SAMPLE="${CONTROL_SAMPLE}"
echo "[$(date '+%F %T')] controls=${CONTROL_SAMPLE} FE=${FE_LIST} slots=${NSLOTS:-5}"
"${STATA_BIN}" -b do "${DOFILE}"

STATA_LOG="_protest_original_controls_fe_sweep.log"
SAVED_LOG="${LOG_DIR}/protest_original_${CONTROL_SAMPLE}_${CHUNK_TAG}_${JOB_ID:-manual}.stata.log"
if [[ ! -f "${STATA_LOG}" ]]; then
    echo "Stata did not create ${STATA_LOG}" >&2
    exit 66
fi
cp "${STATA_LOG}" "${SAVED_LOG}"
cat "${STATA_LOG}"
echo "[$(date '+%F %T')] completed log=${SAVED_LOG}"

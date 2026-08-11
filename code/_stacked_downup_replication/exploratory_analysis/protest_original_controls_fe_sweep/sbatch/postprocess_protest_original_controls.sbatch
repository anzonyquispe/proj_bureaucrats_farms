#!/usr/bin/env bash
#$ -N pr_orig_post
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

set -euo pipefail
REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
export ANALYSIS_SAMPLE_SUFFIX="${ANALYSIS_SAMPLE_SUFFIX:-}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/protest_original_controls_fe_sweep"
LOG_DIR="${ANALYSIS_DIR}/logs"
mkdir -p "${LOG_DIR}"
RUN_LOG="${LOG_DIR}/postprocess_protest_original_controls.log"
[[ "${ANALYSIS_SAMPLE_SUFFIX}" == "_sample" ]] && \
    RUN_LOG="${LOG_DIR}/sample/postprocess_protest_original_controls.log"
mkdir -p "$(dirname "${RUN_LOG}")"
exec > >(tee "${RUN_LOG}") 2>&1

if ! type module >/dev/null 2>&1; then
    for module_init in /etc/profile.d/modules.sh /usr/share/Modules/init/bash; do
        [[ -r "${module_init}" ]] && source "${module_init}" && break
    done
fi
if ! type module >/dev/null 2>&1; then
    [[ "${FARMS_LOGIN_RETRY:-0}" == "1" ]] && exit 127
    export FARMS_LOGIN_RETRY=1
    exec /bin/bash -l "$0" "$@"
fi
module purge 2>/dev/null || true
module load stata gcc R
RSCRIPT_BIN="${RSCRIPT_BIN:-Rscript}"
STATA_BIN="${STATA_BIN:-stata-mp}"
if ! command -v "${STATA_BIN}" >/dev/null 2>&1; then
    echo "Stata is unavailable: ${STATA_BIN}" >&2
    exit 127
fi
if ! command -v "${RSCRIPT_BIN}" >/dev/null 2>&1; then
    echo "Rscript is unavailable: ${RSCRIPT_BIN}" >&2
    exit 127
fi

WORK_DIR="${TMPDIR:-/tmp}/protest_postprocess_${JOB_ID:-manual}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"
POST_DOF="${ANALYSIS_DIR}/_postprocess_protest_original_controls.do"
"${STATA_BIN}" -b do "${POST_DOF}"
STATA_LOG="_postprocess_protest_original_controls.log"
FINAL_LOG_DIR="${LOG_DIR}/postprocess"
[[ "${ANALYSIS_SAMPLE_SUFFIX}" == "_sample" ]] && \
    FINAL_LOG_DIR="${LOG_DIR}/sample/postprocess"
mkdir -p "${FINAL_LOG_DIR}"
if [[ ! -f "${STATA_LOG}" ]]; then
    echo "Missing Stata postprocessing log: ${WORK_DIR}/${STATA_LOG}" >&2
    exit 66
fi
cp "${STATA_LOG}" "${FINAL_LOG_DIR}/${STATA_LOG}"

cd "${REPO}"
plot_args=(--root "${REPO}" --output-root "${REPO}")
[[ "${ANALYSIS_SAMPLE_SUFFIX}" == "_sample" ]] && plot_args+=(--sample)
"${RSCRIPT_BIN}" "${ANALYSIS_DIR}/plot_protest_original_controls_fe_sweep.R" \
    "${plot_args[@]}"

if [[ "${ANALYSIS_SAMPLE_SUFFIX}" == "_sample" ]]; then
    echo "[$(date '+%F %T')] Sample STER/CSV/plot postprocessing completed"
    exit 0
fi
"${RSCRIPT_BIN}" "${ANALYSIS_DIR}/build_protest_original_controls_reports.R" \
    --root "${REPO}"

PDF_DIR="${REPO}/code/_report"
TABLE_DIR="${REPO}/code/_report"
mkdir -p "${PDF_DIR}"
if ! command -v pdflatex >/dev/null 2>&1; then
    echo "pdflatex unavailable; TeX reports remain in ${TABLE_DIR}" >&2
    exit 127
fi
for controls in never both notyet; do
    tex="${TABLE_DIR}/protest_original_controls_${controls}_report.tex"
    pdflatex -interaction=nonstopmode -halt-on-error -output-directory="${PDF_DIR}" "${tex}"
    pdflatex -interaction=nonstopmode -halt-on-error -output-directory="${PDF_DIR}" "${tex}"
done

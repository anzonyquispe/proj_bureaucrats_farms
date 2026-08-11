#!/usr/bin/env bash
#$ -N pol_orig_post
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
export ANALYSIS_SAMPLE_SUFFIX="${ANALYSIS_SAMPLE_SUFFIX:-}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep"
LOG_DIR="${ANALYSIS_DIR}/logs"
mkdir -p "${LOG_DIR}"
RUN_LOG="${LOG_DIR}/postprocess_politician_original_controls.log"
[[ "${ANALYSIS_SAMPLE_SUFFIX}" == "_sample" ]] && \
    RUN_LOG="${LOG_DIR}/sample/postprocess_politician_original_controls.log"
mkdir -p "$(dirname "${RUN_LOG}")"
exec > >(tee "${RUN_LOG}") 2>&1
PLOT_SCRIPT="${ANALYSIS_DIR}/plot_politician_original_controls_fe_sweep.R"
REPORT_SCRIPT="${ANALYSIS_DIR}/build_politician_original_controls_reports.R"
PDF_DIR="${REPO}/code/_report"

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
module load stata gcc R

RSCRIPT_BIN="${RSCRIPT_BIN:-Rscript}"
STATA_BIN="${STATA_BIN:-stata-mp}"
if ! command -v "${RSCRIPT_BIN}" >/dev/null 2>&1; then
    echo "Rscript is unavailable." >&2
    exit 127
fi
if ! command -v "${STATA_BIN}" >/dev/null 2>&1; then
    echo "Stata is unavailable: ${STATA_BIN}" >&2
    exit 127
fi

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
mkdir -p "${PDF_DIR}"
WORK_DIR="${TMPDIR:-/tmp}/politician_postprocess_${JOB_ID:-manual}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"
POST_DOF="${ANALYSIS_DIR}/_postprocess_politician_original_controls.do"
"${STATA_BIN}" -b do "${POST_DOF}"
STATA_LOG="_postprocess_politician_original_controls.log"
confirm_log="${LOG_DIR}/postprocess/${STATA_LOG}"
[[ "${ANALYSIS_SAMPLE_SUFFIX}" == "_sample" ]] && \
    confirm_log="${LOG_DIR}/sample/postprocess/${STATA_LOG}"
mkdir -p "$(dirname "${confirm_log}")"
if [[ ! -f "${STATA_LOG}" ]]; then
    echo "Missing Stata postprocessing log: ${WORK_DIR}/${STATA_LOG}" >&2
    exit 66
fi
cp "${STATA_LOG}" "${confirm_log}"

cd "${REPO}"

echo "[$(date '+%F %T')] Rendering 192 event-study figures from exported CSVs"
plot_args=(--root "${REPO}" --output-root "${REPO}")
[[ "${ANALYSIS_SAMPLE_SUFFIX}" == "_sample" ]] && plot_args+=(--sample)
"${RSCRIPT_BIN}" "${PLOT_SCRIPT}" "${plot_args[@]}"

if [[ "${ANALYSIS_SAMPLE_SUFFIX}" == "_sample" ]]; then
    echo "[$(date '+%F %T')] Sample STER/CSV/plot postprocessing completed"
    exit 0
fi

echo "[$(date '+%F %T')] Building three LaTeX reports"
"${RSCRIPT_BIN}" "${REPORT_SCRIPT}" --root "${REPO}"

if ! command -v pdflatex >/dev/null 2>&1; then
    echo "pdflatex is unavailable; TeX reports were generated in:" >&2
    echo "${REPO}/tables/exploratory_analysis/politician_original_controls_fe_sweep" >&2
    exit 127
fi

TABLE_DIR="${REPO}/code/_report"
for control_sample in never both notyet; do
    tex_file="${TABLE_DIR}/politician_original_controls_${control_sample}_report.tex"
    pdflatex -interaction=nonstopmode -halt-on-error \
        -output-directory="${PDF_DIR}" "${tex_file}"
    pdflatex -interaction=nonstopmode -halt-on-error \
        -output-directory="${PDF_DIR}" "${tex_file}"
done

echo "[$(date '+%F %T')] Completed three reports in ${PDF_DIR}"

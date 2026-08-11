#!/usr/bin/env bash
#$ -N pol_orig_post
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -j y
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep/logs

set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep"
PLOT_SCRIPT="${ANALYSIS_DIR}/plot_politician_original_controls_fe_sweep.R"
REPORT_SCRIPT="${ANALYSIS_DIR}/build_politician_original_controls_reports.R"
PDF_DIR="${REPO}/output/pdf"

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
module load R

RSCRIPT_BIN="${RSCRIPT_BIN:-Rscript}"
if ! command -v "${RSCRIPT_BIN}" >/dev/null 2>&1; then
    echo "Rscript is unavailable." >&2
    exit 127
fi

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
mkdir -p "${PDF_DIR}"
cd "${REPO}"

echo "[$(date '+%F %T')] Rendering 192 event-study figures"
"${RSCRIPT_BIN}" "${PLOT_SCRIPT}" \
    --root "${REPO}" --output-root "${REPO}"

echo "[$(date '+%F %T')] Building three LaTeX reports"
"${RSCRIPT_BIN}" "${REPORT_SCRIPT}" --root "${REPO}"

if ! command -v pdflatex >/dev/null 2>&1; then
    echo "pdflatex is unavailable; TeX reports were generated in:" >&2
    echo "${REPO}/tables/exploratory_analysis/politician_original_controls_fe_sweep" >&2
    exit 127
fi

TABLE_DIR="${REPO}/tables/exploratory_analysis/politician_original_controls_fe_sweep"
for control_sample in never both notyet; do
    tex_file="${TABLE_DIR}/politician_original_controls_${control_sample}_report.tex"
    pdflatex -interaction=nonstopmode -halt-on-error \
        -output-directory="${PDF_DIR}" "${tex_file}"
    pdflatex -interaction=nonstopmode -halt-on-error \
        -output-directory="${PDF_DIR}" "${tex_file}"
done

echo "[$(date '+%F %T')] Completed three reports in ${PDF_DIR}"


#!/usr/bin/env bash
#$ -N pr_orig_post
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -j y
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/protest_original_controls_fe_sweep/logs

set -euo pipefail
REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/protest_original_controls_fe_sweep"

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
module load R
RSCRIPT_BIN="${RSCRIPT_BIN:-Rscript}"

cd "${REPO}"
"${RSCRIPT_BIN}" "${ANALYSIS_DIR}/plot_protest_original_controls_fe_sweep.R" \
    --root "${REPO}" --output-root "${REPO}"
"${RSCRIPT_BIN}" "${ANALYSIS_DIR}/build_protest_original_controls_reports.R" \
    --root "${REPO}"

PDF_DIR="${REPO}/output/pdf"
TABLE_DIR="${REPO}/tables/exploratory_analysis/protest_original_controls_fe_sweep"
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

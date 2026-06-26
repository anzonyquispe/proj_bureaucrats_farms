#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N stacked_stata_analysis
#$ -pe smp 4
#$ -cwd

# Run all six stacked event-study Stata do files:
#   _stacked_analysis.do              (downup_ac, unbalanced)
#   _stacked_analysis_balanced.do     (downup_ac, balanced control panel)
#   _stacked_analysis_pop.do          (downup_ac_pop, unbalanced)
#   _stacked_analysis_balanced_pop.do (downup_ac_pop, balanced)
#   _stacked_analysis_5pre.do         (downup_ac, 5 pre-treatment periods)
#   _stacked_analysis_pop_5pre.do     (downup_ac_pop, 5 pre-treatment periods)
#
# Run AFTER both _stacked_build_downup and _stacked_build_downup_pop jobs
# have completed (combined_dt.dta and combined_dt_pop.dta must exist).

set -euo pipefail

ROOT="/users/aquisper/proj_bureaucrats_farms"
CODE_DIR="${ROOT}/code/_stacked_downup"
cd "${CODE_DIR}"

echo "[$(date '+%F %T')] host=$(hostname) job=${JOB_ID:-NA} pwd=$(pwd)"
if command -v git >/dev/null 2>&1; then
    echo "[$(date '+%F %T')] git HEAD: $(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo 'not-a-git-repo')"
fi

module purge 2>/dev/null || true
module load stata

export TMPDIR="${TMPDIR:-/tmp}/stata.${JOB_ID:-$$}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

run_do() {
    local dofile="$1"
    echo ""
    echo "=========================================="
    echo "Running ${dofile}"
    echo "=========================================="
    rm -f "${dofile%.do}.log"
    stata-mp -b do "${dofile}"
    echo "Done: ${dofile}"
}

run_do _stacked_analysis.do
run_do _stacked_analysis_balanced.do
run_do _stacked_analysis_pop.do
run_do _stacked_analysis_balanced_pop.do
run_do _stacked_analysis_5pre.do
run_do _stacked_analysis_pop_5pre.do

echo ""
echo "=========================================="
echo "All stacked Stata analyses complete."
echo "Ster and CSV files written to tex/paper/tables/."
echo "Includes 5pre variants: stacked_event_study_5pre and stacked_event_study_pop_5pre."
echo "=========================================="

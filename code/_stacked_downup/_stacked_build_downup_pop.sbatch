#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N stacked_build_downup_pop
#$ -pe smp 20
#$ -cwd

# Build + bundle the stacked DiD dataset for the downup_ac_pop treatment.
# Step 1: _build_stacked_downup_pop.R  (parallel, 10 workers, writes .dta per cohort)
# Step 2: _bundle_stacked_downup_pop.R (sequential, aggregates to combined_dt_pop.dta)

set -euo pipefail

ROOT="/users/aquisper/proj_bureaucrats_farms"
CODE_DIR="${ROOT}/code/_stacked_downup"
cd "${CODE_DIR}"

echo "[$(date '+%F %T')] host=$(hostname) job=${JOB_ID:-NA} pwd=$(pwd)"
if command -v git >/dev/null 2>&1; then
    echo "[$(date '+%F %T')] git HEAD: $(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo 'not-a-git-repo')"
fi

module purge 2>/dev/null || true
module load R

export LOCATION=shell
export SAMPLE=""
export CORES=10
# On the cluster the Downloads dir won't exist; the build script falls back to
# data_output/intermediate automatically.
export DOWNLOADS_DIR="${ROOT}/data_output/intermediate"

echo "=========================================="
echo "Step 1: Building per-cohort stacked data (pop)"
echo "=========================================="
Rscript _build_stacked_downup_pop.R

echo ""
echo "=========================================="
echo "Step 2: Bundling cohort files -> combined_dt_pop.dta"
echo "=========================================="
Rscript _bundle_stacked_downup_pop.R

echo ""
echo "Done: combined_dt_pop.dta written to data_output/intermediate/"

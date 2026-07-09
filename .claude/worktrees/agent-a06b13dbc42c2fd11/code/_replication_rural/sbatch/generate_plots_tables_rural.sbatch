#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N gen_plots_tables_rural
#$ -pe smp 4
#$ -cwd

# -----------------------------------------------------------------------------
# Generate all tables, event-study plots, and interaction plots (RURAL).
# Runs: _generate_all_tables.do, plotting_event_studies.R, plotting_interaction.do
#
# Robustness preamble: fail loud, run the latest checked-out code, and start
# each step in a clean module/temp environment so this job never picks up
# stale state from a prior submission.
# -----------------------------------------------------------------------------
set -euo pipefail

# Always run from the canonical project tree on the cluster.
ROOT="/users/aquisper/proj_bureaucrats_farms"
CODE_DIR="${ROOT}/code/_replication_rural"
cd "${CODE_DIR}"

echo "[$(date '+%F %T')] host=$(hostname) job=${JOB_ID:-NA} pwd=$(pwd)"
if command -v git >/dev/null 2>&1; then
    echo "[$(date '+%F %T')] git HEAD: $(git -C "${CODE_DIR}" rev-parse --short HEAD 2>/dev/null || echo 'not-a-git-repo')"
fi

# Force a clean module environment.
module purge 2>/dev/null || true

# Per-job scratch dir.
export TMPDIR="${TMPDIR:-/tmp}/stata.${JOB_ID:-$$}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "=========================================="
echo "Starting RURAL analysis pipeline"
echo "=========================================="

#-------------------------------------------------------------------------------
# Step 1: Generate all tables (Stata)
#-------------------------------------------------------------------------------
echo ""
echo "Step 1: Running _generate_all_tables.do..."
echo "----------------------------------------"
module load stata
rm -f _generate_all_tables.log
stata-mp -b do _generate_all_tables.do
echo "Tables generated."
module unload stata 2>/dev/null || true

#-------------------------------------------------------------------------------
# Step 2: Plot event studies (R)
#-------------------------------------------------------------------------------
echo ""
echo "Step 2: Running plotting_event_studies.R..."
echo "----------------------------------------"
module load R
Rscript plotting_event_studies.R
echo "Event study plots generated."
module unload R 2>/dev/null || true

#-------------------------------------------------------------------------------
# Step 3: Plot interactions (Stata)
#-------------------------------------------------------------------------------
echo ""
echo "Step 3: Running plotting_interaction.do..."
echo "----------------------------------------"
module load stata
rm -f plotting_interaction.log
stata-mp -b do plotting_interaction.do
echo "Interaction plots generated."

#-------------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "RURAL analysis pipeline complete!"
echo "=========================================="

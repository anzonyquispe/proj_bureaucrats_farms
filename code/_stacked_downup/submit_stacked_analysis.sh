#!/bin/bash
# Submit each stacked event-study do file as its own independent SGE job.
# Assumes combined_dt.dta and combined_dt_pop.dta already exist.
#
# Usage (from _stacked_downup/):
#   bash submit_stacked_analysis.sh

set -eu
cd "$(dirname "$0")"

JOBS=(
  _stacked_analysis
  _stacked_analysis_balanced
  _stacked_analysis_pop
  _stacked_analysis_balanced_pop
  _stacked_analysis_5pre
  _stacked_analysis_pop_5pre
)

for j in "${JOBS[@]}"; do
  echo "qsub ${j}.sbatch"
  qsub "${j}.sbatch"
done

echo ""
echo "Submitted ${#JOBS[@]} jobs. Monitor with: qstat -u \$USER"

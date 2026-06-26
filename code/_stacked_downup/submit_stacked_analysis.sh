#!/bin/bash
# Submit the stacked event-study Stata analysis.
# Assumes combined_dt.dta and combined_dt_pop.dta already exist in
# data_output/intermediate/ (data build step is not needed).
#
# Runs all six do files in one job:
#   _stacked_analysis.do
#   _stacked_analysis_balanced.do
#   _stacked_analysis_pop.do
#   _stacked_analysis_balanced_pop.do
#   _stacked_analysis_5pre.do
#   _stacked_analysis_pop_5pre.do
#
# Usage (from _stacked_downup/):
#   bash submit_stacked_analysis.sh

set -eu
cd "$(dirname "$0")"

echo "Submitting stacked Stata analysis..."
qsub _stacked_stata_analysis.sbatch
echo "Submitted. Monitor with: qstat -u \$USER"

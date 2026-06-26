#!/bin/bash
# Submit the three-stage stacked DiD pipeline:
#
#   Stage 1a (parallel with 1b): build + bundle downup_ac
#   Stage 1b (parallel with 1a): build + bundle downup_ac_pop
#   Stage 2  (depends on 1a+1b): run all four Stata do files
#
# Usage (from _stacked_downup/):
#   bash submit_stacked.sh
#
# After stage 2 finishes, run the main generate_plots_tables_rural.sbatch
# (or plotting_event_studies.R directly) to produce the event-study PNGs.

set -eu
cd "$(dirname "$0")"

echo "Submitting stacked DiD pipeline..."
echo ""

# Stage 1a: build + bundle downup_ac
JOB_AC=$(qsub -terse _stacked_build_downup.sbatch)
echo "Submitted _stacked_build_downup.sbatch  -> job ${JOB_AC}"

# Stage 1b: build + bundle downup_ac_pop
JOB_POP=$(qsub -terse _stacked_build_downup_pop.sbatch)
echo "Submitted _stacked_build_downup_pop.sbatch -> job ${JOB_POP}"

# Stage 2: Stata analysis (depends on both stage 1 jobs)
JOB_STATA=$(qsub -terse -hold_jid "${JOB_AC},${JOB_POP}" _stacked_stata_analysis.sbatch)
echo "Submitted _stacked_stata_analysis.sbatch   -> job ${JOB_STATA} (holds on ${JOB_AC},${JOB_POP})"

echo ""
echo "All three jobs submitted."
echo "Monitor with: qstat -u \$USER"
echo ""
echo "After job ${JOB_STATA} finishes, run plotting_event_studies.R to generate PNGs."

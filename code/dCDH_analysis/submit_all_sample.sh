#!/bin/bash
# Submit all 4 sample-data smoke-test sbatch jobs (-pe smp 5, SAMPLE=_sample).
# Use this to verify the pipeline on the cluster before launching production.
#
# Usage:
#   bash submit_all_sample.sh

set -eu
cd "$(dirname "$0")"

JOBS=(
  dCDH_downup_ac_reset6_sample
  dCDH_downup_ac_reset12_sample
  dCDH_downup_ac_pop_reset6_sample
  dCDH_downup_ac_pop_reset12_sample
)

for j in "${JOBS[@]}"; do
  echo "qsub ${j}.sbatch"
  qsub "${j}.sbatch"
done

echo
echo "Submitted ${#JOBS[@]} sample jobs. Run 'qstat -u \$USER' to monitor."

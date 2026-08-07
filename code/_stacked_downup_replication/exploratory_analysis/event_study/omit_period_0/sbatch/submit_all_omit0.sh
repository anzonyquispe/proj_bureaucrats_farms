#!/usr/bin/env bash
# Submit all five population event-study specifications with period 0 omitted.
# Jobs are independent and may run in parallel.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS=(
  main_pop_omit0.sbatch
  grid_monthyear_pop_omit0.sbatch
  grid_monthyear_pop_nocontrols_omit0.sbatch
  grid_monthyear_pop_gridmonth_cluster_omit0.sbatch
  grid_monthyear_pop_nocontrols_gridmonth_cluster_omit0.sbatch
)

for job in "${JOBS[@]}"; do
  job_id=$(qsub -terse "${SCRIPT_DIR}/${job}")
  echo "submitted ${job}: ${job_id}"
done

echo "Submitted ${#JOBS[@]} omit-period-0 jobs."
echo "Monitor with: qstat -u \$USER"

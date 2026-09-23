#!/usr/bin/env bash
# Submit all ten omit-period-0 alternative-window event studies.
# Jobs are independent and may run in parallel.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/run_alternative_window.sbatch"

JOBS=(
  "ev0_m6_main:m6_p6_main_pop.do"
  "ev0_m6_gmb:m6_p6_grid_monthyear_pop.do"
  "ev0_m6_gmn:m6_p6_grid_monthyear_pop_nocontrols.do"
  "ev0_m6_gmc:m6_p6_grid_monthyear_pop_gridmonth_cluster.do"
  "ev0_m6_gmnc:m6_p6_grid_monthyear_pop_nocontrols_gridmonth_cluster.do"
  "ev0_m5_main:m5_p6_main_pop.do"
  "ev0_m5_gmb:m5_p6_grid_monthyear_pop.do"
  "ev0_m5_gmn:m5_p6_grid_monthyear_pop_nocontrols.do"
  "ev0_m5_gmc:m5_p6_grid_monthyear_pop_gridmonth_cluster.do"
  "ev0_m5_gmnc:m5_p6_grid_monthyear_pop_nocontrols_gridmonth_cluster.do"
)

for specification in "${JOBS[@]}"; do
  job_name="${specification%%:*}"
  dofile="${specification#*:}"
  job_id=$(qsub -terse -N "${job_name}" -v "DOFILE=${dofile}" "${RUNNER}")
  echo "submitted ${job_name}: ${job_id} (${dofile})"
done

echo "Submitted ${#JOBS[@]} alternative-window jobs."
echo "Monitor with: qstat -u \$USER"

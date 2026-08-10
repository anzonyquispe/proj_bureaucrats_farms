#!/usr/bin/env bash
# Submit the eight exploratory DiD jobs in parallel, then render all tables.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/run_did_window.sbatch"
TABLE_RUNNER="${SCRIPT_DIR}/generate_tables_explore.sbatch"
mkdir -p "${SCRIPT_DIR}/../logs"

WINDOWS=(
  "m6_p6:-6:6"
  "m6_p5:-6:5"
  "m5_p5:-5:5"
  "m5_p6:-5:6"
)
TREATMENTS=(area pop)
job_ids=()

for window_spec in "${WINDOWS[@]}"; do
  IFS=: read -r window_label window_min window_max <<< "${window_spec}"
  for treatment in "${TREATMENTS[@]}"; do
    job_name="did_${treatment}_${window_label}"
    job_id=$(qsub -terse -N "${job_name}" \
      -v "WINDOW_MIN=${window_min},WINDOW_MAX=${window_max},WINDOW_LABEL=${window_label},TREATMENT=${treatment}" \
      "${RUNNER}")
    job_ids+=("${job_id}")
    echo "submitted ${job_name}: ${job_id}"
  done
done

hold_ids=$(IFS=,; echo "${job_ids[*]}")
table_job=$(qsub -terse -hold_jid "${hold_ids}" "${TABLE_RUNNER}")

echo "Submitted ${#job_ids[@]} DiD jobs in parallel."
echo "Table job ${table_job} will start after all DiD jobs finish."
echo "Monitor with: qstat -u \$USER"

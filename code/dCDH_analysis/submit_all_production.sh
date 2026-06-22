#!/bin/bash
# Submit all 8 production dCDH sbatch jobs (one per regression).
# Each requests -pe smp 60 (~1.8 TB) and exports VARIANT=notrend or actrend.
#
# Usage:
#   bash submit_all_production.sh
# or after `chmod +x submit_all_production.sh`:
#   ./submit_all_production.sh

set -eu
cd "$(dirname "$0")"

JOBS=(
  dCDH_downup_ac_pop_noreset_notrend
  dCDH_downup_ac_pop_noreset_actrend
  dCDH_downup_ac_pop_reset6_notrend
  dCDH_downup_ac_pop_reset6_actrend
  dCDH_downup_ac_pop_reset12_notrend
  dCDH_downup_ac_pop_reset12_actrend
  dCDH_downup_ac_noreset_notrend
  dCDH_downup_ac_noreset_actrend
  dCDH_downup_ac_reset6_notrend
  dCDH_downup_ac_reset6_actrend
  dCDH_downup_ac_reset12_notrend
  dCDH_downup_ac_reset12_actrend
)

for j in "${JOBS[@]}"; do
  echo "qsub ${j}.sbatch"
  qsub "${j}.sbatch"
done

echo
echo "Submitted ${#JOBS[@]} jobs. Run 'qstat -u \$USER' to monitor."

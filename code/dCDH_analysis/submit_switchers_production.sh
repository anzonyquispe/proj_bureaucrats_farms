#!/bin/bash
# Submit all 24 switchers production dCDH sbatch jobs.
# Each sets both VARIANT (notrend or actrend) and SWITCHERS (in or out),
# covering the full 2 × 2 × 6 matrix of switchers-in / switchers-out variants
# across all driver scripts (noreset, reset6, reset12) for both downup_ac and
# downup_ac_pop.
#
# Usage:
#   bash submit_switchers_production.sh
# or after `chmod +x submit_switchers_production.sh`:
#   ./submit_switchers_production.sh

set -eu
cd "$(dirname "$0")"

JOBS=(
  dCDH_downup_ac_noreset_notrend_in
  dCDH_downup_ac_noreset_notrend_out
  dCDH_downup_ac_noreset_actrend_in
  dCDH_downup_ac_noreset_actrend_out
  dCDH_downup_ac_reset6_notrend_in
  dCDH_downup_ac_reset6_notrend_out
  dCDH_downup_ac_reset6_actrend_in
  dCDH_downup_ac_reset6_actrend_out
  dCDH_downup_ac_reset12_notrend_in
  dCDH_downup_ac_reset12_notrend_out
  dCDH_downup_ac_reset12_actrend_in
  dCDH_downup_ac_reset12_actrend_out
  dCDH_downup_ac_pop_noreset_notrend_in
  dCDH_downup_ac_pop_noreset_notrend_out
  dCDH_downup_ac_pop_noreset_actrend_in
  dCDH_downup_ac_pop_noreset_actrend_out
  dCDH_downup_ac_pop_reset6_notrend_in
  dCDH_downup_ac_pop_reset6_notrend_out
  dCDH_downup_ac_pop_reset6_actrend_in
  dCDH_downup_ac_pop_reset6_actrend_out
  dCDH_downup_ac_pop_reset12_notrend_in
  dCDH_downup_ac_pop_reset12_notrend_out
  dCDH_downup_ac_pop_reset12_actrend_in
  dCDH_downup_ac_pop_reset12_actrend_out
)

for j in "${JOBS[@]}"; do
  echo "qsub ${j}.sbatch"
  qsub "${j}.sbatch"
done

echo
echo "Submitted ${#JOBS[@]} jobs. Run 'qstat -u \$USER' to monitor."

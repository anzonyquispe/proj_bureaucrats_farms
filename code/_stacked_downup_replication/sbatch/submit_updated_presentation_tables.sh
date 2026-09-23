#!/usr/bin/env bash
# Rerun the two main DiD tables and three rice-production presentation tables.
# Usage:
#   bash code/_stacked_downup_replication/sbatch/submit_updated_presentation_tables.sh
# Sample test:
#   SAMPLE=_sample bash code/_stacked_downup_replication/sbatch/submit_updated_presentation_tables.sh

set -euo pipefail

REPLICATION_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
SAMPLE="${SAMPLE:-none}"
RUNNER="${REPLICATION_CODE}/sbatch/run_dofile.sbatch"

if command -v qsub >/dev/null 2>&1; then
  scheduler=sge
elif command -v sbatch >/dev/null 2>&1; then
  scheduler=slurm
else
  echo "ERROR: neither qsub nor sbatch is available." >&2
  exit 69
fi

submit_job() {
  local name="$1" dofile="$2" cpus="$3" suffix="$4" downup="${5:-none}"
  if [[ "${scheduler}" == sge ]]; then
    local -a opts=(-terse -V -N "${name}" -j y -o /dev/null)
    (( cpus > 1 )) && opts+=(-pe smp "${cpus}")
    qsub "${opts[@]}" "${RUNNER}" "${dofile}" \
      "${REPLICATION_ROOT}" "${REPLICATION_CODE}" shell "${SAMPLE}" \
      is_rural 0/3 "${suffix}" "${downup}" none none all all
  else
    sbatch --parsable --job-name="${name}" --cpus-per-task="${cpus}" \
      --output=/dev/null --error=/dev/null "${RUNNER}" "${dofile}" \
      "${REPLICATION_ROOT}" "${REPLICATION_CODE}" shell "${SAMPLE}" \
      is_rural 0/3 "${suffix}" "${downup}" none none all all
  fi
}

echo "Submitting no-FE baseline plus three FE specifications (sample=${SAMPLE})."
submit_job main4_protest3fe _main_4_protest_5km_fe12_did_downup.do 3 _acpop downup_ac_pop
submit_job main5_politician3fe _main_5_polischar_fe12_did_downup_inter.do 1 _acpop downup_ac_pop
submit_job pres10_rice3fe _app_10_did_rice_moderators.do 1 none
submit_job pres13_protest_rice3fe _app_13_protest_5km_fe12_did_ricemods.do 3 none
submit_job pres14_politician_rice3fe _app_14_polischar_fe12_did_ricemods.do 1 none

echo "Submitted five independent jobs."
echo "Logs: ${REPLICATION_CODE}/logs/<job-name>_<job-id>.stata.log"

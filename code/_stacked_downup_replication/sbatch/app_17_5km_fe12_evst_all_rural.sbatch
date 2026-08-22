#!/usr/bin/env bash
# Submit the single canonical pooled-control protest event study. The Stata
# dofile estimates FE1-FE5 for the baseline and rice-production moderator.

#$ -N protest_event
#$ -q largemem
#$ -pe smp 10
#$ -cwd
#$ -j y
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/protest_event.log

set -euo pipefail

REPLICATION_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
SAMPLE="${SAMPLE:-none}"

RUNNER="${REPLICATION_CODE}/sbatch/run_dofile.sbatch"
if [[ ! -f "${RUNNER}" ]]; then
  echo "ERROR: runner not found: ${RUNNER}" >&2
  exit 66
fi

exec /bin/bash "${RUNNER}" \
  "_app_17_5km_fe12_evst_all.do" \
  "${REPLICATION_ROOT}" \
  "${REPLICATION_CODE}" \
  "shell" \
  "${SAMPLE}" \
  "is_rural" \
  "1/5" \
  "none" \
  "none" \
  "stacked_data_protest5km" \
  "none" \
  "all"

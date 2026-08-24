#!/usr/bin/env bash
# Submit the single canonical pooled-control protest event study. It estimates
# the selected FE3 over every relative year naturally present in the input.

#$ -N protest_event_fe03
#$ -q largemem
#$ -pe smp 10
#$ -cwd
#$ -j y
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/protest_event_fe03.log

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
  "3" \
  "none" \
  "none" \
  "stacked_data_protest5km" \
  "none" \
  "all"

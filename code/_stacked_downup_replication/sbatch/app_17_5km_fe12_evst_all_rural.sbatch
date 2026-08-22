#!/usr/bin/env bash
# Submit only the production protest event study. By default this runs the
# population downwind measure and produces never, pooled, and not-yet-control
# results in one Stata job.
#
# Optional qsub overrides:
#   -v DOWNUP_VAR=downup_ac,STER_SUFFIX=none,CONTROL_SAMPLES=never

#$ -N protest_event_pop
#$ -q largemem
#$ -pe smp 10
#$ -cwd
#$ -j y
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/protest_event_pop.log

set -euo pipefail

REPLICATION_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
DOWNUP_VAR="${DOWNUP_VAR:-downup_ac_pop}"
CONTROL_SAMPLES="${CONTROL_SAMPLES:-never both notyet}"
SAMPLE="${SAMPLE:-none}"

if [[ "${DOWNUP_VAR}" == "downup_ac_pop" ]]; then
  STER_SUFFIX="${STER_SUFFIX:-_acpop}"
elif [[ "${DOWNUP_VAR}" == "downup_ac" ]]; then
  STER_SUFFIX="${STER_SUFFIX:-none}"
else
  echo "ERROR: DOWNUP_VAR must be downup_ac_pop or downup_ac." >&2
  exit 64
fi

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
  "1" \
  "${STER_SUFFIX}" \
  "${DOWNUP_VAR}" \
  "stacked_data_protest5km" \
  "none" \
  "${CONTROL_SAMPLES}"

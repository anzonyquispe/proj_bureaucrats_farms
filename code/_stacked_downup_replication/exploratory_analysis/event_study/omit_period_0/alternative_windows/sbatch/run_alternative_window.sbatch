#!/usr/bin/env bash
#$ -N ev0_altwin
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/event_study/omit_period_0/alternative_windows/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/event_study/omit_period_0/alternative_windows/logs

set -euo pipefail

CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
DOFILE="${DOFILE:?Set DOFILE to an alternative-window dofile basename}"

case "${DOFILE}" in
  *[!A-Za-z0-9_.-]*|*..*|/*)
    echo "ERROR: invalid DOFILE basename: ${DOFILE}" >&2
    exit 2
    ;;
esac

TARGET="${CODE}/exploratory_analysis/event_study/omit_period_0/alternative_windows/${DOFILE}"
test -f "${TARGET}"

if ! type module >/dev/null 2>&1; then
  if [[ "${FARMS_LOGIN_RETRY:-0}" == "1" ]]; then
    echo "ERROR: the module command is unavailable even in a login shell." >&2
    exit 127
  fi
  export FARMS_LOGIN_RETRY=1
  exec /bin/bash -l "$0" "$@"
fi

module load stata gcc
cd "${CODE}"
stata-mp -b do "${TARGET}"

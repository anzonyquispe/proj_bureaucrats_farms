#!/usr/bin/env bash
#$ -N rec_main_pop
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
set -euo pipefail
CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
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
stata-mp -b do "${CODE}/_main_1_did.do" \
  combined_dt_pop downup_ac_pop main_did_downup_pop_ac _stacked

#!/usr/bin/env bash
#$ -N ev0_gm_cl
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/event_study/omit_period_0/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/event_study/omit_period_0/logs

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
stata-mp -b do \
  "${CODE}/exploratory_analysis/event_study/omit_period_0/grid_monthyear_pop_gridmonth_cluster_omit0.do"

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
  [[ -r /etc/profile.d/modules.sh ]] && source /etc/profile.d/modules.sh
  [[ -r /usr/share/Modules/init/bash ]] && source /usr/share/Modules/init/bash
fi
module load stata gcc
cd "${CODE}"
stata-mp -b do "${CODE}/_main_1_did.do" \
  combined_dt_pop downup_ac_pop main_did_downup_pop_ac _stacked

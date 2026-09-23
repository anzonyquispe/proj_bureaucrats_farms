#!/usr/bin/env bash
#$ -N rec_did_year
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
set -euo pipefail
DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
exec bash "${CODE}/sbatch/run_dofile.sbatch" _app_8_main_did_by_year.do "${DATA_ROOT}" "${CODE}" shell none is_rural 1/10 none none none none

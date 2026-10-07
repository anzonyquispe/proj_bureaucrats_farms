#!/usr/bin/env bash
#$ -N event_pop_octnov
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
# No #$ -m directive: this site's validator rejects a mail option unless the
# script also carries -M, and a command-line -M does not satisfy it. Request
# mail at submit time instead, with: qsub -m abe -M <address> ...
set -euo pipefail
DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
exec bash "${CODE}/sbatch/run_dofile.sbatch" _main_2_stacked_event_study_5pre_octnov.do "${DATA_ROOT}" "${CODE}" shell none is_rural 1 none none none none

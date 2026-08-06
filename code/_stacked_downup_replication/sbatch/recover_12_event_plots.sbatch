#!/usr/bin/env bash
#$ -N rec_event_plots
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
set -euo pipefail
DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPO_ROOT="${REPOSITORY_ROOT:-/users/aquisper/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-${REPO_ROOT}/code/_stacked_downup_replication}"
exec bash "${CODE}/sbatch/run_r.sbatch" "${DATA_ROOT}" "${CODE}" none "${REPO_ROOT}"

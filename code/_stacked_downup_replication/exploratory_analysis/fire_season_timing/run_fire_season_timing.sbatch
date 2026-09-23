#!/usr/bin/env bash
#$ -N fireseason_es
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -j y
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/fire_season_timing/logs/fire_season_timing.log

set -euo pipefail

DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
SAMPLE_ARG="${SAMPLE_ARG:-none}"
ANALYSIS_SUBSAMPLE="${ANALYSIS_SUBSAMPLE:-all}"
LOG_DIR="${CODE}/exploratory_analysis/fire_season_timing/logs"
mkdir -p "${LOG_DIR}"

exec bash "${CODE}/sbatch/run_dofile.sbatch" \
  exploratory_analysis/fire_season_timing/fire_season_start_event_study.do \
  "${DATA_ROOT}" "${CODE}" shell "${SAMPLE_ARG}" is_rural 1/2 none \
  downup_ac_pop none none all "${ANALYSIS_SUBSAMPLE}"

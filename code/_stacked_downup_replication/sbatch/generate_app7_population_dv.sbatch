#!/usr/bin/env bash
#SBATCH --job-name=app7_pop_dv
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
#$ -N app7_pop_dv
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -j y
#$ -o /dev/null

set -euo pipefail

DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"

exec bash "${CODE}/sbatch/run_dofile.sbatch" \
  _app_7_main_did_downup_area_ac_dv.do \
  "${DATA_ROOT}" "${CODE}" shell none is_rural 1/3 none \
  downup_ac_pop none none all all

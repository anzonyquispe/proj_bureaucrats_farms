#!/usr/bin/env bash
#SBATCH --job-name=ev_gm_area
#SBATCH --cpus-per-task=1
#SBATCH --mem=120G
#SBATCH --time=24:00:00
#SBATCH --output=/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/%x_%j.out
#SBATCH --error=/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/%x_%j.err
#$ -N ev_gm_area
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
stata-mp -b do "${CODE}/_main_2_stacked_event_study_5pre_grid_monthyear_area.do"

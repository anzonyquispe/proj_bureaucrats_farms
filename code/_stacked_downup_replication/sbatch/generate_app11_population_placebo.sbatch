#!/usr/bin/env bash
# Rerun only the corrected 13 km population-placebo regression.
# The placebo treatment is downup_pop_13km (renamed from downup_13kmpl),
# while columns 2 and 3 are split using downup_ac_pop.

#SBATCH --job-name=app11_pop13km
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
#$ -N app11_pop13km
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -j y
#$ -o /dev/null

set -euo pipefail

DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"

exec bash "${CODE}/sbatch/run_dofile.sbatch" \
  _app_11_placebo_pop_13km.do \
  "${DATA_ROOT}" "${CODE}" shell none is_rural 1 none \
  none none none all all

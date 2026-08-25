#!/usr/bin/env bash
# Rerun only the selected politician FE03 event study. The dofile saves both
# the baseline model (evreg1) and its above-median rice-production interaction
# (evreg2) in the same .ster file.

#SBATCH --job-name=pol_fe03_rice_ev
#SBATCH --cpus-per-task=1
#SBATCH --mem=120G
#SBATCH --time=48:00:00
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
#$ -N pol_fe03_rice_ev
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -j y
#$ -o /dev/null

set -euo pipefail

DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"

# Internally this finalized dofile stores the selected FE03 specification as
# local fe1. Therefore FE_LIST must be 1; passing 3 would reference no local
# fe3. The _acpop suffix preserves the canonical production filename.
exec bash "${CODE}/sbatch/run_dofile.sbatch" \
  _app_16_polischar_fe12_evst_all.do \
  "${DATA_ROOT}" "${CODE}" shell none is_rural 1 _acpop \
  downup_ac_pop none none both all

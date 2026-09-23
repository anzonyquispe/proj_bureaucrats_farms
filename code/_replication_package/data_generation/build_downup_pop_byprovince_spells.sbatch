#!/usr/bin/env bash
#$ -N downup_byprov
#$ -q largemem
#$ -pe smp 10
#$ -cwd
#$ -j y
#$ -o /dev/null
set -euo pipefail
REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
CODE="${REPO}/code/_replication_package/data_generation"
mkdir -p "${CODE}/logs/data_generation"
exec > "${CODE}/logs/data_generation/build_downup_pop_byprovince_spells.log" 2>&1
trap 'echo "FAILED at line ${LINENO}"' ERR
source /afs/crc.nd.edu/x86_64_linux/c/conda/24.7.1/etc/profile.d/conda.sh
conda activate "${DOWNUP_ENV_PREFIX:-/groups/sgulzar/india_forest_land/downup_geo}"
echo "Started $(date) host=$(hostname) job=${JOB_ID:-local}"
python "${CODE}/build_downup_pop_byprovince_spells.py" \
    --threads "${NSLOTS:-10}" --memory-limit "${STACK_MEMORY_LIMIT:-90GB}"
echo "Completed $(date)"

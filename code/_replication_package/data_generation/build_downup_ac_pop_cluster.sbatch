#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N build_downup_ac_pop
#$ -pe smp 60
#$ -cwd

set -euo pipefail

ROOT="/users/aquisper/proj_bureaucrats_farms"
CODE_DIR="${ROOT}/code/_replication_package/data_generation"
PYTHON="/groups/sgulzar/india_forest_land/did_stat/bin/python"

cd "${CODE_DIR}"

echo "[$(date '+%F %T')] host=$(hostname) job=${JOB_ID:-NA} pwd=$(pwd)"
if command -v git >/dev/null 2>&1; then
    echo "[$(date '+%F %T')] git HEAD: $(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo 'not-a-git-repo')"
fi

"${PYTHON}" -c "import duckdb"

"${PYTHON}" build_downup_ac_pop_cluster.py \
    --threads "${NSLOTS:-60}" \
    --memory-limit "90GB" \
    --overwrite \
    > build_downup_ac_pop_cluster.out 2>&1

echo "[$(date '+%F %T')] population stage completed"

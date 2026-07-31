#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N build_downup_ac_pop_area
#$ -pe smp 10
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

echo "[$(date '+%F %T')] checking Python dependencies"
"${PYTHON}" -c "import duckdb, geopandas, numpy, pandas, pyarrow, shapely; assert int(shapely.__version__.split('.')[0]) >= 2"

echo "[$(date '+%F %T')] stage 1/2: downwind/upwind population"
"${PYTHON}" build_downup_ac_pop_cluster.py \
    --threads "${NSLOTS:-60}" \
    --memory-limit "90GB" \
    --overwrite \
    > build_downup_ac_pop_cluster.out 2>&1

echo "[$(date '+%F %T')] stage 2/2: exact parallel AC areas"
"${PYTHON}" build_downup_ac_area_cluster.py \
    --workers "${NSLOTS:-60}" \
    --threads "${NSLOTS:-60}" \
    --memory-limit "90GB" \
    --area-chunk-rows 5000 \
    --overwrite \
    > build_downup_ac_area_cluster.out 2>&1

echo "[$(date '+%F %T')] completed both stages"

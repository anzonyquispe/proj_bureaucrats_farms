#!/bin/bash
#$ -q long
#$ -N downup_ac_pop_rice
#$ -pe smp 8
#$ -cwd
#$ -j y
#$ -o downup_ac_pop_rice.log

set -euo pipefail

WORK_DIR="${HOME}/downup_pop_rice_work"
INTERMEDIATE="/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate"
CONDA_SH="/afs/crc.nd.edu/x86_64_linux/c/conda/24.7.1/etc/profile.d/conda.sh"
CONDA_ENV="/groups/sgulzar/india_forest_land/downup_geo"

source "${CONDA_SH}"
conda activate "${CONDA_ENV}"
export PYTHONUNBUFFERED=1

cd "${WORK_DIR}"
echo "[$(date '+%F %T')] host=$(hostname) job=${JOB_ID:-NA} slots=${NSLOTS:-NA}"
echo "[$(date '+%F %T')] python=$(command -v python)"

python tests/test_downup_pop_rice.py -v

echo "[$(date '+%F %T')] AC-month population downwind of rice zones"
python build_downup_ac_pop_rice.py \
    --panel "${INTERMEDIATE}/data_2012_2024_grid_ac_downup_pop.parquet" \
    --grid-population "${INTERMEDIATE}/small_grid_population_2010.parquet" \
    --grid-rice "${INTERMEDIATE}/small_grid_rice_2010.parquet" \
    --rice-percentile 0.5 \
    --rice-sample-percentile 0.5 \
    --output "${INTERMEDIATE}/data_2012_2024_ac_downup_pop_rice.parquet" \
    --output-dta "${INTERMEDIATE}/data_2012_2024_ac_downup_pop_rice.dta" \
    --database "${WORK_DIR}/downup_ac_pop_rice.duckdb" \
    --temp-directory "${WORK_DIR}/downup_ac_pop_rice_duckdb_tmp" \
    --threads "${NSLOTS:-8}" \
    --memory-limit 32GB \
    --overwrite

echo "[$(date '+%F %T')] completed"

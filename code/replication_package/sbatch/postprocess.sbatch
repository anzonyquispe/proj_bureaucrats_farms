#!/usr/bin/env bash
#SBATCH --job-name=farms-post
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=08:00:00
#SBATCH --output=logs/postprocess_%j.out
#SBATCH --error=logs/postprocess_%j.err

set -euo pipefail

REPLICATION_CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/replication_package}"
REPLICATION_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
STATA_BIN="${STATA_BIN:-stata-mp}"
RSCRIPT_BIN="${RSCRIPT_BIN:-Rscript}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
LOCATION="${LOCATION:-shell}"
SAMPLE="${SAMPLE:-none}"
RURAL_VAR="${RURAL_VAR:-is_rural_area}"
PY_SAMPLE="${SAMPLE/none/}"

cd "${REPLICATION_CODE}"
"${STATA_BIN}" -b do sbatch/postprocess.do "${LOCATION}" "${SAMPLE}" "${RURAL_VAR}" \
  "${REPLICATION_ROOT}" "${REPLICATION_CODE}"
"${RSCRIPT_BIN}" plot_event_studies.R --root "${REPLICATION_ROOT}"
"${PYTHON_BIN}" python/generate_descriptive_figures.py \
  --root "${REPLICATION_ROOT}" --sample "${PY_SAMPLE}" --rural-var "${RURAL_VAR}"
"${PYTHON_BIN}" python/generate_design_maps.py \
  --root "${REPLICATION_ROOT}" --sample "${PY_SAMPLE}"
"${PYTHON_BIN}" python/generate_protest_figures.py --root "${REPLICATION_ROOT}"

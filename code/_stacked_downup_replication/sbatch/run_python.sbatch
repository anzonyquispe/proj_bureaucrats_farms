#!/usr/bin/env bash
#SBATCH --job-name=farms_python
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --time=08:00:00
#SBATCH --output=/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/%x_%j.out
#SBATCH --error=/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/%x_%j.err
#$ -N farms_python
#$ -q largemem
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs

set -euo pipefail

SCRIPT="${1:?Python script argument is required}"
REPLICATION_ROOT="${2:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_CODE="${3:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
SAMPLE="${4:-none}"
RURAL_VAR="${5:-is_rural_area}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
if [[ "${SAMPLE}" == "none" ]]; then SAMPLE=""; fi

module purge 2>/dev/null || true
module load python 2>/dev/null || true
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export BLIS_NUM_THREADS=1

case "${SCRIPT}" in
  generate_descriptive_figures.py)
    "${PYTHON_BIN}" "${REPLICATION_CODE}/python/${SCRIPT}" \
      --root "${REPLICATION_ROOT}" --sample "${SAMPLE}" --rural-var "${RURAL_VAR}"
    ;;
  generate_design_maps.py)
    "${PYTHON_BIN}" "${REPLICATION_CODE}/python/${SCRIPT}" \
      --root "${REPLICATION_ROOT}" --sample "${SAMPLE}"
    ;;
  generate_protest_figures.py)
    "${PYTHON_BIN}" "${REPLICATION_CODE}/python/${SCRIPT}" \
      --root "${REPLICATION_ROOT}"
    ;;
  audit_main_outputs.py)
    "${PYTHON_BIN}" "${REPLICATION_CODE}/python/${SCRIPT}" \
      --tex "/users/aquisper/proj_bureaucrats_farms/code/_report/main.tex" \
      --package "${REPLICATION_CODE}" --root "${REPLICATION_ROOT}" \
      --check-files --strict
    ;;
  *)
    echo "Unsupported Python job: ${SCRIPT}" >&2
    exit 64
    ;;
esac

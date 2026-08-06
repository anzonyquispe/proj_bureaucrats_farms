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
RURAL_VAR="${5:-is_rural}"
REPOSITORY_ROOT="${6:-$(cd "${REPLICATION_CODE}/../.." && pwd)}"
PYTHON_ENV="${PYTHON_ENV:-/groups/sgulzar/india_forest_land/downup_geo}"
PYTHON_BIN="${PYTHON_BIN:-${PYTHON_ENV}/bin/python}"
if [[ "${SAMPLE}" == "none" ]]; then SAMPLE=""; fi

module purge 2>/dev/null || true
if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "Python executable is missing or not executable: ${PYTHON_BIN}" >&2
  echo "Expected conda environment: ${PYTHON_ENV}" >&2
  exit 69
fi

# Use the requested geospatial conda environment for Python and any helper
# executables it launches.  Do not load the cluster Python module on top of it.
export PATH="${PYTHON_ENV}/bin:${PATH}"
if [[ -d "${PYTHON_ENV}/share/proj" ]]; then
  export PROJ_DATA="${PYTHON_ENV}/share/proj"
fi
if [[ -d "${PYTHON_ENV}/share/gdal" ]]; then
  export GDAL_DATA="${PYTHON_ENV}/share/gdal"
fi
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export BLIS_NUM_THREADS=1

echo "Python environment: ${PYTHON_ENV}"
"${PYTHON_BIN}" -c 'import sys; print("Python executable:", sys.executable); print("Python version:", sys.version.split()[0])'

case "${SCRIPT}" in
  generate_descriptive_figures.py)
    "${PYTHON_BIN}" "${REPLICATION_CODE}/python/${SCRIPT}" \
      --root "${REPLICATION_ROOT}" --output-root "${REPOSITORY_ROOT}" \
      --sample "${SAMPLE}" --rural-var "${RURAL_VAR}"
    ;;
  generate_design_maps.py)
    "${PYTHON_BIN}" "${REPLICATION_CODE}/python/${SCRIPT}" \
      --root "${REPLICATION_ROOT}" --output-root "${REPOSITORY_ROOT}" \
      --sample "${SAMPLE}"
    ;;
  generate_protest_figures.py)
    "${PYTHON_BIN}" "${REPLICATION_CODE}/python/${SCRIPT}" \
      --root "${REPLICATION_ROOT}" --output-root "${REPOSITORY_ROOT}"
    ;;
  audit_main_outputs.py)
    "${PYTHON_BIN}" "${REPLICATION_CODE}/python/${SCRIPT}" \
      --tex "/users/aquisper/proj_bureaucrats_farms/code/_report/main.tex" \
      --package "${REPLICATION_CODE}" --root "${REPLICATION_ROOT}" \
      --output-root "${REPOSITORY_ROOT}" \
      --check-files --strict
    ;;
  *)
    echo "Unsupported Python job: ${SCRIPT}" >&2
    exit 64
    ;;
esac

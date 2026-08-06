#!/usr/bin/env bash
#SBATCH --job-name=farms_event_plots
#SBATCH --cpus-per-task=1
#SBATCH --mem=24G
#SBATCH --time=08:00:00
#SBATCH --output=/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/%x_%j.out
#SBATCH --error=/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/%x_%j.err
#$ -N farms_event_plots
#$ -q largemem
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs

set -euo pipefail

REPLICATION_ROOT="${1:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_CODE="${2:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
SAMPLE="${3:-none}"
REPOSITORY_ROOT="${4:-$(cd "${REPLICATION_CODE}/../.." && pwd)}"
RSCRIPT_BIN="${RSCRIPT_BIN:-Rscript}"
if [[ "${SAMPLE}" == "none" ]]; then SAMPLE=""; fi

module purge 2>/dev/null || true
module load R
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export BLIS_NUM_THREADS=1

"${RSCRIPT_BIN}" "${REPLICATION_CODE}/plotting_event_studies.R" \
  --root "${REPLICATION_ROOT}" --output-root "${REPOSITORY_ROOT}" \
  --sample "${SAMPLE}"

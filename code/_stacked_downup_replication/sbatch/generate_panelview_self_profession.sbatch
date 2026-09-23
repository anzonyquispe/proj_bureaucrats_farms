#!/usr/bin/env bash
# Regenerate the AC-level politician panel view from the election panel.

#SBATCH --job-name=panelview_selfprof
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
#$ -N panelview_selfprof
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -j y
#$ -o /dev/null

set -euo pipefail

DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-${REPO}/code/_stacked_downup_replication}"
RSCRIPT_BIN="${RSCRIPT_BIN:-Rscript}"
LOG_DIR="${CODE}/logs"
LOG_FILE="${LOG_DIR}/panelview_self_profession.log"

mkdir -p "${LOG_DIR}" "${REPO}/figures"
exec > >(tee "${LOG_FILE}") 2>&1

echo "[$(date '+%F %T')] Regenerating panelview_self_profession.png"
echo "Input: ${DATA_ROOT}/data_output/intermediate/panel_data_election_year.dta"
echo "Sampling: 10% of ACs independently within province; seed=20260826"

if command -v module >/dev/null 2>&1; then
  module load R/4.4.0/gcc/11.5.0
fi
if ! command -v "${RSCRIPT_BIN}" >/dev/null 2>&1; then
  echo "ERROR: Rscript is unavailable: ${RSCRIPT_BIN}" >&2
  exit 69
fi

"${RSCRIPT_BIN}" "${CODE}/generate_panelview_self_profession.R" \
  "${DATA_ROOT}" "${REPO}"

test -s "${REPO}/figures/panelview_self_profession.png"
test -s "${REPO}/tables/panelview_self_profession_selected_acs.csv"
echo "[$(date '+%F %T')] Completed: ${REPO}/figures/panelview_self_profession.png"

#!/usr/bin/env bash
#SBATCH --job-name=farms_do
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --output=/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/%x_%j.out
#SBATCH --error=/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/%x_%j.err
#$ -N farms_do
#$ -q largemem
#$ -pe smp 4
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs

set -euo pipefail

DOFILE="${1:?dofile argument is required}"
REPLICATION_ROOT="${2:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_CODE="${3:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
LOCATION="${4:-shell}"
SAMPLE="${5:-none}"
RURAL_VAR="${6:-is_rural_area}"
FE_LIST="${7:-1}"
STER_SUFFIX="${8:-none}"
DOWNUP_VAR="${9:-none}"
STACKED_FILE="${10:-none}"
DID_OUTPUT="${11:-none}"
STATA_BIN="${STATA_BIN:-stata-mp}"

mkdir -p "${REPLICATION_CODE}/logs"
cd "${REPLICATION_CODE}"

module purge 2>/dev/null || true
module load stata gcc

"${STATA_BIN}" -b do "${REPLICATION_CODE}/sbatch/_run_dofile.do" \
  "${DOFILE}" "${REPLICATION_ROOT}" "${REPLICATION_CODE}" "${LOCATION}" \
  "${SAMPLE}" "${RURAL_VAR}" "${FE_LIST}" "${STER_SUFFIX}" \
  "${DOWNUP_VAR}" "${STACKED_FILE}" "${DID_OUTPUT}"


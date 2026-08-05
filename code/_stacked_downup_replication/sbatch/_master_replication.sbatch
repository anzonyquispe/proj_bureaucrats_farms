#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N stacked_replication
#$ -pe smp 4
#$ -cwd

set -euo pipefail

module purge 2>/dev/null || true
module load stata gcc

REPLICATION_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
LOCATION="${LOCATION:-shell}"
SAMPLE="${SAMPLE:-none}"
IS_RURAL_VAR="${IS_RURAL_VAR:-is_rural_area}"
FE_LIST="${FE_LIST:-1/4}"
STER_SUFFIX="${STER_SUFFIX:-none}"

stata-mp -b do "${REPLICATION_CODE}/sbatch/_run_master.do" \
  "${REPLICATION_ROOT}" "${REPLICATION_CODE}" "${LOCATION}" "${SAMPLE}" \
  "${IS_RURAL_VAR}" "${FE_LIST}" "${STER_SUFFIX}"

module unload stata 2>/dev/null || true
module load R

R_SAMPLE="${SAMPLE}"
if [[ "${R_SAMPLE}" == "none" ]]; then
  R_SAMPLE=""
fi

Rscript "${REPLICATION_CODE}/plotting_event_studies.R" \
  --root "${REPLICATION_ROOT}" --sample "${R_SAMPLE}"

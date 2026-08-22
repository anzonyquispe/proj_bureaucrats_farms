#!/usr/bin/env bash
# Backward-compatible entry point. The production specification now submits
# one pooled-control protest job; it no longer creates six control/treatment
# variants.

set -euo pipefail

REPLICATION_CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
JOB="${REPLICATION_CODE}/sbatch/app_17_5km_fe12_evst_all_rural.sbatch"

if [[ ! -f "${JOB}" ]]; then
  echo "ERROR: job file not found: ${JOB}" >&2
  exit 66
fi

if command -v qsub >/dev/null 2>&1; then
  scheduler="sge"
elif command -v sbatch >/dev/null 2>&1; then
  scheduler="slurm"
else
  echo "ERROR: neither qsub nor sbatch is available." >&2
  exit 69
fi

if [[ "${scheduler}" == "sge" ]]; then
  qsub -V "${JOB}"
else
  sbatch "${JOB}"
fi

echo "Submitted the canonical pooled-control app-17 job."

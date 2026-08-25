#!/usr/bin/env bash
# Rerun only the two full/rice_high estimates that failed in job set 1383845-68.

set -euo pipefail

ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
RUNNER="${CODE}/sbatch/run_dofile.sbatch"

submit_sge() {
  local name="$1"
  shift
  qsub -terse -V -N "${name}" -j y -o /dev/null "${RUNNER}" "$@"
}

submit_slurm() {
  local name="$1"
  shift
  sbatch --parsable --job-name="${name}" --cpus-per-task=1 \
    --output=/dev/null --error=/dev/null "${RUNNER}" "$@"
}

common=("${ROOT}" "${CODE}" shell none is_rural)

if command -v qsub >/dev/null 2>&1; then
  bureau_id=$(submit_sge full_rice_bureau_repair \
    _main_3_bureau_polisc_did.do "${common[@]}" 1/4 _rice_high \
    none none none all rice_high)
  neighbour_id=$(submit_sge full_rice_neighbour_repair \
    _main_6_neighbour.do "${common[@]}" 1 _rice_high \
    none none none all rice_high)
elif command -v sbatch >/dev/null 2>&1; then
  bureau_id=$(submit_slurm full_rice_bureau_repair \
    _main_3_bureau_polisc_did.do "${common[@]}" 1/4 _rice_high \
    none none none all rice_high)
  neighbour_id=$(submit_slurm full_rice_neighbour_repair \
    _main_6_neighbour.do "${common[@]}" 1 _rice_high \
    none none none all rice_high)
else
  echo "ERROR: neither qsub nor sbatch is available." >&2
  exit 69
fi

echo "Submitted bureaucrat-politician repair: ${bureau_id}"
echo "Submitted neighbour repair: ${neighbour_id}"
echo "Logs will be written under ${CODE}/logs with the repair job names."

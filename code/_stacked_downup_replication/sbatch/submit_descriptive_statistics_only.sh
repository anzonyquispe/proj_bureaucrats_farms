#!/usr/bin/env bash
# Submit only the three production stacked-data descriptive-statistics jobs.
# Each dofile re-estimates its richest model, retains e(sample), and writes its
# full-sample LaTeX descriptive table. No .ster input is required.

set -euo pipefail

REPLICATION_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
RUNNER="${REPLICATION_CODE}/sbatch/run_dofile.sbatch"

if command -v qsub >/dev/null 2>&1; then
  SCHEDULER="sge"
elif command -v sbatch >/dev/null 2>&1; then
  SCHEDULER="slurm"
else
  echo "ERROR: neither qsub nor sbatch is available." >&2
  exit 69
fi

submit_one() {
  local job_name="$1"
  local dofile="$2"
  local cpus="$3"
  local stacked_file="$4"
  local job_id

  if [[ "${SCHEDULER}" == "sge" ]]; then
    local -a options=(-terse -V -N "${job_name}" -j y -o /dev/null)
    if (( cpus > 1 )); then
      options+=(-pe smp "${cpus}")
    fi
    job_id=$(qsub "${options[@]}" "${RUNNER}" \
      "${dofile}" "${REPLICATION_ROOT}" "${REPLICATION_CODE}" \
      shell none is_rural 1 none none "${stacked_file}" none all all)
  else
    job_id=$(sbatch --parsable --job-name="${job_name}" \
      --cpus-per-task="${cpus}" --output=/dev/null --error=/dev/null \
      "${RUNNER}" \
      "${dofile}" "${REPLICATION_ROOT}" "${REPLICATION_CODE}" \
      shell none is_rural 1 none none "${stacked_file}" none all all)
    job_id="${job_id%%;*}"
  fi

  printf '%-28s job=%s cpus=%s dofile=%s\n' \
    "${job_name}" "${job_id}" "${cpus}" "${dofile}"
}

echo "Submitting full-sample descriptive statistics with ${SCHEDULER}."
echo "Permanent logs: ${REPLICATION_CODE}/logs/<job-name>_<job-id>.stata.log"

submit_one descriptives_main app_main_descriptive.do 1 none
submit_one descriptives_politician app_polischar_descriptive.do 1 none
submit_one descriptives_protest app_5km_descriptive.do 3 stacked_data_protest5km

echo "Submitted all three descriptive-statistics jobs."

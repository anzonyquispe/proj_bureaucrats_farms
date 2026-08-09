#!/usr/bin/env bash
# Submit the six missing protest event-study jobs independently:
# area/population moderators x never/both/not-yet-treated controls.

set -euo pipefail

REPLICATION_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
RUNNER="${REPLICATION_CODE}/sbatch/run_dofile.sbatch"

if [[ ! -f "${RUNNER}" ]]; then
  echo "ERROR: runner not found: ${RUNNER}" >&2
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

submit_one() {
  local treatment_family="$1"
  local control_sample="$2"
  local suffix downup job_name

  if [[ "${treatment_family}" == "area" ]]; then
    suffix="none"
    downup="downup_ac"
  else
    suffix="_acpop"
    downup="downup_ac_pop"
  fi
  job_name="pr_ev_${treatment_family}_${control_sample}"

  local -a args=(
    "_app_17_5km_fe12_evst_all.do"
    "${REPLICATION_ROOT}"
    "${REPLICATION_CODE}"
    "shell"
    "none"
    "is_rural"
    "1"
    "${suffix}"
    "${downup}"
    "stacked_data_protest5km"
    "none"
    "${control_sample}"
  )

  if [[ "${scheduler}" == "sge" ]]; then
    qsub -V -N "${job_name}" -pe smp 10 "${RUNNER}" "${args[@]}"
  else
    sbatch --job-name="${job_name}" --cpus-per-task=10 \
      "${RUNNER}" "${args[@]}"
  fi
}

for treatment_family in area pop; do
  for control_sample in never both notyet; do
    submit_one "${treatment_family}" "${control_sample}"
  done
done

echo "Submitted all six app-17 control-sample jobs."

#!/usr/bin/env bash
# Submit only the two estimations corrected to absorb cohort-specific fixed
# effects: treatment definitions (_app_6) and the 13 km placebo (_app_11).

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
  local fe_list="$3"
  local job_id

  if [[ "${SCHEDULER}" == "sge" ]]; then
    job_id=$(qsub -terse -V -N "${job_name}" -j y -o /dev/null \
      "${RUNNER}" \
      "${dofile}" "${REPLICATION_ROOT}" "${REPLICATION_CODE}" \
      shell none is_rural "${fe_list}" none none none none all all)
  else
    job_id=$(sbatch --parsable --job-name="${job_name}" \
      --cpus-per-task=1 --output=/dev/null --error=/dev/null \
      "${RUNNER}" \
      "${dofile}" "${REPLICATION_ROOT}" "${REPLICATION_CODE}" \
      shell none is_rural "${fe_list}" none none none none all all)
    job_id="${job_id%%;*}"
  fi

  printf '%-28s job=%s dofile=%s\n' "${job_name}" "${job_id}" "${dofile}"
}

echo "Submitting corrected cohort-FE estimations with ${SCHEDULER}."
echo "Permanent logs: ${REPLICATION_CODE}/logs/<job-name>_<job-id>.stata.log"

submit_one treatment_defs_cohortfe _app_6_main_did_treat_definition.do 1/7
submit_one placebo_13km_cohortfe _app_11_placebo_pop_13km.do 1

echo "Submitted both corrected jobs."

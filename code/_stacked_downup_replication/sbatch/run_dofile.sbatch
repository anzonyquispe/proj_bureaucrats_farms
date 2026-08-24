#!/usr/bin/env bash
#SBATCH --job-name=farms_do
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --output=/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/%x_%j.out
#SBATCH --error=/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/%x_%j.err
#$ -N farms_do
#$ -q largemem
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs

set -euo pipefail

DOFILE="${1:?dofile argument is required}"
REPLICATION_ROOT="${2:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_CODE="${3:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
LOCATION="${4:-shell}"
SAMPLE="${5:-none}"
RURAL_VAR="${6:-is_rural}"
FE_LIST="${7:-1}"
STER_SUFFIX="${8:-none}"
DOWNUP_VAR="${9:-none}"
STACKED_FILE="${10:-none}"
DID_OUTPUT="${11:-none}"
CONTROL_SAMPLES="${12:-all}"
ANALYSIS_SUBSAMPLE="${13:-all}"
STATA_BIN="${STATA_BIN:-stata-mp}"
ALLOCATED_CPUS="${SLURM_CPUS_PER_TASK:-${NSLOTS:-1}}"

if ! [[ "${ALLOCATED_CPUS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid scheduler CPU allocation: ${ALLOCATED_CPUS}" >&2
  exit 64
fi

mkdir -p "${REPLICATION_CODE}/logs"

# Pass parameters through the environment.  Supplying them after `stata -b do`
# makes Stata concatenate every argument into its automatic .log filename.
export FARMS_DOFILE="${DOFILE}"
export FARMS_ROOT="${REPLICATION_ROOT}"
export FARMS_CODE="${REPLICATION_CODE}"
export FARMS_LOCATION="${LOCATION}"
export FARMS_SAMPLE="${SAMPLE}"
export FARMS_RURAL_VAR="${RURAL_VAR}"
export FARMS_FE_LIST="${FE_LIST}"
export FARMS_STER_SUFFIX="${STER_SUFFIX}"
export FARMS_DOWNUP_VAR="${DOWNUP_VAR}"
export FARMS_STACKED_FILE="${STACKED_FILE}"
export FARMS_DID_OUTPUT="${DID_OUTPUT}"
export FARMS_CONTROL_SAMPLES="${CONTROL_SAMPLES}"
export FARMS_ANALYSIS_SUBSAMPLE="${ANALYSIS_SUBSAMPLE}"
export FARMS_CPUS="${ALLOCATED_CPUS}"

SCHEDULER_JOB_NAME="${SLURM_JOB_NAME:-${JOB_NAME:-farms_do}}"
SCHEDULER_JOB_ID="${SLURM_JOB_ID:-${JOB_ID:-$$}}"
STATA_WORK_DIR="${REPLICATION_CODE}/logs/stata_work/${SCHEDULER_JOB_NAME}_${SCHEDULER_JOB_ID}"
STATA_SAVED_LOG="${REPLICATION_CODE}/logs/${SCHEDULER_JOB_NAME}_${SCHEDULER_JOB_ID}.stata.log"
STATA_AUTOMATIC_LOG="${STATA_WORK_DIR}/_run_dofile.log"
mkdir -p "${STATA_WORK_DIR}"
cd "${STATA_WORK_DIR}"

preserve_stata_log() {
  if [[ -f "${STATA_AUTOMATIC_LOG}" ]]; then
    cp "${STATA_AUTOMATIC_LOG}" "${STATA_SAVED_LOG}" || true
  fi
}
trap preserve_stata_log EXIT
trap 'preserve_stata_log; exit 143' TERM
trap 'preserve_stata_log; exit 130' INT
trap 'preserve_stata_log; exit 129' HUP

if ! type module >/dev/null 2>&1; then
  if [[ "${FARMS_LOGIN_RETRY:-0}" == "1" ]]; then
    echo "ERROR: the module command is unavailable even in a login shell." >&2
    exit 127
  fi
  export FARMS_LOGIN_RETRY=1
  exec /bin/bash -l "$0" "$@"
fi
module purge 2>/dev/null || true
module load stata gcc

# Match Stata and linked numerical libraries to the scheduler allocation.
# Protest-stack jobs receive 10; every other job receives 1.
export OMP_NUM_THREADS="${ALLOCATED_CPUS}"
export OPENBLAS_NUM_THREADS="${ALLOCATED_CPUS}"
export MKL_NUM_THREADS="${ALLOCATED_CPUS}"
export NUMEXPR_NUM_THREADS="${ALLOCATED_CPUS}"
export VECLIB_MAXIMUM_THREADS="${ALLOCATED_CPUS}"
export BLIS_NUM_THREADS="${ALLOCATED_CPUS}"

echo "Starting ${DOFILE} with ${ALLOCATED_CPUS} CPU(s)."
echo "Permanent Stata log: ${STATA_SAVED_LOG}"

set +e
"${STATA_BIN}" -b do "${REPLICATION_CODE}/sbatch/_run_dofile.do"
stata_status=$?
set -e

# Stata batch output normally goes to this automatic log instead of stdout.
# Preserve it under a scheduler-specific name and mirror it into .out/.o so
# either logging location can be inspected.
if [[ -f "${STATA_AUTOMATIC_LOG}" ]]; then
  preserve_stata_log
  cat "${STATA_AUTOMATIC_LOG}"
  # Stata/MP can return shell status 0 even when a nested dofile terminates with
  # r(#). Treat an uncaught Stata return code in the batch log as job failure so
  # dependent jobs are not released after an incomplete estimate.
  if grep -Eq '^r\([1-9][0-9]*\);[[:space:]]*$' "${STATA_AUTOMATIC_LOG}"; then
    echo "ERROR: uncaught Stata return code detected in the batch log." >&2
    stata_status=1
  fi
  # The permanent copy above and scheduler output contain the diagnostics.
  # Remove the per-job working copy so logs/stata_work does not accumulate a
  # third duplicate of every Stata log.
  rm -f -- "${STATA_AUTOMATIC_LOG}"
  rmdir -- "${STATA_WORK_DIR}" 2>/dev/null || true
else
  echo "ERROR: Stata did not create ${STATA_AUTOMATIC_LOG}." >&2
  exit 66
fi

echo "Stata exit status: ${stata_status}"
exit "${stata_status}"

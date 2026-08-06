#!/usr/bin/env bash
#SBATCH --job-name=recover_farms_outputs
#SBATCH --cpus-per-task=10
#SBATCH --mem=150G
#SBATCH --time=4-00:00:00
#SBATCH --output=/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/%x_%j.out
#SBATCH --error=/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs/%x_%j.err
#$ -N recover_farms_outputs
#$ -q largemem
#$ -pe smp 10
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs

set -euo pipefail

DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPO_ROOT="${REPOSITORY_ROOT:-/users/aquisper/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-${REPO_ROOT}/code/_stacked_downup_replication}"
OLD_TABLES="${OLD_TABLES:-${DATA_ROOT}/tex/paper/tables}"
OLD_FIGURES="${OLD_FIGURES:-${DATA_ROOT}/tex/paper/figures}"
TABLES="${REPO_ROOT}/tables"
FIGURES="${REPO_ROOT}/figures"
RUN_DOF="${CODE}/sbatch/run_dofile.sbatch"
RUN_R="${CODE}/sbatch/run_r.sbatch"

for required in "${REPO_ROOT}" "${CODE}" "${RUN_DOF}" "${RUN_R}"; do
  if [[ ! -e "${required}" ]]; then
    echo "Required path is missing: ${required}" >&2
    exit 66
  fi
done

mkdir -p "${TABLES}" "${FIGURES}" "${CODE}/logs"

copy_previous_outputs() {
  if [[ -d "${OLD_TABLES}" ]]; then
    cp -R "${OLD_TABLES}/." "${TABLES}/"
  else
    echo "WARNING: previous tables folder is absent: ${OLD_TABLES}" >&2
  fi
  if [[ -d "${OLD_FIGURES}" ]]; then
    cp -R "${OLD_FIGURES}/." "${FIGURES}/"
  else
    echo "WARNING: previous figures folder is absent: ${OLD_FIGURES}" >&2
  fi
  chmod -R u+rwX "${TABLES}" "${FIGURES}"
  echo "Copied previous outputs into ${TABLES} and ${FIGURES}."
}

run_stata() {
  local label="$1" dofile="$2" fe_list="$3" suffix="$4"
  local downup="${5:-none}" stacked="${6:-none}" output="${7:-none}"
  echo "[$(date '+%F %T')] Stata stage ${label}: ${dofile}"
  SLURM_JOB_NAME="recover_${label}" JOB_NAME="recover_${label}" \
    bash "${RUN_DOF}" \
      "${dofile}" "${DATA_ROOT}" "${CODE}" shell none is_rural \
      "${fe_list}" "${suffix}" "${downup}" "${stacked}" "${output}"
}

copy_previous_outputs

# These seven jobs completed estimation but failed when replacing their old
# shared-storage .ster outputs. They now write to the repository tables folder.
run_stata main_did_area _main_1_did.do 1/4 _stacked \
  downup_ac combined_dt main_did_downup_area_ac
run_stata main_did_pop _main_1_did.do 1/4 _stacked \
  downup_ac_pop combined_dt_pop main_did_downup_pop_ac
run_stata bureau_polisc _main_3_bureau_polisc_did.do 1/5 none
run_stata treatment_defs _app_6_main_did_treat_definition.do 1/7 none
run_stata alternative_dv _app_7_main_did_downup_area_ac_dv.do 1/3 none
run_stata did_by_year _app_8_main_did_by_year.do 1/10 none
run_stata did_by_state _app_9_main_did_by_state.do 1/4 none

# Re-estimate the two changed event studies over relative months -6 through 5.
run_stata event_main_area _main_2_stacked_event_study_5pre_area.do 1 none
run_stata event_main_pop _main_2_stacked_event_study_5pre.do 1 none

# Recover every event-study CSV from the copied/new .ster files, then rebuild
# the LaTeX tables and event-study figures in the repository output folders.
run_stata export_event_csv _export_event_study_csv.do 1 none
run_stata generate_tables _generate_all_tables.do 1 none

echo "[$(date '+%F %T')] R stage: event-study figures"
bash "${RUN_R}" "${DATA_ROOT}" "${CODE}" none "${REPO_ROOT}"

echo "[$(date '+%F %T')] Recovery pipeline completed."
echo "Tables: ${TABLES}"
echo "Figures: ${FIGURES}"
echo "Review the outputs, then add/commit them from ${REPO_ROOT}."

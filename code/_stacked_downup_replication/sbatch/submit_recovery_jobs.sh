#!/usr/bin/env bash
# Run this launcher directly on the cluster login node with `bash`.
# It submits separate qsub jobs; do not submit this file with qsub.
set -euo pipefail

DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPO_ROOT="${REPOSITORY_ROOT:-/users/aquisper/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-${REPO_ROOT}/code/_stacked_downup_replication}"
SBATCH_DIR="${CODE}/sbatch"
OLD_TABLES="${OLD_TABLES:-${DATA_ROOT}/tex/paper/tables}"
OLD_FIGURES="${OLD_FIGURES:-${DATA_ROOT}/tex/paper/figures}"

if ! command -v qsub >/dev/null 2>&1; then
  echo "qsub is unavailable. Run this script directly on a cluster login node." >&2
  exit 69
fi

mkdir -p "${REPO_ROOT}/tables" "${REPO_ROOT}/figures" "${CODE}/logs"
if [[ -d "${OLD_TABLES}" ]]; then cp -R "${OLD_TABLES}/." "${REPO_ROOT}/tables/"; fi
if [[ -d "${OLD_FIGURES}" ]]; then cp -R "${OLD_FIGURES}/." "${REPO_ROOT}/figures/"; fi
chmod -R u+rwX "${REPO_ROOT}/tables" "${REPO_ROOT}/figures"

submit() {
  local script="$1"
  local id
  id=$(qsub -terse -V "${SBATCH_DIR}/${script}")
  echo "Submitted ${script}: ${id}" >&2
  printf '%s' "${id}"
}

submit_after() {
  local dependency="$1" script="$2"
  local id
  id=$(qsub -terse -V -hold_jid "${dependency}" "${SBATCH_DIR}/${script}")
  echo "Submitted ${script} after ${dependency}: ${id}" >&2
  printf '%s' "${id}"
}

# These nine jobs are independent. They are all submitted without holds.
table_1=$(submit recover_01_main_did_area.sbatch)
table_2=$(submit recover_02_main_did_pop.sbatch)
table_3=$(submit recover_03_bureau_polisc.sbatch)
table_4=$(submit recover_04_treatment_definitions.sbatch)
table_5=$(submit recover_05_alternative_dv.sbatch)
table_6=$(submit recover_06_did_by_year.sbatch)
table_7=$(submit recover_07_did_by_state.sbatch)
event_1=$(submit recover_08_event_main_area.sbatch)
event_2=$(submit recover_09_event_main_pop.sbatch)

table_dependency="${table_1},${table_2},${table_3},${table_4},${table_5},${table_6},${table_7}"
event_dependency="${event_1},${event_2}"

# Post-processing waits only for the files it consumes.
table_job=$(submit_after "${table_dependency}" recover_10_generate_tables.sbatch)
event_csv_job=$(submit_after "${event_dependency}" recover_11_export_event_csv.sbatch)
event_plot_job=$(submit_after "${event_csv_job}" recover_12_event_plots.sbatch)

echo
echo "Nine independent estimation jobs were submitted in parallel."
echo "Table job (held): ${table_job}"
echo "Event CSV job (held): ${event_csv_job}"
echo "Event plot job (held): ${event_plot_job}"
echo "Inspect them with: qstat -u ${USER:-your_username}"

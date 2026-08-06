#!/usr/bin/env bash
# Parallel recovery launcher. Run this file with `bash`, not qsub/sbatch: it
# submits each independent Stata estimation as a separate scheduler job.

set -euo pipefail

DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPO_ROOT="${REPOSITORY_ROOT:-/users/aquisper/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-${REPO_ROOT}/code/_stacked_downup_replication}"
LOCATION="${LOCATION:-shell}"
SAMPLE="${SAMPLE:-none}"
RURAL_VAR="${RURAL_VAR:-is_rural}"
OLD_TABLES="${OLD_TABLES:-${DATA_ROOT}/tex/paper/tables}"
OLD_FIGURES="${OLD_FIGURES:-${DATA_ROOT}/tex/paper/figures}"
TABLES="${REPO_ROOT}/tables"
FIGURES="${REPO_ROOT}/figures"

for required in "${REPO_ROOT}" "${CODE}" \
  "${CODE}/sbatch/run_dofile.sbatch" "${CODE}/sbatch/run_r.sbatch"; do
  if [[ ! -e "${required}" ]]; then
    echo "Required path is missing: ${required}" >&2
    exit 66
  fi
done

mkdir -p "${TABLES}" "${FIGURES}" "${CODE}/logs"

# Preserve successful products from the old shared output directory before any
# dependent table or plotting job starts. These files are small enough to copy
# synchronously from the login node.
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

cd "${CODE}"

if command -v sbatch >/dev/null 2>&1; then
  scheduler="slurm"
elif command -v qsub >/dev/null 2>&1; then
  scheduler="sge"
else
  echo "Neither sbatch nor qsub is available on this cluster." >&2
  exit 69
fi

join_ids() {
  local separator="$1"
  shift
  local result="" item
  for item in "$@"; do
    [[ -z "${item}" ]] && continue
    if [[ -z "${result}" ]]; then
      result="${item}"
    else
      result+="${separator}${item}"
    fi
  done
  printf '%s' "${result}"
}

submit_job() {
  local name="$1" script="$2" dependency="$3" cpus="$4"
  shift 4
  local id

  if [[ "${scheduler}" == "slurm" ]]; then
    local -a options=(--parsable --job-name="${name}" --cpus-per-task="${cpus}")
    [[ -n "${dependency}" ]] && options+=(--dependency="afterok:${dependency}")
    id=$(sbatch "${options[@]}" "${script}" "$@")
    id="${id%%;*}"
  else
    local -a options=(-terse -V -N "${name}")
    if (( cpus > 1 )); then options+=(-pe smp "${cpus}"); fi
    [[ -n "${dependency}" ]] && options+=(-hold_jid "${dependency}")
    id=$(qsub "${options[@]}" "${script}" "$@")
  fi

  echo "Submitted ${name} (${cpus} CPU): ${id}" >&2
  printf '%s' "${id}"
}

submit_stata() {
  local name="$1" dofile="$2" fe_list="$3" suffix="$4"
  local downup="${5:-none}" stacked="${6:-none}" output="${7:-none}"
  submit_job "${name}" sbatch/run_dofile.sbatch "" 1 \
    "${dofile}" "${DATA_ROOT}" "${CODE}" "${LOCATION}" "${SAMPLE}" \
    "${RURAL_VAR}" "${fe_list}" "${suffix}" \
    "${downup}" "${stacked}" "${output}"
}

declare -a table_ids event_ids

# All nine calls below have no dependency and are submitted immediately. The
# scheduler can run them concurrently, subject only to cluster and Stata-license
# availability.
table_ids+=("$(submit_stata recover_main_did_area _main_1_did.do 1/4 _stacked \
  downup_ac combined_dt main_did_downup_area_ac)")
table_ids+=("$(submit_stata recover_main_did_pop _main_1_did.do 1/4 _stacked \
  downup_ac_pop combined_dt_pop main_did_downup_pop_ac)")
table_ids+=("$(submit_stata recover_bureau_polisc _main_3_bureau_polisc_did.do 1/5 none)")
table_ids+=("$(submit_stata recover_treatment_defs _app_6_main_did_treat_definition.do 1/7 none)")
table_ids+=("$(submit_stata recover_alternative_dv _app_7_main_did_downup_area_ac_dv.do 1/3 none)")
table_ids+=("$(submit_stata recover_did_by_year _app_8_main_did_by_year.do 1/10 none)")
table_ids+=("$(submit_stata recover_did_by_state _app_9_main_did_by_state.do 1/4 none)")

event_ids+=("$(submit_stata recover_event_main_area _main_2_stacked_event_study_5pre_area.do 1 none)")
event_ids+=("$(submit_stata recover_event_main_pop _main_2_stacked_event_study_5pre.do 1 none)")

if [[ "${scheduler}" == "slurm" ]]; then
  table_dependency=$(join_ids : "${table_ids[@]}")
  event_dependency=$(join_ids : "${event_ids[@]}")
else
  table_dependency=$(join_ids , "${table_ids[@]}")
  event_dependency=$(join_ids , "${event_ids[@]}")
fi

# These post-processing jobs start only after their actual inputs finish.
table_job=$(submit_job recover_generate_tables sbatch/run_dofile.sbatch \
  "${table_dependency}" 1 \
  _generate_all_tables.do "${DATA_ROOT}" "${CODE}" "${LOCATION}" \
  "${SAMPLE}" "${RURAL_VAR}" 1 none none none none)

event_export_job=$(submit_job recover_export_event_csv sbatch/run_dofile.sbatch \
  "${event_dependency}" 1 \
  _export_event_study_csv.do "${DATA_ROOT}" "${CODE}" "${LOCATION}" \
  "${SAMPLE}" "${RURAL_VAR}" 1 none none none none)

event_plot_job=$(submit_job recover_event_plots sbatch/run_r.sbatch \
  "${event_export_job}" 1 "${DATA_ROOT}" "${CODE}" "${SAMPLE}" "${REPO_ROOT}")

echo
echo "Scheduler: ${scheduler}"
echo "Submitted 9 independent Stata estimations in parallel."
echo "Dependent table job: ${table_job}"
echo "Dependent event CSV job: ${event_export_job}"
echo "Dependent event plot job: ${event_plot_job}"
echo "Logs: ${CODE}/logs"
echo "Tables: ${TABLES}"
echo "Figures: ${FIGURES}"

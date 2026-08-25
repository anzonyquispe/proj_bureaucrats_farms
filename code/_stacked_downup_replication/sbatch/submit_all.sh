#!/usr/bin/env bash
# Submit cluster estimation and data-dependent figure jobs. Ster-to-CSV export,
# LaTeX tables, and event-study R plots are intentionally run locally.

set -euo pipefail

REPLICATION_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
LOCATION="${LOCATION:-shell}"
SAMPLE="${SAMPLE:-none}"
RURAL_VAR="is_rural"
EVENT_FE_LIST="${EVENT_FE_LIST:-1}"
PROTEST_CPUS=3

mkdir -p "${REPLICATION_CODE}/logs"
cd "${REPLICATION_CODE}"

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
  local result=""
  local item
  for item in "$@"; do
    [[ -z "${item}" ]] && continue
    if [[ -z "${result}" ]]; then result="${item}"; else result+="${separator}${item}"; fi
  done
  printf '%s' "${result}"
}

submit_job() {
  local name="$1"
  local script="$2"
  local dependency="$3"
  local cpus="$4"
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
  echo "Submitted ${name} (${cpus} CPU(s)): ${id}" >&2
  printf '%s' "${id}"
}

submit_stata() {
  local name="$1" dofile="$2" fe_list="$3" suffix="$4"
  local downup="${5:-none}" stacked="${6:-none}" output="${7:-none}"
  local cpus=1
  if [[ "${stacked}" == "stacked_data_protest5km" ]]; then
    cpus="${PROTEST_CPUS}"
  fi
  submit_job "${name}" "sbatch/run_dofile.sbatch" "" "${cpus}" \
    "${dofile}" "${REPLICATION_ROOT}" "${REPLICATION_CODE}" "${LOCATION}" \
    "${SAMPLE}" "${RURAL_VAR}" "${fe_list}" "${suffix}" \
    "${downup}" "${stacked}" "${output}"
}

declare -a table_ids event_ids interaction_ids neighbour_ids

# Main and appendix table estimates. Each call is a distinct scheduler job.
table_ids+=("$(submit_stata main_did_area _main_1_did.do 1/4 _stacked downup_ac combined_dt main_did_downup_area_ac)")
table_ids+=("$(submit_stata main_did_pop _main_1_did.do 1/4 _stacked downup_ac_pop combined_dt_pop main_did_downup_pop_ac)")
table_ids+=("$(submit_stata bureau_polisc _main_3_bureau_polisc_did.do 1/4 none)")
table_ids+=("$(submit_stata treatment_defs _app_6_main_did_treat_definition.do 1/7 none)")
table_ids+=("$(submit_stata alternative_dv _app_7_main_did_downup_area_ac_dv.do 1/3 none)")
table_ids+=("$(submit_stata did_by_year _app_8_main_did_by_year.do 1/10 none)")
table_ids+=("$(submit_stata did_by_state _app_9_main_did_by_state.do 1/4 none)")
table_ids+=("$(submit_stata placebo_13km _app_11_placebo_pop_13km.do 1 none)")
table_ids+=("$(submit_stata protest_did_area _main_4_protest_5km_fe12_did_downup.do 1/3 none downup_ac stacked_data_protest5km)")
table_ids+=("$(submit_stata protest_did_pop _main_4_protest_5km_fe12_did_downup.do 1/3 _acpop downup_ac_pop stacked_data_protest5km)")
table_ids+=("$(submit_stata politician_did_area _main_5_polischar_fe12_did_downup_inter.do 1/3 none downup_ac)")
table_ids+=("$(submit_stata politician_did_pop _main_5_polischar_fe12_did_downup_inter.do 1/3 _acpop downup_ac_pop)")

# Descriptive tables are also separate Stata jobs.
table_ids+=("$(submit_stata descriptives_main app_main_descriptive.do 1 none)")
table_ids+=("$(submit_stata descriptives_protest app_5km_descriptive.do 1 none none stacked_data_protest5km)")
table_ids+=("$(submit_stata descriptives_politician app_polischar_descriptive.do 1 none)")

# Event-study estimates. Politician uses the unchanged by-province composition.
# Protest uses the RA's pooled control sample and selected FE3 only.
event_ids+=("$(submit_stata event_5pre_area _main_2_stacked_event_study_5pre_area.do "${EVENT_FE_LIST}" none)")
event_ids+=("$(submit_stata event_5pre_pop _main_2_stacked_event_study_5pre.do "${EVENT_FE_LIST}" none)")
event_ids+=("$(submit_stata politician_event_pop _app_16_polischar_fe12_evst_all.do "${EVENT_FE_LIST}" _acpop downup_ac_pop)")
event_ids+=("$(submit_stata protest_event _app_17_5km_fe12_evst_all.do 3 none none stacked_data_protest5km)")

# Interaction estimates used by the two active interaction figures.
interaction_ids+=("$(submit_stata protest_inter_area _app_18_protest_5km_fe12_did_downup_plot.do 3 none downup_ac stacked_data_protest5km)")
interaction_ids+=("$(submit_stata protest_inter_pop _app_18_protest_5km_fe12_did_downup_plot.do 3 _acpop downup_ac_pop stacked_data_protest5km)")
interaction_ids+=("$(submit_stata politician_inter_area _app_19_polischar_fe12_did_downup_inter_plot.do 1 none downup_ac)")
interaction_ids+=("$(submit_stata politician_inter_pop _app_19_polischar_fe12_did_downup_inter_plot.do 1 _acpop downup_ac_pop)")

# Neighbour estimate is one job; its graph is a dependent second dofile job.
neighbour_ids+=("$(submit_stata neighbour_estimate _main_6_neighbour.do 1 none)")

interaction_dep=$(join_ids : "${interaction_ids[@]}")
neighbour_dep=$(join_ids : "${neighbour_ids[@]}")
if [[ "${scheduler}" == "sge" ]]; then
  interaction_dep=$(join_ids , "${interaction_ids[@]}")
  neighbour_dep=$(join_ids , "${neighbour_ids[@]}")
fi

# LaTeX tables, event-study CSV export, and event-study R figures are local
# post-processing steps. They consume the synchronized repository-level .ster
# files through _run_local_ster_postprocessing.do and plotting_event_studies.R.
interaction_plot_job=$(submit_job interaction_plots sbatch/run_dofile.sbatch "${interaction_dep}" 1 \
  _generate_interaction_plots.do "${REPLICATION_ROOT}" "${REPLICATION_CODE}" "${LOCATION}" \
  "${SAMPLE}" "${RURAL_VAR}" 1 none none none none)
neighbour_plot_job=$(submit_job neighbour_plot sbatch/run_dofile.sbatch "${neighbour_dep}" 1 \
  _main_6_neighbour_plot.do "${REPLICATION_ROOT}" "${REPLICATION_CODE}" "${LOCATION}" \
  "${SAMPLE}" "${RURAL_VAR}" 1 none none none none)

# Non-regression figures extracted from the source notebooks.
design_job=$(submit_job design_maps sbatch/run_python.sbatch "" 1 \
  generate_design_maps.py "${REPLICATION_ROOT}" "${REPLICATION_CODE}" "${SAMPLE}" "${RURAL_VAR}")
desc_fig_job=$(submit_job descriptive_figures sbatch/run_python.sbatch "" 1 \
  generate_descriptive_figures.py "${REPLICATION_ROOT}" "${REPLICATION_CODE}" "${SAMPLE}" "${RURAL_VAR}")
protest_fig_job=$(submit_job protest_figures sbatch/run_python.sbatch "" 1 \
  generate_protest_figures.py "${REPLICATION_ROOT}" "${REPLICATION_CODE}" "${SAMPLE}" "${RURAL_VAR}")

echo "Scheduler: ${scheduler}"
echo "Cluster estimation jobs submitted."
echo "Run local .ster post-processing after synchronizing the tables folder."
echo "Logs: ${REPLICATION_CODE}/logs"

#!/usr/bin/env bash
# Submit every active Stata estimation as an independent scheduler job.
#
# This launcher intentionally does NOT export event-study CSVs, draw figures,
# or render LaTeX tables.  Copy/pull the resulting .ster files locally and run
# _run_local_ster_postprocessing.do and plotting_event_studies.R there.

set -euo pipefail

REPLICATION_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
LOCATION="${LOCATION:-shell}"
SAMPLE="${SAMPLE:-none}"
RURAL_VAR="${RURAL_VAR:-is_rural}"
ANALYSIS_SUBSAMPLE="${ANALYSIS_SUBSAMPLE:-all}"
OUTPUT_TAG="${OUTPUT_TAG:-}"
JOB_PREFIX="${JOB_PREFIX:-}"
RUNNER="${REPLICATION_CODE}/sbatch/run_dofile.sbatch"
LOG_DIR="${REPLICATION_CODE}/logs"

mkdir -p "${LOG_DIR}"
cd "${REPLICATION_CODE}"

if command -v qsub >/dev/null 2>&1; then
  scheduler="sge"
elif command -v sbatch >/dev/null 2>&1; then
  scheduler="slurm"
else
  echo "ERROR: neither qsub nor sbatch is available." >&2
  exit 69
fi

submit_estimation() {
  local name="$1" dofile="$2" cpus="$3" fe_list="$4" base_suffix="$5"
  local downup="${6:-none}" stacked="${7:-none}" output="${8:-none}"
  local controls="${9:-all}"
  local suffix="${base_suffix}"
  if [[ -n "${OUTPUT_TAG}" ]]; then
    [[ "${suffix}" == "none" ]] && suffix=""
    suffix="${suffix}${OUTPUT_TAG}"
  fi
  [[ -z "${suffix}" ]] && suffix="none"
  name="${JOB_PREFIX}${name}"
  local job_id

  if [[ "${scheduler}" == "sge" ]]; then
    local -a opts=(-terse -V -N "${name}" -j y -o /dev/null)
    if (( cpus > 1 )); then opts+=(-pe smp "${cpus}"); fi
    job_id=$(qsub "${opts[@]}" "${RUNNER}" \
      "${dofile}" "${REPLICATION_ROOT}" "${REPLICATION_CODE}" \
      "${LOCATION}" "${SAMPLE}" "${RURAL_VAR}" "${fe_list}" \
      "${suffix}" "${downup}" "${stacked}" "${output}" "${controls}" \
      "${ANALYSIS_SUBSAMPLE}")
  else
    job_id=$(sbatch --parsable --job-name="${name}" \
      --cpus-per-task="${cpus}" --output=/dev/null --error=/dev/null \
      "${RUNNER}" "${dofile}" "${REPLICATION_ROOT}" \
      "${REPLICATION_CODE}" "${LOCATION}" "${SAMPLE}" "${RURAL_VAR}" \
      "${fe_list}" "${suffix}" "${downup}" "${stacked}" "${output}" \
      "${controls}" "${ANALYSIS_SUBSAMPLE}")
    job_id="${job_id%%;*}"
  fi
  printf '%-28s job=%s cpus=%s dofile=%s\n' \
    "${name}" "${job_id}" "${cpus}" "${dofile}"
}

echo "Submitting estimation-only pipeline with ${scheduler}."
echo "Sample suffix: ${SAMPLE}"
echo "Analysis subsample: ${ANALYSIS_SUBSAMPLE}"
echo "Output tag: ${OUTPUT_TAG:-<none>}"
echo "Job prefix: ${JOB_PREFIX:-<none>}"
echo "Permanent logs: ${LOG_DIR}/<job-name>_<job-id>.stata.log"

# Main down/up DiD: the four common-sample FE specifications.
submit_estimation main_did_area _main_1_did.do 1 1/4 _stacked \
  downup_ac combined_dt main_did_downup_area_ac
submit_estimation main_did_pop _main_1_did.do 1 1/4 _stacked \
  downup_ac_pop combined_dt_pop main_did_downup_pop_ac

# Remaining main and appendix table estimations.
submit_estimation bureau_polisc _main_3_bureau_polisc_did.do 1 1/4 none
submit_estimation treatment_defs _app_6_main_did_treat_definition.do 1 1/7 none
submit_estimation alternative_dv _app_7_main_did_downup_area_ac_dv.do 1 1/3 none
submit_estimation did_by_year _app_8_main_did_by_year.do 1 1/10 none
submit_estimation did_by_state _app_9_main_did_by_state.do 1 1/4 none
submit_estimation placebo_13km _app_11_placebo_pop_13km.do 1 1 none

# Descriptive tables reproduce the richest-regression e(sample) directly from
# each full stack. Protest receives three cores; the other jobs receive one.
submit_estimation descriptives_main app_main_descriptive.do 1 1 none
submit_estimation descriptives_protest app_5km_descriptive.do 3 1 none \
  none stacked_data_protest5km
submit_estimation descriptives_politician app_polischar_descriptive.do 1 1 none

# Main down/up event studies.
submit_estimation event_area _main_2_stacked_event_study_5pre_area.do 1 1 none
submit_estimation event_pop _main_2_stacked_event_study_5pre.do 1 1 none

# Protest jobs use three cores.  Every invocation remains a separate job.
submit_estimation protest_did_area _main_4_protest_5km_fe12_did_downup.do 3 1/3 none \
  downup_ac stacked_data_protest5km
submit_estimation protest_did_pop _main_4_protest_5km_fe12_did_downup.do 3 1/3 _acpop \
  downup_ac_pop stacked_data_protest5km
submit_estimation protest_inter_area _app_18_protest_5km_fe12_did_downup_plot.do 3 3 none \
  downup_ac stacked_data_protest5km
submit_estimation protest_inter_pop _app_18_protest_5km_fe12_did_downup_plot.do 3 3 _acpop \
  downup_ac_pop stacked_data_protest5km
submit_estimation protest_event _app_17_5km_fe12_evst_all.do 3 3 none \
  none stacked_data_protest5km none all

# Politician-by-province jobs use one core.
submit_estimation politician_did_area _main_5_polischar_fe12_did_downup_inter.do 1 1/3 none \
  downup_ac
submit_estimation politician_did_pop _main_5_polischar_fe12_did_downup_inter.do 1 1/3 _acpop \
  downup_ac_pop
submit_estimation politician_inter_area _app_19_polischar_fe12_did_downup_inter_plot.do 1 1 none \
  downup_ac
submit_estimation politician_inter_pop _app_19_polischar_fe12_did_downup_inter_plot.do 1 1 _acpop \
  downup_ac_pop
submit_estimation politician_event_pop _app_16_polischar_fe12_evst_all.do 1 1 _acpop \
  downup_ac_pop none none both

# Neighbour-border estimate only; its graph is generated locally.
submit_estimation neighbour _main_6_neighbour.do 1 1 none

echo "All estimation jobs were submitted independently."
echo "No cluster plot or table-rendering jobs were submitted."

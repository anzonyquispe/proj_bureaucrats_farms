#!/usr/bin/env bash
# Submit only production DiD, robustness, and descriptive-statistics jobs.
# Event-study regressions and plots are intentionally excluded.
#
# Usage on the cluster:
#   bash code/_stacked_downup_replication/sbatch/submit_did_descriptives_only.sh
#
# Optional sample test:
#   SAMPLE=_sample JOB_PREFIX=test_ bash \
#     code/_stacked_downup_replication/sbatch/submit_did_descriptives_only.sh

set -euo pipefail

REPLICATION_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
REPLICATION_CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
LOCATION="${LOCATION:-shell}"
SAMPLE="${SAMPLE:-none}"
RURAL_VAR="${RURAL_VAR:-is_rural}"
ANALYSIS_SUBSAMPLE="${ANALYSIS_SUBSAMPLE:-all}"
JOB_PREFIX="${JOB_PREFIX:-did_}"
RUNNER="${REPLICATION_CODE}/sbatch/run_dofile.sbatch"

if command -v qsub >/dev/null 2>&1; then
  scheduler="sge"
elif command -v sbatch >/dev/null 2>&1; then
  scheduler="slurm"
else
  echo "ERROR: neither qsub nor sbatch is available." >&2
  exit 69
fi

submit_one() {
  local name="$1" dofile="$2" cpus="$3" fe_list="$4" suffix="$5"
  local downup="${6:-none}" stacked="${7:-none}" output="${8:-none}"
  local dependency="${9:-}"
  local full_name="${JOB_PREFIX}${name}"
  local job_id

  if [[ "${scheduler}" == "sge" ]]; then
    local -a opts=(-terse -V -N "${full_name}" -j y -o /dev/null)
    (( cpus > 1 )) && opts+=(-pe smp "${cpus}")
    [[ -n "${dependency}" ]] && opts+=(-hold_jid "${dependency}")
    job_id=$(qsub "${opts[@]}" "${RUNNER}" \
      "${dofile}" "${REPLICATION_ROOT}" "${REPLICATION_CODE}" \
      "${LOCATION}" "${SAMPLE}" "${RURAL_VAR}" "${fe_list}" \
      "${suffix}" "${downup}" "${stacked}" "${output}" all \
      "${ANALYSIS_SUBSAMPLE}")
  else
    local -a opts=(--parsable --job-name="${full_name}" \
      --cpus-per-task="${cpus}" --output=/dev/null --error=/dev/null)
    [[ -n "${dependency}" ]] && opts+=(--dependency="afterok:${dependency}")
    job_id=$(sbatch "${opts[@]}" "${RUNNER}" \
      "${dofile}" "${REPLICATION_ROOT}" "${REPLICATION_CODE}" \
      "${LOCATION}" "${SAMPLE}" "${RURAL_VAR}" "${fe_list}" \
      "${suffix}" "${downup}" "${stacked}" "${output}" all \
      "${ANALYSIS_SUBSAMPLE}")
    job_id="${job_id%%;*}"
  fi

  printf '%-28s job=%s cpus=%s hold=%s\n' \
    "${full_name}" "${job_id}" "${cpus}" "${dependency:-none}" >&2
  printf '%s' "${job_id}"
}

echo "Scheduler: ${scheduler}"
echo "Input suffix: ${SAMPLE}"
echo "Analysis subsample: ${ANALYSIS_SUBSAMPLE}"
echo "No event-study jobs will be submitted."

# These three jobs define and export the exact samples used downstream.
main_id=$(submit_one main_pop _main_1_did.do 1 1/4 _stacked \
  downup_ac_pop combined_dt_pop main_did_downup_pop_ac)
politician_id=$(submit_one politician _main_5_polischar_fe12_did_downup_inter.do \
  1 1/3 _acpop downup_ac_pop)
protest_id=$(submit_one protest _main_4_protest_5km_fe12_did_downup.do \
  3 1/3 _acpop downup_ac_pop stacked_data_protest5km)

# The bureaucrat-politician table has its own richest specification and also
# exports that exact sample for auditing.
submit_one bureau_polisc _main_3_bureau_polisc_did.do 1 1/4 none >/dev/null

# Every main robustness job waits for the specification-4 population sample.
submit_one treatment_defs _app_6_main_did_treat_definition.do \
  1 1/7 none none none none "${main_id}" >/dev/null
submit_one alternative_dv _app_7_main_did_downup_area_ac_dv.do \
  1 1/3 none none none none "${main_id}" >/dev/null
submit_one by_year _app_8_main_did_by_year.do \
  1 1/10 none none none none "${main_id}" >/dev/null
submit_one by_province _app_9_main_did_by_state.do \
  1 1/4 none none none none "${main_id}" >/dev/null
submit_one placebo_13km _app_11_placebo_pop_13km.do \
  1 1 none none none none "${main_id}" >/dev/null

# Descriptive tables read the exported samples directly and therefore wait for
# the corresponding richest DiD job. Protest retains the requested 3 cores.
submit_one descriptive_main app_main_descriptive.do \
  1 1 none none none none "${main_id}" >/dev/null
submit_one descriptive_politician app_polischar_descriptive.do \
  1 1 none none none none "${politician_id}" >/dev/null
submit_one descriptive_protest app_5km_descriptive.do \
  3 1 none none none none "${protest_id}" >/dev/null

echo "Submitted DiD, robustness, and descriptive jobs with after-success dependencies."
echo "Permanent Stata logs: ${REPLICATION_CODE}/logs/<job-name>_<job-id>.stata.log"


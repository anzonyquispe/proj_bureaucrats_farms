#!/usr/bin/env bash
# Submit only the corrected protest event-study and DiD estimations.

set -euo pipefail

ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
INTERMEDIATE="${PIPELINE_INTERMEDIATE:-${ROOT}/data_output/intermediate}"
RUNNER="${CODE}/sbatch/run_dofile.sbatch"
SAMPLE="${SAMPLE:-none}"

if [[ ! -f "${INTERMEDIATE}/grid_month_ac_area_tr.dta" ]]; then
  echo "ERROR: ${INTERMEDIATE}/grid_month_ac_area_tr.dta is missing." >&2
  echo "Run build_grid_month_ac_area_tr.sbatch first." >&2
  exit 1
fi
if ! command -v qsub >/dev/null 2>&1; then
  echo "ERROR: qsub is unavailable on this host." >&2
  exit 69
fi

submit() {
  local name="$1" dofile="$2" suffix="$3" downup="$4" fe="$5"
  qsub -terse -V -N "${name}" -j y -o /dev/null -pe smp 3 \
    "${RUNNER}" "${dofile}" "${ROOT}" "${CODE}" shell "${SAMPLE}" \
    is_rural "${fe}" "${suffix}" "${downup}" \
    stacked_data_protest5km none all all
}

echo "Submitting corrected protest estimations; sample=${SAMPLE}"
submit protest_did_area   _main_4_protest_5km_fe12_did_downup.do      none   downup_ac     1/3
submit protest_did_pop    _main_4_protest_5km_fe12_did_downup.do      _acpop downup_ac_pop 1/3
submit protest_inter_area _app_18_protest_5km_fe12_did_downup_plot.do none   downup_ac     3
submit protest_inter_pop  _app_18_protest_5km_fe12_did_downup_plot.do _acpop downup_ac_pop 3
submit protest_event      _app_17_5km_fe12_evst_all.do                none   none          3

echo "Submitted five independent three-core jobs. Permanent logs are in ${CODE}/logs."

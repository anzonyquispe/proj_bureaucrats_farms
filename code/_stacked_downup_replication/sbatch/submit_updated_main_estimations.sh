#!/usr/bin/env bash
# Submit only the production estimations changed by the final sample/moderator
# cleanup. Plotting, CSV export, and LaTeX rendering remain local tasks.

set -euo pipefail

ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
RUNNER="${CODE}/sbatch/run_dofile.sbatch"

if ! command -v qsub >/dev/null 2>&1; then
  echo "ERROR: qsub is unavailable. Run this launcher from a CRC login node." >&2
  exit 69
fi

submit_job() {
  local name="$1" cpus="$2" dofile="$3" fe_list="$4"
  local ster_suffix="$5" downup_var="$6" control_samples="$7"
  local -a scheduler=(-terse -V -N "${name}" -j y -o /dev/null)
  if (( cpus > 1 )); then
    scheduler+=(-pe smp "${cpus}")
  fi
  local job_id
  job_id=$(qsub "${scheduler[@]}" "${RUNNER}" \
    "${dofile}" "${ROOT}" "${CODE}" shell none is_rural "${fe_list}" \
    "${ster_suffix}" "${downup_var}" none none "${control_samples}" all)
  printf '%-30s job=%s cpus=%s\n' "${name}" "${job_id}" "${cpus}"
}

echo "Submitting updated full-sample production estimations."
echo "Permanent logs: ${CODE}/logs/<job-name>_<job-id>.stata.log"

# Redesigned four-column bureaucrat/politician table on its anchored sample.
submit_job bureau_polisc_final 1 _main_3_bureau_polisc_did.do 1/4 none none all

# Treatment-definition table no longer inner-merges the obsolete rice file.
submit_job treatment_defs_final 1 _app_6_main_did_treat_definition.do 1/7 none none all

# Protest event study now uses the stack's native rice-production moderator.
submit_job protest_event_final 3 _app_17_5km_fe12_evst_all.do 3 none none all

# Canonical politician event study: baseline plus rice production only.
submit_job politician_event_final 1 _app_16_polischar_fe12_evst_all.do 1 \
  _acpop downup_ac_pop both

echo "Submitted all four updated production jobs."

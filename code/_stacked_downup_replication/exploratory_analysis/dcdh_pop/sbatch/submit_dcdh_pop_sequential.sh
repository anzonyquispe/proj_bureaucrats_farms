#!/usr/bin/env bash
# Submit population-only dCDH specifications as one SGE dependency chain.
# At most one memory-intensive estimator job can run at a time.
#
# Usage:
#   bash submit_dcdh_pop_sequential.sh       # all 18 production runs
#   bash submit_dcdh_pop_sequential.sh core  # six runs without switcher filter

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB_FILE="${SCRIPT_DIR}/run_dcdh_pop.sbatch"
SCOPE="${1:-all}"
if [[ "${SCOPE}" != "all" && "${SCOPE}" != "core" ]]; then
  echo "Usage: $0 [all|core]" >&2
  exit 2
fi

submit_one() {
  local driver="$1"
  local variant="$2"
  local switchers="$3"
  local prior_job="${4:-}"
  local suffix="${switchers:+_${switchers}}"
  local job_name="dcp_${driver}_${variant}${suffix}"
  local variables="DRIVER=${driver},VARIANT=${variant}"
  if [[ -n "${switchers}" ]]; then
    variables="${variables},SWITCHERS=${switchers}"
  fi
  if [[ -n "${prior_job}" ]]; then
    variables="${variables},REQUIRE_JOB_ID=${prior_job}"
  fi
  local output

  if [[ -n "${prior_job}" ]]; then
    output=$(qsub -terse -hold_jid "${prior_job}" -N "${job_name}" \
      -v "${variables}" "${JOB_FILE}")
  else
    output=$(qsub -terse -N "${job_name}" \
      -v "${variables}" "${JOB_FILE}")
  fi
  printf '%s\n' "${output%%.*}"
}

switcher_specs=("")
if [[ "${SCOPE}" == "all" ]]; then
  switcher_specs+=("in" "out")
fi

previous=""
for driver in noreset reset6 reset12; do
  for variant in notrend actrend; do
    for switchers in "${switcher_specs[@]}"; do
      job_id=$(submit_one "${driver}" "${variant}" "${switchers}" "${previous}")
      label="${driver}/${variant}/${switchers:-all-switchers}"
      if [[ -n "${previous}" ]]; then
        echo "submitted ${job_id}: ${label}; held for ${previous}"
      else
        echo "submitted ${job_id}: ${label}; starts when scheduled"
      fi
      previous="${job_id}"
    done
  done
done

echo "Sequential ${SCOPE} chain created. Final job: ${previous}"
echo "Monitor with: qstat -u \$USER"

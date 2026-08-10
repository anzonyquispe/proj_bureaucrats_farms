#!/usr/bin/env bash
#$ -N did_window
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/did_windows/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/did_windows/logs

set -euo pipefail

CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
WINDOW_MIN="${WINDOW_MIN:?Set WINDOW_MIN}"
WINDOW_MAX="${WINDOW_MAX:?Set WINDOW_MAX}"
WINDOW_LABEL="${WINDOW_LABEL:?Set WINDOW_LABEL}"
TREATMENT="${TREATMENT:?Set TREATMENT to area or pop}"

case "${WINDOW_LABEL}" in
  m6_p6|m6_p5|m5_p5|m5_p6) ;;
  *) echo "ERROR: unsupported WINDOW_LABEL=${WINDOW_LABEL}" >&2; exit 2 ;;
esac

case "${TREATMENT}" in
  area)
    stacked_file="combined_dt"
    treatment_var="downup_ac"
    output_stem="exploratory_analysis/main_did_downup_area_ac_${WINDOW_LABEL}"
    ;;
  pop)
    stacked_file="combined_dt_pop"
    treatment_var="downup_ac_pop"
    output_stem="exploratory_analysis/main_did_downup_pop_ac_${WINDOW_LABEL}"
    ;;
  *) echo "ERROR: unsupported TREATMENT=${TREATMENT}" >&2; exit 2 ;;
esac

mkdir -p "${CODE}/../../tables/exploratory_analysis"
mkdir -p "${CODE}/exploratory_analysis/did_windows/logs"

if ! type module >/dev/null 2>&1; then
  if [[ "${FARMS_LOGIN_RETRY:-0}" == "1" ]]; then
    echo "ERROR: the module command is unavailable even in a login shell." >&2
    exit 127
  fi
  export FARMS_LOGIN_RETRY=1
  exec /bin/bash -l "$0" "$@"
fi

module load stata gcc
cd "${CODE}/exploratory_analysis/did_windows/logs"

stata-mp -b do "${CODE}/_main_1_did.do" \
  "${stacked_file}" "${treatment_var}" "${output_stem}" _stacked \
  "${WINDOW_MIN}" "${WINDOW_MAX}"

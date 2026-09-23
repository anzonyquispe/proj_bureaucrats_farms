#!/usr/bin/env bash
#$ -N didwin_tables
#$ -q largemem
#$ -pe smp 1
#$ -cwd
# Log destinations are passed as -o/-e by submit_all_did_windows.sh; SGE cannot
# expand variables in "#$" directives, so no path is hardcoded here. Submitting
# this file directly without -o/-e falls back to -cwd.

set -euo pipefail

# submit_all_did_windows.sh resolves REPLICATION_CODE from its own location.
CODE="${REPLICATION_CODE:?Set REPLICATION_CODE (submit via submit_all_did_windows.sh)}"
export REPLICATION_CODE="${CODE}"
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
stata-mp -b do "${CODE}/exploratory_analysis/did_windows/generate_tables_explore.do"

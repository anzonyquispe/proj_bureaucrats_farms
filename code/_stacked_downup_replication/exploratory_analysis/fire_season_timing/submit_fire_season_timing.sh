#!/usr/bin/env bash
# Submit the exploratory October-November seasonality event study.
# Usage: bash submit_fire_season_timing.sh [full|sample]

set -euo pipefail

MODE="${1:-full}"
case "${MODE}" in
  full) SAMPLE_ARG="none" ;;
  sample) SAMPLE_ARG="_sample" ;;
  *) echo "Usage: $0 [full|sample]" >&2; exit 64 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
job_id=$(qsub -terse -v "SAMPLE_ARG=${SAMPLE_ARG}" \
  "${SCRIPT_DIR}/run_fire_season_timing.sbatch")
echo "Submitted fire-season timing event study (${MODE}): ${job_id}"
echo "Log: ${SCRIPT_DIR}/logs/fire_season_timing.log"

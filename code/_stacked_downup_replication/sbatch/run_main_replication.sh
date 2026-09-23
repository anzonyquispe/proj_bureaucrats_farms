#!/usr/bin/env bash
# One cluster entry point for the production replication.
#
# Usage:
#   bash sbatch/run_main_replication.sh full   all
#   bash sbatch/run_main_replication.sh sample all
#   bash sbatch/run_main_replication.sh full   rice_high
#   bash sbatch/run_main_replication.sh sample rice_high

set -euo pipefail

DATA_SIZE="${1:-full}"
SUBSAMPLE="${2:-all}"

case "${DATA_SIZE}" in
  full)
    export SAMPLE="none"
    size_prefix="full_"
    ;;
  sample)
    export SAMPLE="_sample"
    size_prefix="sample_"
    ;;
  *)
    echo "ERROR: first argument must be full or sample." >&2
    exit 64
    ;;
esac

case "${SUBSAMPLE}" in
  all)
    export ANALYSIS_SUBSAMPLE="all"
    export OUTPUT_TAG=""
    subsample_prefix=""
    ;;
  rice_high)
    export ANALYSIS_SUBSAMPLE="rice_high"
    export OUTPUT_TAG="_rice_high"
    subsample_prefix="rice_"
    ;;
  *)
    echo "ERROR: second argument must be all or rice_high." >&2
    exit 64
    ;;
esac

export JOB_PREFIX="${JOB_PREFIX:-${size_prefix}${subsample_prefix}}"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
echo "Production replication: data_size=${DATA_SIZE}; subsample=${SUBSAMPLE}"
echo "Scheduler job prefix: ${JOB_PREFIX}"
exec bash "${SCRIPT_DIR}/submit_all.sh"

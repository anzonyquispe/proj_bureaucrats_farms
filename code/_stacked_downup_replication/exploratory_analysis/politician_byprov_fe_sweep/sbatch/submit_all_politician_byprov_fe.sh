#!/usr/bin/env bash
set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep"
ARRAY_RUNNER="${ANALYSIS_DIR}/sbatch/run_all_politician_byprov_fe.sbatch"
LOG_DIR="${ANALYSIS_DIR}/logs"

mkdir -p "${LOG_DIR}"
test -f "${ARRAY_RUNNER}"

job_id=$(qsub -terse \
    -v "REPLICATION_REPO=${REPO}" \
    "${ARRAY_RUNNER}")
echo "Submitted politician-by-province FE array 1-32: ${job_id}"

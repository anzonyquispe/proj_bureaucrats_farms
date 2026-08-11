#!/usr/bin/env bash
set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep"
RUNNER="${ANALYSIS_DIR}/sbatch/run_politician_byprov_fe.sbatch"
LOG_DIR="${ANALYSIS_DIR}/logs"

mkdir -p "${LOG_DIR}"
test -f "${RUNNER}"

for fe_id in $(seq 1 32); do
    fe_tag=$(printf '%02d' "${fe_id}")
    job_id=$(qsub -terse \
        -N "polbp_fe${fe_tag}" \
        -v "FE_ID=${fe_id},REPLICATION_REPO=${REPO}" \
        "${RUNNER}")
    echo "Submitted FE ${fe_tag}: ${job_id}"
done


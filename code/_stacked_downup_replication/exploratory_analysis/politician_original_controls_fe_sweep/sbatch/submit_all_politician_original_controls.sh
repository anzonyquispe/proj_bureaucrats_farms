#!/usr/bin/env bash

# One command submits the 96-task estimation array and a dependent plotting /
# report job. The second job starts only after the complete array finishes.

set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep"
ARRAY_RUNNER="${ANALYSIS_DIR}/sbatch/run_all_politician_original_controls_fe.sbatch"
POSTPROCESS="${ANALYSIS_DIR}/sbatch/postprocess_politician_original_controls.sbatch"
LOG_DIR="${ANALYSIS_DIR}/logs"

mkdir -p "${LOG_DIR}"
test -f "${ARRAY_RUNNER}"
test -f "${POSTPROCESS}"

array_job=$(qsub -terse \
    -v "REPLICATION_REPO=${REPO}" \
    "${ARRAY_RUNNER}")
array_job_id="${array_job%%.*}"
echo "Submitted 96-task estimation array: ${array_job}"

post_job=$(qsub -terse \
    -hold_jid "${array_job_id}" \
    -v "REPLICATION_REPO=${REPO}" \
    "${POSTPROCESS}")
echo "Submitted dependent plot/report job: ${post_job}"
echo "The post-processing job waits for array job ${array_job_id}."


#!/usr/bin/env bash
#$ -N polbp_did_fe
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -j y
#$ -t 1-32
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep/logs

# Submit once with qsub. SGE creates 32 independent one-core tasks, and each
# task estimates the baseline event study plus the _app_19-style DiD
# interaction for exactly one FE specification.

set -euo pipefail

: "${SGE_TASK_ID:?This file must be submitted as an SGE array job}"
REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
RUNNER="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep/sbatch/run_politician_byprov_fe.sbatch"

if ! [[ "${SGE_TASK_ID}" =~ ^([1-9]|[12][0-9]|3[0-2])$ ]]; then
    echo "Invalid SGE_TASK_ID=${SGE_TASK_ID}; expected 1,...,32" >&2
    exit 198
fi
if [[ ! -f "${RUNNER}" ]]; then
    echo "Missing FE runner: ${RUNNER}" >&2
    exit 66
fi

export FE_ID="${SGE_TASK_ID}"
export REPLICATION_REPO="${REPO}"
exec /bin/bash "${RUNNER}"


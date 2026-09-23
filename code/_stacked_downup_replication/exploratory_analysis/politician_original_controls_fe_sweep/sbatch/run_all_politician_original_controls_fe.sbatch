#!/usr/bin/env bash
#$ -N pol_orig_ctrl
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -j y
#$ -t 1-96
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep/logs

# Task mapping:
#    1-32 = never-treated controls
#   33-64 = both control types
#   65-96 = legacy not-yet/partial-zero-spell controls

set -euo pipefail

: "${SGE_TASK_ID:?Submit this file as an SGE array job}"
if ! [[ "${SGE_TASK_ID}" =~ ^[1-9][0-9]?$ ]] || \
        (( SGE_TASK_ID < 1 || SGE_TASK_ID > 96 )); then
    echo "Invalid SGE_TASK_ID=${SGE_TASK_ID}; expected 1,...,96" >&2
    exit 198
fi

zero_based=$((SGE_TASK_ID - 1))
FE_ID=$((zero_based % 32 + 1))
control_block=$((zero_based / 32))
case "${control_block}" in
    0) CONTROL_SAMPLE="never" ;;
    1) CONTROL_SAMPLE="both" ;;
    2) CONTROL_SAMPLE="notyet" ;;
    *) echo "Invalid control block ${control_block}" >&2; exit 198 ;;
esac

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
RUNNER="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep/sbatch/run_politician_original_controls_fe.sbatch"
if [[ ! -f "${RUNNER}" ]]; then
    echo "Missing task runner: ${RUNNER}" >&2
    exit 66
fi

export FE_ID CONTROL_SAMPLE REPLICATION_REPO="${REPO}"
echo "Array task ${SGE_TASK_ID}: FE=${FE_ID}, controls=${CONTROL_SAMPLE}"
exec /bin/bash "${RUNNER}"


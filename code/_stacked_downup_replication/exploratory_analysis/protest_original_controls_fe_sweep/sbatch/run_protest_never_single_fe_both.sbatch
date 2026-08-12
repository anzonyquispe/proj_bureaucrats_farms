#!/usr/bin/env bash
#$ -N pr_never_fe
#$ -q largemem
#$ -pe smp 5
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

# Dedicated recovery wrapper: one never-treated FE, event study and DiD in the
# same Stata process. Submit once per RECOVERY_FE.
set -euo pipefail
: "${RECOVERY_FE:?RECOVERY_FE must be an integer from 16 through 32}"
[[ "${RECOVERY_FE}" =~ ^(1[6-9]|2[0-9]|3[0-2])$ ]] || {
    echo "RECOVERY_FE must be from 16 through 32; received ${RECOVERY_FE}" >&2
    exit 198
}

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
GENERIC_RUNNER="${REPO}/code/_stacked_downup_replication/exploratory_analysis/protest_original_controls_fe_sweep/sbatch/run_protest_original_single_fe.sbatch"
[[ -f "${GENERIC_RUNNER}" ]] || { echo "Missing ${GENERIC_RUNNER}" >&2; exit 66; }

export CONTROL_SAMPLE=never
export ANALYSIS_STAGE=both
export REPLICATION_REPO="${REPO}"
exec bash "${GENERIC_RUNNER}"

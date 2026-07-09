#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N tweets_r2_wp_own
#$ -pe smp 1
#$ -cwd
#$ -o logs/$JOB_NAME.$JOB_ID.out
#$ -e logs/$JOB_NAME.$JOB_ID.err

# -----------------------------------------------------------------------------
# Robustness preamble: fail loud, run the latest checked-out code, and start
# Stata from a clean module/temp environment so this job never picks up stale
# state from a prior submission. (Mirrors code/_replication_rural/sbatch/.)
# -----------------------------------------------------------------------------
set -euo pipefail

# Always run from the canonical project tree on the cluster -- guards against
# inheriting a stale CWD from the submitter's shell.
CODE_DIR="/users/aquisper/proj_bureaucrats_farms/code/_tweets_analysis_rubric2"
cd "${CODE_DIR}"

mkdir -p logs

echo "[$(date '+%F %T')] host=$(hostname) job=${JOB_ID:-NA} pwd=$(pwd)"
if command -v git >/dev/null 2>&1; then
    echo "[$(date '+%F %T')] git HEAD: $(git -C "${CODE_DIR}" rev-parse --short HEAD 2>/dev/null || echo 'not-a-git-repo')"
fi

# Force a clean module environment then load stata fresh.
module purge 2>/dev/null || true
module load stata

# Per-job scratch dir so concurrent / repeat submissions don't share state.
export TMPDIR="${TMPDIR:-/tmp}/stata.${JOB_ID:-$$}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

# ---- Job-specific globals -> wrapper.do --------------------------------------
PROJ_SHELL="/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
DOFILE_PATH="${CODE_DIR}/_tweets_did_event_study.do"
WRAPPER="logs/tweets_r2_wp_own_wrapper.do"

cat > "${WRAPPER}" <<EOF
clear all
set more off
global shell        "${PROJ_SHELL}"
global job_name     "tweets_r2_wp_own"
global outcome_list "wp_pm_kisan_own wp_crop_insurance_own wp_machinery_distribution_own wp_msp_procurement_own wp_debt_relief_own wp_irrigation_scheme_own wp_soil_health_own wp_organic_farming_own wp_other_farm_policy_own wp_none_own"
do "${DOFILE_PATH}"
EOF

# Wipe the prior Stata log for this wrapper so we read only this run's output.
rm -f "${WRAPPER%.do}.log"

echo "[$(date '+%F %T')] starting tweets_r2_wp_own"
echo "  outcomes: wp_pm_kisan_own wp_crop_insurance_own wp_machinery_distribution_own wp_msp_procurement_own wp_debt_relief_own wp_irrigation_scheme_own wp_soil_health_own wp_organic_farming_own wp_other_farm_policy_own wp_none_own"
stata-mp -b do "${WRAPPER}"
rc=$?
echo "[$(date '+%F %T')] tweets_r2_wp_own finished rc=$rc"
exit $rc

#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N tweets_rh_own
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

# Always run from the canonical project tree on the cluster — guards against
# inheriting a stale CWD from the submitter's shell.
CODE_DIR="/users/aquisper/proj_bureaucrats_farms/code/_tweets_analysis"
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

# ---- Job-specific globals → wrapper.do --------------------------------------
PROJ_SHELL="/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
DOFILE_PATH="${CODE_DIR}/_tweets_did_event_study.do"
WRAPPER="logs/tweets_rh_own_wrapper.do"

cat > "${WRAPPER}" <<EOF
clear all
set more off
global shell        "${PROJ_SHELL}"
global job_name     "tweets_rh_own"
global outcome_list "rh_accusatory_own rh_celebratory_own rh_ceremonial_own rh_contempt_own rh_critical_own rh_empathetic_own rh_fear_alarm_own rh_governance_own rh_grievance_own rh_informational_own rh_mobilizational_own rh_persuasive_own rh_reflective_own rh_solidarity_own rh_supportive_own rh_tribute_ceremony_own rh_unclear_own"
do "${DOFILE_PATH}"
EOF

# Wipe the prior Stata log for this wrapper so we read only this run's output.
rm -f "${WRAPPER%.do}.log"

echo "[$(date '+%F %T')] starting tweets_rh_own"
echo "  outcomes: rh_accusatory_own rh_celebratory_own rh_ceremonial_own rh_contempt_own rh_critical_own rh_empathetic_own rh_fear_alarm_own rh_governance_own rh_grievance_own rh_informational_own rh_mobilizational_own rh_persuasive_own rh_reflective_own rh_solidarity_own rh_supportive_own rh_tribute_ceremony_own rh_unclear_own"
stata-mp -b do "${WRAPPER}"
rc=$?
echo "[$(date '+%F %T')] tweets_rh_own finished rc=$rc"
exit $rc

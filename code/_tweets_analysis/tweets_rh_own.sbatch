#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N tweets_rh_own
#$ -pe smp 1
#$ -cwd
#$ -o logs/$JOB_NAME.$JOB_ID.out
#$ -e logs/$JOB_NAME.$JOB_ID.err

set -euo pipefail
module purge 2>/dev/null || true
module load stata

PROJ_SHELL="/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
GIT_ROOT="${GIT_ROOT:-/users/aquisper/proj_bureaucrats_farms}"
DOFILE_PATH="$GIT_ROOT/code/_tweets_analysis/_tweets_did_event_study.do"

mkdir -p logs

# Per-job scratch dir so concurrent jobs don't share Stata temp state.
export TMPDIR="${TMPDIR:-/tmp}/stata.${JOB_ID:-$$}"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

WRAPPER="logs/tweets_rh_own_wrapper.do"
cat > "$WRAPPER" <<EOF
clear all
set more off
global shell        "$PROJ_SHELL"
global job_name     "tweets_rh_own"
global outcome_list "rh_accusatory_own rh_celebratory_own rh_ceremonial_own rh_contempt_own rh_critical_own rh_empathetic_own rh_fear_alarm_own rh_governance_own rh_grievance_own rh_informational_own rh_mobilizational_own rh_persuasive_own rh_reflective_own rh_solidarity_own rh_supportive_own rh_tribute_ceremony_own rh_unclear_own"
do "$DOFILE_PATH"
EOF

echo "[$(date '+%F %T')] starting tweets_rh_own"
echo "  outcomes: rh_accusatory_own rh_celebratory_own rh_ceremonial_own rh_contempt_own rh_critical_own rh_empathetic_own rh_fear_alarm_own rh_governance_own rh_grievance_own rh_informational_own rh_mobilizational_own rh_persuasive_own rh_reflective_own rh_solidarity_own rh_supportive_own rh_tribute_ceremony_own rh_unclear_own"
stata-mp -b do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] tweets_rh_own finished rc=$rc"
exit $rc

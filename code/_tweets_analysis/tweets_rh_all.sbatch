#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N tweets_rh_all
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

WRAPPER="logs/tweets_rh_all_wrapper.do"
cat > "$WRAPPER" <<EOF
clear all
set more off
global shell        "$PROJ_SHELL"
global job_name     "tweets_rh_all"
global outcome_list "rh_accusatory_all rh_celebratory_all rh_ceremonial_all rh_contempt_all rh_critical_all rh_empathetic_all rh_fear_alarm_all rh_governance_all rh_grievance_all rh_informational_all rh_mobilizational_all rh_persuasive_all rh_reflective_all rh_solidarity_all rh_supportive_all rh_tribute_ceremony_all rh_unclear_all"
do "$DOFILE_PATH"
EOF

echo "[$(date '+%F %T')] starting tweets_rh_all"
echo "  outcomes: rh_accusatory_all rh_celebratory_all rh_ceremonial_all rh_contempt_all rh_critical_all rh_empathetic_all rh_fear_alarm_all rh_governance_all rh_grievance_all rh_informational_all rh_mobilizational_all rh_persuasive_all rh_reflective_all rh_solidarity_all rh_supportive_all rh_tribute_ceremony_all rh_unclear_all"
stata-mp -b do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] tweets_rh_all finished rc=$rc"
exit $rc

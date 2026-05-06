#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N tweets_neu_own
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

WRAPPER="logs/tweets_neu_own_wrapper.do"
cat > "$WRAPPER" <<EOF
clear all
set more off
global shell        "$PROJ_SHELL"
global job_name     "tweets_neu_own"
global outcome_list "neu_agriculture_own neu_development_own neu_election_campaign_own neu_environment_pollution_own neu_farmer_protest_own neu_governance_own neu_party_politics_own neu_sports_culture_own neu_tribute_ceremony_own neu_unclear_own neu_welfare_own"
do "$DOFILE_PATH"
EOF

echo "[$(date '+%F %T')] starting tweets_neu_own"
echo "  outcomes: neu_agriculture_own neu_development_own neu_election_campaign_own neu_environment_pollution_own neu_farmer_protest_own neu_governance_own neu_party_politics_own neu_sports_culture_own neu_tribute_ceremony_own neu_unclear_own neu_welfare_own"
stata-mp -b do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] tweets_neu_own finished rc=$rc"
exit $rc

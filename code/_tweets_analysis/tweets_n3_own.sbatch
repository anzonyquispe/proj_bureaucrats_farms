#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N tweets_n3_own
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

WRAPPER="logs/tweets_n3_own_wrapper.do"
cat > "$WRAPPER" <<EOF
clear all
set more off
global shell        "$PROJ_SHELL"
global job_name     "tweets_n3_own"
global outcome_list "n3_accusatory_own n3_agriculture_own n3_development_own n3_election_campaign_own n3_environment_pollution_own n3_farmer_protest_own n3_governance_own n3_party_politics_own n3_sports_culture_own n3_tribute_ceremony_own n3_welfare_own"
do "$DOFILE_PATH"
EOF

echo "[$(date '+%F %T')] starting tweets_n3_own"
echo "  outcomes: n3_accusatory_own n3_agriculture_own n3_development_own n3_election_campaign_own n3_environment_pollution_own n3_farmer_protest_own n3_governance_own n3_party_politics_own n3_sports_culture_own n3_tribute_ceremony_own n3_welfare_own"
stata-mp -b do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] tweets_n3_own finished rc=$rc"
exit $rc

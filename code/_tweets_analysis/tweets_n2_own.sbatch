#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N tweets_n2_own
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

WRAPPER="logs/tweets_n2_own_wrapper.do"
cat > "$WRAPPER" <<EOF
clear all
set more off
global shell        "$PROJ_SHELL"
global job_name     "tweets_n2_own"
global outcome_list "n2_agriculture_own n2_development_own n2_election_campaign_own n2_environment_pollution_own n2_farmer_protest_own n2_governance_own n2_party_politics_own n2_sports_culture_own n2_tribute_ceremony_own n2_welfare_own"
do "$DOFILE_PATH"
EOF

echo "[$(date '+%F %T')] starting tweets_n2_own"
echo "  outcomes: n2_agriculture_own n2_development_own n2_election_campaign_own n2_environment_pollution_own n2_farmer_protest_own n2_governance_own n2_party_politics_own n2_sports_culture_own n2_tribute_ceremony_own n2_welfare_own"
stata-mp -b do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] tweets_n2_own finished rc=$rc"
exit $rc

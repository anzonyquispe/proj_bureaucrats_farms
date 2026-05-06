#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N tweets_neu_all
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

WRAPPER="logs/tweets_neu_all_wrapper.do"
cat > "$WRAPPER" <<EOF
clear all
set more off
global shell        "$PROJ_SHELL"
global job_name     "tweets_neu_all"
global outcome_list "neu_agriculture_all neu_development_all neu_election_campaign_all neu_environment_pollution_all neu_farmer_protest_all neu_governance_all neu_party_politics_all neu_sports_culture_all neu_tribute_ceremony_all neu_unclear_all neu_welfare_all"
do "$DOFILE_PATH"
EOF

echo "[$(date '+%F %T')] starting tweets_neu_all"
echo "  outcomes: neu_agriculture_all neu_development_all neu_election_campaign_all neu_environment_pollution_all neu_farmer_protest_all neu_governance_all neu_party_politics_all neu_sports_culture_all neu_tribute_ceremony_all neu_unclear_all neu_welfare_all"
stata-mp -b do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] tweets_neu_all finished rc=$rc"
exit $rc

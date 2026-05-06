#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N tweets_mix_own
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

WRAPPER="logs/tweets_mix_own_wrapper.do"
cat > "$WRAPPER" <<EOF
clear all
set more off
global shell        "$PROJ_SHELL"
global job_name     "tweets_mix_own"
global outcome_list "mix_agriculture_own mix_development_own mix_election_campaign_own mix_environment_pollution_own mix_farmer_protest_own mix_governance_own mix_party_politics_own mix_sports_culture_own mix_tribute_ceremony_own mix_unclear_own mix_welfare_own"
do "$DOFILE_PATH"
EOF

echo "[$(date '+%F %T')] starting tweets_mix_own"
echo "  outcomes: mix_agriculture_own mix_development_own mix_election_campaign_own mix_environment_pollution_own mix_farmer_protest_own mix_governance_own mix_party_politics_own mix_sports_culture_own mix_tribute_ceremony_own mix_unclear_own mix_welfare_own"
stata-mp -b do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] tweets_mix_own finished rc=$rc"
exit $rc

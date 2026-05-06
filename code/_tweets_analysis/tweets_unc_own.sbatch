#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N tweets_unc_own
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

WRAPPER="logs/tweets_unc_own_wrapper.do"
cat > "$WRAPPER" <<EOF
clear all
set more off
global shell        "$PROJ_SHELL"
global job_name     "tweets_unc_own"
global outcome_list "unc_agriculture_own unc_development_own unc_election_campaign_own unc_environment_pollution_own unc_farmer_protest_own unc_governance_own unc_party_politics_own unc_sports_culture_own unc_tribute_ceremony_own unc_unclear_own unc_welfare_own"
do "$DOFILE_PATH"
EOF

echo "[$(date '+%F %T')] starting tweets_unc_own"
echo "  outcomes: unc_agriculture_own unc_development_own unc_election_campaign_own unc_environment_pollution_own unc_farmer_protest_own unc_governance_own unc_party_politics_own unc_sports_culture_own unc_tribute_ceremony_own unc_unclear_own unc_welfare_own"
stata-mp -b do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] tweets_unc_own finished rc=$rc"
exit $rc

#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N tweets_mix_all
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

WRAPPER="logs/tweets_mix_all_wrapper.do"
cat > "$WRAPPER" <<EOF
clear all
set more off
global shell        "$PROJ_SHELL"
global job_name     "tweets_mix_all"
global outcome_list "mix_agriculture_all mix_development_all mix_election_campaign_all mix_environment_pollution_all mix_farmer_protest_all mix_governance_all mix_party_politics_all mix_sports_culture_all mix_tribute_ceremony_all mix_unclear_all mix_welfare_all"
do "$DOFILE_PATH"
EOF

echo "[$(date '+%F %T')] starting tweets_mix_all"
echo "  outcomes: mix_agriculture_all mix_development_all mix_election_campaign_all mix_environment_pollution_all mix_farmer_protest_all mix_governance_all mix_party_politics_all mix_sports_culture_all mix_tribute_ceremony_all mix_unclear_all mix_welfare_all"
stata-mp -b do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] tweets_mix_all finished rc=$rc"
exit $rc

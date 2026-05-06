#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N tweets_em_all
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

WRAPPER="logs/tweets_em_all_wrapper.do"
cat > "$WRAPPER" <<EOF
clear all
set more off
global shell        "$PROJ_SHELL"
global job_name     "tweets_em_all"
global outcome_list "em_positive_all em_negative_all em_neutral_all em_mixed_all em_unclear_all"
do "$DOFILE_PATH"
EOF

echo "[$(date '+%F %T')] starting tweets_em_all"
echo "  outcomes: em_positive_all em_negative_all em_neutral_all em_mixed_all em_unclear_all"
stata-mp -b do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] tweets_em_all finished rc=$rc"
exit $rc

#!/usr/bin/env bash
#$ -N pr_pes_event
#$ -q largemem
#$ -pe smp 5
#$ -cwd
#$ -j y
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/protest_province_election_switch/logs/protest_province_election_switch_event.log

set -euo pipefail

ROOT="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
CODE="${ROOT}/code/_stacked_downup_replication"
RUNNER="${CODE}/sbatch/run_dofile.sbatch"
BRANCH="${PIPELINE_BRANCH:-replication_data}"

if [[ ! -f "${RUNNER}" ]]; then
    echo "ERROR: runner missing: ${RUNNER}" >&2
    exit 66
fi

cd "${ROOT}"
exec 9>"${ROOT}.git-update.lock"
flock 9
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "ERROR: tracked files contain uncommitted changes." >&2
    git status --short --untracked-files=no >&2
    exit 1
fi
git fetch origin "${BRANCH}"
git switch "${BRANCH}"
git pull --ff-only origin "${BRANCH}"
echo "[$(date '+%F %T')] git HEAD=$(git rev-parse --short HEAD)"
flock -u 9

exec /bin/bash "${RUNNER}" \
    "exploratory_analysis/protest_province_election_switch/_protest_province_election_switch_event_study.do" \
    "${DATA_ROOT}" \
    "${CODE}" \
    "shell" \
    "none" \
    "is_rural" \
    "1/5" \
    "none" \
    "none" \
    "stacked_data_protest5km_province_election_switch" \
    "none" \
    "all"

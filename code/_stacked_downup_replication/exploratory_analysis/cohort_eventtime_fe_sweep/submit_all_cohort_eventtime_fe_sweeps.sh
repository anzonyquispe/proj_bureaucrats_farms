#!/usr/bin/env bash

# Submit one 1-core politician job and five 5-core protest jobs concurrently.
# Maximum simultaneous allocation: 26 cores.
set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/cohort_eventtime_fe_sweep"
POL_RUNNER="${DIR}/sbatch/run_politician_byprov_cohort_eventtime_fe_sweep.sbatch"
PR_RUNNER="${DIR}/sbatch/run_protest_never_cohort_eventtime_fe_chunk.sbatch"
mkdir -p "${DIR}/logs"
test -f "${POL_RUNNER}"
test -f "${PR_RUNNER}"

if ! command -v qsub >/dev/null 2>&1; then
    for settings in \
        /opt/sge/crc/common/settings.sh \
        /opt/sge/default/common/settings.sh \
        /etc/profile.d/sge.sh; do
        [[ -r "${settings}" ]] && source "${settings}" && break
    done
fi
if ! command -v qsub >/dev/null 2>&1; then
    for qsub_dir in /opt/sge/bin/lx-amd64 /opt/sge/bin; do
        [[ -x "${qsub_dir}/qsub" ]] && export PATH="${qsub_dir}:${PATH}" && break
    done
fi
command -v qsub >/dev/null 2>&1 || { echo "qsub is unavailable." >&2; exit 127; }

pol_job=$(qsub -terse -N pol_ctime_32 \
    -v "REPLICATION_REPO=${REPO}" "${POL_RUNNER}")
echo "Submitted politician FE 1/32 (1 core): ${pol_job}"

for chunk in 1/7 8/14 15/20 21/26 27/32; do
    tag="${chunk//\//_}"
    job=$(qsub -terse -N "pr_ct_${tag}" \
        -v "FE_LIST=${chunk},REPLICATION_REPO=${REPO}" "${PR_RUNNER}")
    echo "Submitted protest never-treated FE ${chunk} (5 cores): ${job}"
done

echo "Submitted six independent jobs: 1 politician x 1 core + 5 protest x 5 cores."
echo "Maximum simultaneous allocation: 26 cores."


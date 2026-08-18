#!/usr/bin/env bash

# Submit one independent three-core job for every audited missing protest DiD FE.
set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
RUNNER="${REPO}/code/_stacked_downup_replication/exploratory_analysis/cohort_eventtime_fe_sweep/sbatch/run_missing_protest_did_single_fe.sbatch"
test -f "${RUNNER}"

if ! command -v qsub >/dev/null 2>&1; then
    for settings in /opt/sge/crc/common/settings.sh /opt/sge/default/common/settings.sh /etc/profile.d/sge.sh; do
        [[ -r "${settings}" ]] && source "${settings}" && break
    done
fi
if ! command -v qsub >/dev/null 2>&1; then
    for qsub_dir in /opt/sge/bin/lx-amd64 /opt/sge/bin; do
        [[ -x "${qsub_dir}/qsub" ]] && export PATH="${qsub_dir}:${PATH}" && break
    done
fi
command -v qsub >/dev/null 2>&1 || { echo "qsub is unavailable." >&2; exit 127; }

jobs=()
for fe in 23 24 25 26 28 29 30 31 32; do
    tag=$(printf '%02d' "${fe}")
    job=$(qsub -terse -N "pr_ct_did_${tag}" \
        -v "FE_ID=${fe},REPLICATION_REPO=${REPO}" "${RUNNER}")
    jobs+=("${job%%.*}")
    echo "Submitted missing protest DiD FE ${fe}: ${job}"
done

echo "Submitted ${#jobs[@]} independent three-core jobs."
echo "Job IDs: ${jobs[*]}"

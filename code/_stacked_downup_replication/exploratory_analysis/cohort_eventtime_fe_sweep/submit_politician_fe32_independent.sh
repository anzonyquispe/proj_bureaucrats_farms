#!/usr/bin/env bash

# Submit 32 independent, one-core politician jobs. Each job estimates both the
# event study and the post x treatment x downup_ac_pop DiD interaction.
# No protest regressions are submitted by this launcher.
set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/cohort_eventtime_fe_sweep"
RUNNER="${ANALYSIS_DIR}/sbatch/run_politician_single_fe.sbatch"
SUBMIT_LOG="${ANALYSIS_DIR}/logs/politician_current/submission.log"

mkdir -p "$(dirname "${SUBMIT_LOG}")"
[[ -f "${RUNNER}" ]] || { echo "Missing runner: ${RUNNER}" >&2; exit 66; }

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

: > "${SUBMIT_LOG}"
echo "Submitting 32 politician jobs: event study + DiD interaction, one core each." | tee -a "${SUBMIT_LOG}"
for fe in $(seq 1 32); do
    tag=$(printf '%02d' "${fe}")
    job=$(qsub -terse \
        -N "pol_fe${tag}" \
        -v "FE_ID=${fe},REPLICATION_REPO=${REPO}" \
        "${RUNNER}")
    echo "FE ${tag}: ${job}" | tee -a "${SUBMIT_LOG}"
done

echo "Submitted 32 jobs. Maximum allocation if all run concurrently: 32 cores." | tee -a "${SUBMIT_LOG}"
echo "Logs: ${ANALYSIS_DIR}/logs/politician_current/politician_feNN.log" | tee -a "${SUBMIT_LOG}"

#!/usr/bin/env bash

# Submit FE 16,...,32 as 17 independent jobs. Every job runs both the event
# study and DiD. There are deliberately no dependency lanes: if the scheduler
# has capacity, all 17 jobs may run concurrently (17 x 5 = 85 cores).
set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/protest_original_controls_fe_sweep"
RUNNER="${ANALYSIS_DIR}/sbatch/run_protest_never_single_fe_both.sbatch"
POST="${ANALYSIS_DIR}/sbatch/postprocess_protest_original_controls.sbatch"
CANCEL_CONFLICTING_JOB="${CANCEL_CONFLICTING_JOB:-0}"

if ! command -v qsub >/dev/null 2>&1; then
    for settings in /opt/sge/crc/common/settings.sh /opt/sge/default/common/settings.sh /etc/profile.d/sge.sh; do
        [[ -r "${settings}" ]] && source "${settings}" && break
    done
fi
command -v qsub >/dev/null 2>&1 || { echo "qsub is unavailable." >&2; exit 127; }
[[ -f "${RUNNER}" ]] || { echo "Missing ${RUNNER}" >&2; exit 66; }
[[ -f "${POST}" ]] || { echo "Missing ${POST}" >&2; exit 66; }

# Do not allow the old 16/32 chunk or an earlier recovery to write the same
# outputs. qstat truncates names, so retrieve full job names with qstat -j.
SGE_USER="${USER:-$(id -un)}"
conflicting_ids=()
conflicting_names=()
while read -r job_id; do
    [[ -n "${job_id}" ]] || continue
    job_name=$(qstat -j "${job_id}" 2>/dev/null | awk -F: '/^job_name:/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
    case "${job_name}" in
        pr_never_16_32|pr_orig_post|rpr_post|prn_*|rpr_n_*)
            conflicting_ids+=("${job_id}")
            conflicting_names+=("${job_name}")
            ;;
    esac
done < <(qstat -u "${SGE_USER}" | awk 'NR > 2 && $1 ~ /^[0-9]+$/ {print $1}')

if (( ${#conflicting_ids[@]} > 0 )); then
    echo "Conflicting jobs that can write never-treated FE 16-32 outputs:" >&2
    for i in "${!conflicting_ids[@]}"; do
        echo "  ${conflicting_ids[$i]} ${conflicting_names[$i]}" >&2
    done
    if [[ "${CANCEL_CONFLICTING_JOB}" != "1" ]]; then
        echo "No jobs submitted. Rerun with CANCEL_CONFLICTING_JOB=1 to replace only those jobs." >&2
        exit 75
    fi
    qdel "${conflicting_ids[@]}"
    echo "Cancelled conflicting jobs; all completed output files were retained."
fi

job_ids=()
for fe in $(seq 16 32); do
    tag=$(printf '%02d' "${fe}")
    job=$(qsub -terse -N "prn_${tag}_both" \
        -v "RECOVERY_FE=${fe},REPLICATION_REPO=${REPO}" "${RUNNER}")
    job_id="${job%%.*}"
    job_ids+=("${job_id}")
    echo "Submitted never-treated FE=${fe}, event+DiD: ${job}"
done

hold=$(IFS=,; echo "${job_ids[*]}")
post=$(qsub -terse -N prn_post -hold_jid "${hold}" \
    -v "REPLICATION_REPO=${REPO},POSTPROCESS_CONTROLS=never" "${POST}")

echo "Submitted 17 independent estimation jobs (up to 85 cores concurrently)."
echo "Submitted never-treated CSV/plot postprocessing: ${post}"
echo "Postprocessing hold: ${hold}"

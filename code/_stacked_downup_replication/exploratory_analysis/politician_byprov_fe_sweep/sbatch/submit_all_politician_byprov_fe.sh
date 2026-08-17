#!/usr/bin/env bash
set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep"
RUNNER="${ANALYSIS_DIR}/sbatch/run_politician_byprov_fe.sbatch"
VALIDATOR="${ANALYSIS_DIR}/sbatch/validate_politician_byprov_fe.sbatch"
LOG_DIR="${ANALYSIS_DIR}/logs"
CANCEL_CONFLICTING_JOB="${CANCEL_CONFLICTING_JOB:-0}"

mkdir -p "${LOG_DIR}"
test -f "${RUNNER}"
test -f "${VALIDATOR}"

if ! command -v qsub >/dev/null 2>&1; then
    for settings in /opt/sge/crc/common/settings.sh /opt/sge/default/common/settings.sh /etc/profile.d/sge.sh; do
        [[ -r "${settings}" ]] && source "${settings}" && break
    done
fi
command -v qsub >/dev/null 2>&1 || { echo "qsub is unavailable." >&2; exit 127; }

# Prevent an old array or an earlier cohort_id rerun from writing the same files.
SGE_USER="${USER:-$(id -un)}"
conflicting_ids=()
conflicting_names=()
while read -r job_id; do
    [[ -n "${job_id}" ]] || continue
    job_name=$(qstat -j "${job_id}" 2>/dev/null | awk -F: '/^job_name:/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
    case "${job_name}" in
        polbp_did_fe|polbp_fe*|polbp_cid_*|polbp_validate)
            conflicting_ids+=("${job_id}")
            conflicting_names+=("${job_name}")
            ;;
    esac
done < <(qstat -u "${SGE_USER}" | awk 'NR > 2 && $1 ~ /^[0-9]+$/ {print $1}')

if (( ${#conflicting_ids[@]} > 0 )); then
    echo "Conflicting politician-by-province jobs:" >&2
    for i in "${!conflicting_ids[@]}"; do
        echo "  ${conflicting_ids[$i]} ${conflicting_names[$i]}" >&2
    done
    if [[ "${CANCEL_CONFLICTING_JOB}" != "1" ]]; then
        echo "No jobs submitted. Rerun with CANCEL_CONFLICTING_JOB=1 only if these jobs should be replaced." >&2
        exit 75
    fi
    qdel "${conflicting_ids[@]}"
fi

# These summaries and report sources are derived from the old FE CSVs. Remove
# them before submission so they cannot be mistaken for cohort_id results.
TABLE_DIR="${REPO}/tables/exploratory_analysis/politician_byprov_fe_sweep"
rm -f \
    "${TABLE_DIR}/politician_byprov_fe_sweep_coefficients.csv" \
    "${TABLE_DIR}/politician_byprov_fe_sweep_pre_post_averages.csv" \
    "${TABLE_DIR}/politician_byprov_fe_sweep_report.tex" \
    "${TABLE_DIR}/politician_byprov_fe_sweep_all.tex"

job_ids=()
for fe in $(seq 1 32); do
    tag=$(printf '%02d' "${fe}")
    job=$(qsub -terse -N "polbp_cid_${tag}" \
        -v "FE_ID=${fe},REPLACE_RESULTS=1,REPLICATION_REPO=${REPO}" \
        "${RUNNER}")
    job_id="${job%%.*}"
    job_ids+=("${job_id}")
    echo "Submitted corrected cohort_id FE ${fe}: ${job}"
done

hold=$(IFS=,; echo "${job_ids[*]}")
validation=$(qsub -terse -N polbp_validate -hold_jid "${hold}" \
    -v "REPLICATION_REPO=${REPO}" "${VALIDATOR}")

echo "Submitted 32 independent one-core jobs."
echo "Submitted held validation job: ${validation}"
echo "Validation hold: ${hold}"

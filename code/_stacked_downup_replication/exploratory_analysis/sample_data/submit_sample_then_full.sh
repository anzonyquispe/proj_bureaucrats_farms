#!/usr/bin/env bash

# Submit the random-sample smoke test.  The final held gate submits the full
# pipeline only after every expected sample result passes validation.
set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
BASE="${REPO}/code/_stacked_downup_replication/exploratory_analysis"
SAMPLE_BUILD="${BASE}/sample_data/build_exploratory_samples.sbatch"
SAMPLE_GATE="${BASE}/sample_data/validate_samples_and_submit_full.sbatch"
POL_RUNNER="${BASE}/politician_original_controls_fe_sweep/sbatch/run_politician_original_control_all32.sbatch"
POL_POST="${BASE}/politician_original_controls_fe_sweep/sbatch/postprocess_politician_original_controls.sbatch"
PR_RUNNER="${BASE}/protest_original_controls_fe_sweep/sbatch/run_protest_original_controls_chunk.sbatch"
PR_POST="${BASE}/protest_original_controls_fe_sweep/sbatch/postprocess_protest_original_controls.sbatch"

for file in "${SAMPLE_BUILD}" "${SAMPLE_GATE}" "${POL_RUNNER}" \
            "${POL_POST}" "${PR_RUNNER}" "${PR_POST}"; do
    if [[ ! -f "${file}" ]]; then
        echo "WARNING: required pipeline file is missing: ${file}" >&2
        exit 66
    fi
done
if ! command -v qsub >/dev/null 2>&1; then
    for settings in \
        /opt/sge/crc/common/settings.sh \
        /opt/sge/default/common/settings.sh \
        /etc/profile.d/sge.sh; do
        if [[ -r "${settings}" ]]; then
            # shellcheck disable=SC1090
            source "${settings}"
            break
        fi
    done
fi
if ! command -v qsub >/dev/null 2>&1; then
    for qsub_dir in /opt/sge/bin/lx-amd64 /opt/sge/bin; do
        [[ -x "${qsub_dir}/qsub" ]] && export PATH="${qsub_dir}:${PATH}" && break
    done
fi
if ! command -v qsub >/dev/null 2>&1; then
    echo "WARNING: qsub is unavailable; no jobs were submitted." >&2
    exit 127
fi

submit_job() {
    local result
    if ! result=$(qsub -terse "$@"); then
        echo "WARNING: qsub failed: qsub -terse $*" >&2
        exit 1
    fi
    printf '%s' "${result%%.*}"
}

build_env="REPLICATION_REPO=${REPO}"
[[ -n "${SAMPLE_SEED:-}" ]] && build_env+=",SAMPLE_SEED=${SAMPLE_SEED}"
build_args=(-N build_explore_samples -v "${build_env}")
[[ -n "${POLITICIAN_COHORTS:-}" ]] && {
    echo "WARNING: POLITICIAN_COHORTS is ignored; cohorts are selected randomly." >&2
}
build_id=$(submit_job "${build_args[@]}" "${SAMPLE_BUILD}")
echo "Submitted random-sample builder: ${build_id}"

pol_ids=()
pr_ids=()
for controls in never both notyet; do
    job_id=$(submit_job -N "pol_sample_${controls}" -hold_jid "${build_id}" \
        -v "CONTROL_SAMPLE=${controls},REPLICATION_REPO=${REPO},ANALYSIS_SAMPLE_SUFFIX=_sample" \
        "${POL_RUNNER}")
    pol_ids+=("${job_id}")
    echo "Submitted sample politician controls=${controls}: ${job_id}"

    for chunk in 1/15 16/32; do
        tag="${chunk//\//_}"
        job_id=$(submit_job -N "pr_sample_${controls}_${tag}" \
            -hold_jid "${build_id}" \
            -v "CONTROL_SAMPLE=${controls},FE_LIST=${chunk},REPLICATION_REPO=${REPO},ANALYSIS_SAMPLE_SUFFIX=_sample" \
            "${PR_RUNNER}")
        pr_ids+=("${job_id}")
        echo "Submitted sample protest controls=${controls}, FE=${chunk}: ${job_id}"
    done
done

pol_hold=$(IFS=,; echo "${pol_ids[*]}")
pr_hold=$(IFS=,; echo "${pr_ids[*]}")
pol_post_id=$(submit_job -N pol_sample_post -hold_jid "${pol_hold}" \
    -v "REPLICATION_REPO=${REPO},ANALYSIS_SAMPLE_SUFFIX=_sample" "${POL_POST}")
pr_post_id=$(submit_job -N pr_sample_post -hold_jid "${pr_hold}" \
    -v "REPLICATION_REPO=${REPO},ANALYSIS_SAMPLE_SUFFIX=_sample" "${PR_POST}")
echo "Submitted sample politician postprocessing: ${pol_post_id}"
echo "Submitted sample protest postprocessing: ${pr_post_id}"

gate_hold="${pol_post_id},${pr_post_id}"
gate_id=$(submit_job -N validate_explore_samples -hold_jid "${gate_hold}" \
    -v "REPLICATION_REPO=${REPO}" "${SAMPLE_GATE}")
echo "Submitted validation/full-submission gate: ${gate_id} (hold=${gate_hold})"
echo "The full nine-job pipeline will not be submitted unless the gate passes."

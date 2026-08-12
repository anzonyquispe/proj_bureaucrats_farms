#!/usr/bin/env bash

# Dynamically submit one job per unfinished FE. Never-treated recovery is the
# default and is submitted first. Existing chunk jobs must be cancelled (with
# explicit opt-in) to prevent two Stata processes writing the same .ster file.
set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
RECOVERY_CONTROLS="${RECOVERY_CONTROLS:-never}"
CANCEL_CHUNK_JOBS="${CANCEL_CHUNK_JOBS:-0}"
PROTEST_LANES="${RECOVERY_PROTEST_LANES:-6}"
POLITICIAN_LANES="${RECOVERY_POLITICIAN_LANES:-3}"
BASE="${REPO}/code/_stacked_downup_replication/exploratory_analysis"
POL_TABLES="${REPO}/tables/exploratory_analysis/politician_original_controls_fe_sweep"
PR_TABLES="${REPO}/tables/exploratory_analysis/protest_original_controls_fe_sweep"
POL_RUNNER="${BASE}/politician_original_controls_fe_sweep/sbatch/run_politician_original_single_fe.sbatch"
PR_RUNNER="${BASE}/protest_original_controls_fe_sweep/sbatch/run_protest_original_single_fe.sbatch"
POL_POST="${BASE}/politician_original_controls_fe_sweep/sbatch/postprocess_politician_original_controls.sbatch"
PR_POST="${BASE}/protest_original_controls_fe_sweep/sbatch/postprocess_protest_original_controls.sbatch"

if ! command -v qsub >/dev/null 2>&1; then
    for settings in /opt/sge/crc/common/settings.sh /opt/sge/default/common/settings.sh /etc/profile.d/sge.sh; do
        [[ -r "${settings}" ]] && source "${settings}" && break
    done
fi
command -v qsub >/dev/null 2>&1 || { echo "WARNING: qsub is unavailable." >&2; exit 127; }
for file in "${POL_RUNNER}" "${PR_RUNNER}" "${POL_POST}" "${PR_POST}"; do
    [[ -f "${file}" ]] || { echo "Missing required file: ${file}" >&2; exit 66; }
done

IFS=',' read -r -a controls_array <<< "${RECOVERY_CONTROLS}"
for control in "${controls_array[@]}"; do
    case "${control}" in never|both|notyet) ;; *) echo "Invalid RECOVERY_CONTROLS=${control}" >&2; exit 198 ;; esac
done
[[ "${PROTEST_LANES}" =~ ^[1-9][0-9]*$ ]] || { echo "RECOVERY_PROTEST_LANES must be positive." >&2; exit 198; }
[[ "${POLITICIAN_LANES}" =~ ^[1-9][0-9]*$ ]] || { echo "RECOVERY_POLITICIAN_LANES must be positive." >&2; exit 198; }

# Identify old chunk/recovery/postprocessing jobs that could collide with this
# recovery. qstat truncates names, so inspect each job with qstat -j.
conflicting_ids=()
conflicting_names=()
SGE_USER="${USER:-$(id -un)}"
while read -r job_id; do
    [[ -n "${job_id}" ]] || continue
    job_name=$(qstat -j "${job_id}" 2>/dev/null | awk -F: '/^job_name:/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
    conflict=0
    case "${job_name}" in pol_orig_post|pr_orig_post|rpol_post|rpr_post) conflict=1 ;; esac
    for control in "${controls_array[@]}"; do
        short_control=${control:0:1}
        case "${job_name}" in
            "pol_${control}_32"|"pr_${control}_1_15"|"pr_${control}_16_32"|\
            "rpol_${short_control}_"*|"rpr_${short_control}_"*) conflict=1 ;;
        esac
    done
    if (( conflict )); then
        conflicting_ids+=("${job_id}")
        conflicting_names+=("${job_name}")
    fi
done < <(qstat -u "${SGE_USER}" | awk 'NR > 2 && $1 ~ /^[0-9]+$/ {print $1}')

if (( ${#conflicting_ids[@]} > 0 )); then
    echo "Conflicting active jobs:" >&2
    for i in "${!conflicting_ids[@]}"; do
        echo "  ${conflicting_ids[$i]} ${conflicting_names[$i]}" >&2
    done
    if [[ "${CANCEL_CHUNK_JOBS}" != "1" ]]; then
        echo "WARNING: no recovery jobs submitted because concurrent writers are active." >&2
        echo "Rerun with CANCEL_CHUNK_JOBS=1 to cancel only the jobs listed above." >&2
        exit 75
    fi
    qdel "${conflicting_ids[@]}"
    echo "Cancelled conflicting chunk/postprocessing jobs. Existing completed .ster files were retained."
fi

submit_job() {
    local result
    result=$(qsub -terse "$@") || { echo "WARNING: qsub submission failed: $*" >&2; exit 1; }
    printf '%s' "${result%%.*}"
}

missing_stage() {
    local event_file="$1" did_file="$2"
    local event_missing=0 did_missing=0
    [[ -s "${event_file}" ]] || event_missing=1
    [[ -s "${did_file}" ]] || did_missing=1
    if (( event_missing && did_missing )); then echo both
    elif (( event_missing )); then echo event
    elif (( did_missing )); then echo did
    else echo complete
    fi
}

pol_ids=()
pr_ids=()
pol_lane_last=()
pr_lane_last=()
pol_index=0
pr_index=0
for control in "${controls_array[@]}"; do
    echo "Scanning controls=${control}"
    # Protest is submitted first, so never-treated recovery receives the
    # earliest queue submission times.
    for fe in $(seq 1 32); do
        tag=$(printf '%02d' "${fe}")
        stem="protest_original_fe${tag}_controls_${control}"
        stage=$(missing_stage \
            "${PR_TABLES}/${stem}_event_rural_acpop_all.ster" \
            "${PR_TABLES}/${stem}_did_interaction_rural_acpop_all.ster")
        [[ "${stage}" == complete ]] && continue
        short_control=${control:0:1}
        short_stage=${stage:0:1}
        lane=$((pr_index % PROTEST_LANES))
        submit_args=(-N "rpr_${short_control}_${tag}_${short_stage}")
        [[ -n "${pr_lane_last[$lane]:-}" ]] && submit_args+=(-hold_jid "${pr_lane_last[$lane]}")
        job_id=$(submit_job "${submit_args[@]}" \
            -v "RECOVERY_FE=${fe},CONTROL_SAMPLE=${control},ANALYSIS_STAGE=${stage},REPLICATION_REPO=${REPO}" \
            "${PR_RUNNER}")
        pr_ids+=("${job_id}")
        pr_lane_last[$lane]="${job_id}"
        pr_index=$((pr_index + 1))
        echo "Submitted protest controls=${control}, FE=${fe}, stage=${stage}, lane=$((lane + 1)): ${job_id}"
    done

    for fe in $(seq 1 32); do
        tag=$(printf '%02d' "${fe}")
        stem="politician_original_fe${tag}_controls_${control}"
        stage=$(missing_stage \
            "${POL_TABLES}/${stem}_event_rural_acpop_all.ster" \
            "${POL_TABLES}/${stem}_did_interaction_rural_acpop_all.ster")
        [[ "${stage}" == complete ]] && continue
        short_control=${control:0:1}
        short_stage=${stage:0:1}
        lane=$((pol_index % POLITICIAN_LANES))
        submit_args=(-N "rpol_${short_control}_${tag}_${short_stage}")
        [[ -n "${pol_lane_last[$lane]:-}" ]] && submit_args+=(-hold_jid "${pol_lane_last[$lane]}")
        job_id=$(submit_job "${submit_args[@]}" \
            -v "RECOVERY_FE=${fe},CONTROL_SAMPLE=${control},ANALYSIS_STAGE=${stage},REPLICATION_REPO=${REPO}" \
            "${POL_RUNNER}")
        pol_ids+=("${job_id}")
        pol_lane_last[$lane]="${job_id}"
        pol_index=$((pol_index + 1))
        echo "Submitted politician controls=${control}, FE=${fe}, stage=${stage}, lane=$((lane + 1)): ${job_id}"
    done
done

controls_token=$(IFS=:; echo "${controls_array[*]}")
if (( ${#pol_ids[@]} > 0 )); then
    pol_hold=$(IFS=,; echo "${pol_ids[*]}")
    pol_post_id=$(submit_job -N rpol_post -hold_jid "${pol_hold}" \
        -v "REPLICATION_REPO=${REPO},POSTPROCESS_CONTROLS=${controls_token}" "${POL_POST}")
else
    pol_post_id=$(submit_job -N rpol_post \
        -v "REPLICATION_REPO=${REPO},POSTPROCESS_CONTROLS=${controls_token}" "${POL_POST}")
fi
if (( ${#pr_ids[@]} > 0 )); then
    pr_hold=$(IFS=,; echo "${pr_ids[*]}")
    pr_post_id=$(submit_job -N rpr_post -hold_jid "${pr_hold}" \
        -v "REPLICATION_REPO=${REPO},POSTPROCESS_CONTROLS=${controls_token}" "${PR_POST}")
else
    pr_post_id=$(submit_job -N rpr_post \
        -v "REPLICATION_REPO=${REPO},POSTPROCESS_CONTROLS=${controls_token}" "${PR_POST}")
fi

echo "Recovery submitted: politician jobs=${#pol_ids[@]}, protest jobs=${#pr_ids[@]}"
echo "Concurrency caps: politician=${POLITICIAN_LANES} cores, protest=$((PROTEST_LANES * 5)) cores"
echo "Partial postprocessing: politician=${pol_post_id}, protest=${pr_post_id}"
echo "After all controls are complete, run submit_final_full_postprocessing.sh to build the six PDFs."

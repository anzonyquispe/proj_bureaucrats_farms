#!/usr/bin/env bash

# Submit nine estimation jobs concurrently:
#   - 3 politician jobs x 1 core (one job per controls, FE 1-32);
#   - 6 protest jobs x 5 cores (two FE chunks per controls).
# Total requested while all nine run: 33 cores.

set -euo pipefail
REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
POL_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep"
PR_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/protest_original_controls_fe_sweep"
POL_RUNNER="${POL_DIR}/sbatch/run_politician_original_control_all32.sbatch"
PR_RUNNER="${PR_DIR}/sbatch/run_protest_original_controls_chunk.sbatch"
POL_POST="${POL_DIR}/sbatch/postprocess_politician_original_controls.sbatch"
PR_POST="${PR_DIR}/sbatch/postprocess_protest_original_controls.sbatch"

mkdir -p "${POL_DIR}/logs" "${PR_DIR}/logs"
for file in "${POL_RUNNER}" "${PR_RUNNER}" "${POL_POST}" "${PR_POST}"; do
    test -f "${file}"
done

pol_ids=()
pr_ids=()
for controls in never both notyet; do
    job=$(qsub -terse -N "pol_${controls}_32" \
        -v "CONTROL_SAMPLE=${controls},REPLICATION_REPO=${REPO}" "${POL_RUNNER}")
    pol_ids+=("${job%%.*}")
    echo "Submitted politician controls=${controls}: ${job}"

    for chunk in 1/15 16/32; do
        tag="${chunk//\//_}"
        job=$(qsub -terse -N "pr_${controls}_${tag}" \
            -v "CONTROL_SAMPLE=${controls},FE_LIST=${chunk},REPLICATION_REPO=${REPO}" \
            "${PR_RUNNER}")
        pr_ids+=("${job%%.*}")
        echo "Submitted protest controls=${controls}, FE=${chunk}: ${job}"
    done
done

pol_hold=$(IFS=,; echo "${pol_ids[*]}")
pr_hold=$(IFS=,; echo "${pr_ids[*]}")
pol_post_job=$(qsub -terse -hold_jid "${pol_hold}" \
    -v "REPLICATION_REPO=${REPO}" "${POL_POST}")
pr_post_job=$(qsub -terse -hold_jid "${pr_hold}" \
    -v "REPLICATION_REPO=${REPO}" "${PR_POST}")

echo "Submitted politician postprocessing: ${pol_post_job} (hold=${pol_hold})"
echo "Submitted protest postprocessing: ${pr_post_job} (hold=${pr_hold})"
echo "Nine estimation jobs submitted: 3 x 1 core + 6 x 5 cores = 33 cores."

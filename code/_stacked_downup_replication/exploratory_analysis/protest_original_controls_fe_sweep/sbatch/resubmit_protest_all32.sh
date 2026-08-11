#!/usr/bin/env bash

# Resubmit only the six failed protest chunks:
# three control definitions x FE 1/15 and FE 16/32.
# Each job requests five cores and launches exactly one Stata process.
set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/protest_original_controls_fe_sweep"
RUNNER="${DIR}/sbatch/run_protest_original_controls_chunk.sbatch"
POST="${DIR}/sbatch/postprocess_protest_original_controls.sbatch"
mkdir -p "${DIR}/logs"
test -f "${RUNNER}"
test -f "${POST}"

ids=()
for controls in never both notyet; do
    for chunk in 1/15 16/32; do
        tag="${chunk//\//_}"
        job=$(qsub -terse -N "pr_${controls}_${tag}" \
            -v "CONTROL_SAMPLE=${controls},FE_LIST=${chunk},REPLICATION_REPO=${REPO}" \
            "${RUNNER}")
        ids+=("${job%%.*}")
        echo "Submitted protest controls=${controls}, FE=${chunk}: ${job}"
    done
done

hold=$(IFS=,; echo "${ids[*]}")
post=$(qsub -terse -hold_jid "${hold}" \
    -v "REPLICATION_REPO=${REPO}" "${POST}")
echo "Submitted protest postprocessing ${post}; hold=${hold}"
echo "Six five-core regression jobs submitted (30 active cores total)."

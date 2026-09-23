#!/usr/bin/env bash

# Resubmit only the three failed politician control-group jobs. Each scheduler
# job launches Stata once, imports once, and runs FE 1/32 in internal loops.
set -euo pipefail
REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep"
RUNNER="${DIR}/sbatch/run_politician_original_control_all32.sbatch"
POST="${DIR}/sbatch/postprocess_politician_original_controls.sbatch"
mkdir -p "${DIR}/logs"
test -f "${RUNNER}"
test -f "${POST}"

ids=()
for controls in never both notyet; do
    job=$(qsub -terse -N "pol_${controls}_32" \
        -v "CONTROL_SAMPLE=${controls},REPLICATION_REPO=${REPO}" "${RUNNER}")
    ids+=("${job%%.*}")
    echo "Submitted politician controls=${controls}: ${job}"
done
hold=$(IFS=,; echo "${ids[*]}")
post=$(qsub -terse -hold_jid "${hold}" \
    -v "REPLICATION_REPO=${REPO}" "${POST}")
echo "Submitted politician postprocessing ${post}; hold=${hold}"

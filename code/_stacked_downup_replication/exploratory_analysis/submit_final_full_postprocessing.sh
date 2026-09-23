#!/usr/bin/env bash

# Verify all 384 full-sample .ster files, then build all CSVs, plots and PDFs.
set -euo pipefail
REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
BASE="${REPO}/code/_stacked_downup_replication/exploratory_analysis"
POL_TABLES="${REPO}/tables/exploratory_analysis/politician_original_controls_fe_sweep"
PR_TABLES="${REPO}/tables/exploratory_analysis/protest_original_controls_fe_sweep"
POL_POST="${BASE}/politician_original_controls_fe_sweep/sbatch/postprocess_politician_original_controls.sbatch"
PR_POST="${BASE}/protest_original_controls_fe_sweep/sbatch/postprocess_protest_original_controls.sbatch"

if ! command -v qsub >/dev/null 2>&1; then
    [[ -r /opt/sge/crc/common/settings.sh ]] && source /opt/sge/crc/common/settings.sh
fi
command -v qsub >/dev/null 2>&1 || exit 127

missing=0
for control in never both notyet; do
    for fe in $(seq 1 32); do
        tag=$(printf '%02d' "${fe}")
        for file in \
            "${POL_TABLES}/politician_original_fe${tag}_controls_${control}_event_rural_acpop_all.ster" \
            "${POL_TABLES}/politician_original_fe${tag}_controls_${control}_did_interaction_rural_acpop_all.ster" \
            "${PR_TABLES}/protest_original_fe${tag}_controls_${control}_event_rural_acpop_all.ster" \
            "${PR_TABLES}/protest_original_fe${tag}_controls_${control}_did_interaction_rural_acpop_all.ster"; do
            [[ -s "${file}" ]] || { echo "Missing: ${file}" >&2; missing=$((missing + 1)); }
        done
    done
done
if (( missing > 0 )); then
    echo "WARNING: ${missing} full-sample STER files are missing; final reports were not submitted." >&2
    exit 1
fi

pol=$(qsub -terse -N pol_final_post -v "REPLICATION_REPO=${REPO},POSTPROCESS_CONTROLS=never:both:notyet" "${POL_POST}")
pr=$(qsub -terse -N pr_final_post -v "REPLICATION_REPO=${REPO},POSTPROCESS_CONTROLS=never:both:notyet" "${PR_POST}")
echo "Submitted final politician postprocessing: ${pol}"
echo "Submitted final protest postprocessing: ${pr}"

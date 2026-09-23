#!/usr/bin/env bash
#$ -N polbp_validate
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep"
TABLE_DIR="${REPO}/tables/exploratory_analysis/politician_byprov_fe_sweep"
FIGURE_DIR="${REPO}/figures/exploratory_analysis/politician_byprov_fe_sweep"
LOG_DIR="${ANALYSIS_DIR}/logs"
VALIDATION_LOG="${LOG_DIR}/validate_politician_byprov_cohort_id.log"
mkdir -p "${LOG_DIR}"
exec > >(tee "${VALIDATION_LOG}") 2>&1

missing=0
for fe in $(seq 1 32); do
    tag=$(printf '%02d' "${fe}")
    event_stem="${TABLE_DIR}/politician_byprov_fe${tag}_event_rural_acpop_all"
    did_stem="${TABLE_DIR}/politician_byprov_fe${tag}_did_interaction_rural_acpop_all"
    stata_log="${LOG_DIR}/_politician_byprov_fe_sweep_fe${tag}.log"
    for output in \
        "${event_stem}.ster" "${event_stem}.csv" \
        "${event_stem}_scalars.csv" \
        "${did_stem}.ster" "${did_stem}.csv" \
        "${did_stem}_scalars.csv" \
        "${FIGURE_DIR}/politician_byprov_fe${tag}_did_interaction_rural_acpop_all_1.png" \
        "${stata_log}"; do
        if [[ ! -s "${output}" ]]; then
            echo "MISSING OR EMPTY: ${output}" >&2
            missing=$((missing + 1))
        fi
    done
    if [[ -s "${stata_log}" ]] && ! grep -q "Validated province-election cohort_id groups" "${stata_log}"; then
        echo "COHORT_ID VALIDATION MARKER ABSENT: ${stata_log}" >&2
        missing=$((missing + 1))
    fi
    for scalar_file in "${event_stem}_scalars.csv" "${did_stem}_scalars.csv"; do
        if [[ -s "${scalar_file}" ]] && ! grep -q "cohort_id" "${scalar_file}"; then
            echo "COHORT_ID RESULT TAG ABSENT: ${scalar_file}" >&2
            missing=$((missing + 1))
        fi
    done
done

if (( missing > 0 )); then
    echo "FAILED: ${missing} corrected result or validation checks failed." >&2
    exit 1
fi

echo "PASS: all 32 FE event-study and DiD outputs use cohort_id and are nonempty."

# Replace the old baseline event-study figures using the repository's canonical
# plotting code and unchanged visual format.
if ! type module >/dev/null 2>&1; then
    for module_init in /etc/profile.d/modules.sh /usr/share/Modules/init/bash; do
        [[ -r "${module_init}" ]] && source "${module_init}" && break
    done
fi
if ! type module >/dev/null 2>&1; then
    if [[ "${FARMS_LOGIN_RETRY:-0}" == "1" ]]; then
        echo "The module command is unavailable even in a login shell." >&2
        exit 127
    fi
    export FARMS_LOGIN_RETRY=1
    exec /bin/bash -l "$0" "$@"
fi
module load R
RSCRIPT_BIN="${RSCRIPT_BIN:-Rscript}"
PLOT_SCRIPT="${REPO}/code/_stacked_downup_replication/plotting_event_studies.R"
"${RSCRIPT_BIN}" "${PLOT_SCRIPT}" \
    --root "${REPO}" --output-root "${REPO}" \
    --families politician_sweep --skip-honest

for fe in $(seq 1 32); do
    tag=$(printf '%02d' "${fe}")
    for figure in \
        "${FIGURE_DIR}/politician_byprov_fe${tag}_rural_acpop_all_baseline_ori.png" \
        "${FIGURE_DIR}/politician_byprov_fe${tag}_rural_acpop_all_baseline_rotated.png"; do
        [[ -s "${figure}" ]] || { echo "MISSING REPLACEMENT FIGURE: ${figure}" >&2; exit 1; }
    done
done

echo "PASS: all corrected baseline event-study and DiD figures were replaced."
echo "Rebuild the TeX report after pulling the corrected outputs locally."

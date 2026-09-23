#!/usr/bin/env bash
#$ -N validate_explore_samples
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

# This is the only gate allowed to launch the full nine-job pipeline.  SGE
# releases hold_jid dependencies even when a prerequisite exits nonzero, so the
# gate verifies the actual files rather than trusting scheduler completion.
set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
INTERMEDIATE="/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate"
SAMPLE_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/sample_data"
LOG_DIR="${SAMPLE_DIR}/logs"
mkdir -p "${LOG_DIR}"
exec > >(tee "${LOG_DIR}/validate_samples_and_submit_full.log") 2>&1

POL_TABLES="${REPO}/tables/exploratory_analysis/politician_original_controls_fe_sweep/sample"
POL_FIGURES="${REPO}/figures/exploratory_analysis/politician_original_controls_fe_sweep/sample"
PR_TABLES="${REPO}/tables/exploratory_analysis/protest_original_controls_fe_sweep/sample"
PR_FIGURES="${REPO}/figures/exploratory_analysis/protest_original_controls_fe_sweep/sample"
failures=0

warn() {
    echo "WARNING: $*" >&2
    failures=$((failures + 1))
}

require_file() {
    local path="$1"
    [[ -s "${path}" ]] || warn "missing or empty file: ${path}"
}

require_count() {
    local directory="$1"
    local pattern="$2"
    local expected="$3"
    local label="$4"
    local actual=0
    if [[ -d "${directory}" ]]; then
        actual=$(find "${directory}" -maxdepth 1 -type f -size +0c \
            -name "${pattern}" | wc -l)
        actual="${actual//[[:space:]]/}"
    fi
    if [[ "${actual}" != "${expected}" ]]; then
        warn "${label}: expected ${expected}, found ${actual} in ${directory}"
    else
        echo "PASS: ${label} (${actual})"
    fi
}

require_file "${INTERMEDIATE}/politicians_characteristics_sample.csv"
require_file "${INTERMEDIATE}/stacked_data_protest5km_sample.csv"

# Each analysis has 32 FE specifications x 3 control definitions.
for item in \
    "${POL_TABLES}|politician|${POL_FIGURES}" \
    "${PR_TABLES}|protest|${PR_FIGURES}"; do
    IFS='|' read -r table_dir label figure_dir <<< "${item}"
    require_count "${table_dir}" "*_event_rural_acpop_all.ster" 96 \
        "${label} event STER files"
    require_count "${table_dir}" "*_did_interaction_rural_acpop_all.ster" 96 \
        "${label} DiD STER files"
    require_count "${table_dir}" "*_event_rural_acpop_all.csv" 96 \
        "${label} event coefficient CSV files"
    require_count "${table_dir}" "*_event_rural_acpop_all_scalars.csv" 96 \
        "${label} event scalar CSV files"
    require_count "${table_dir}" "*_did_interaction_rural_acpop_all.csv" 96 \
        "${label} DiD coefficient CSV files"
    require_count "${table_dir}" "*_did_interaction_rural_acpop_all_scalars.csv" 96 \
        "${label} DiD scalar CSV files"
    require_count "${figure_dir}" \
        "*_did_interaction_rural_acpop_all_1.png" 96 \
        "${label} DiD interaction plots"
    require_count "${figure_dir}" "*_event_ori.png" 96 \
        "${label} original event-study plots"
    require_count "${figure_dir}" "*_event_rotated.png" 96 \
        "${label} rotated event-study plots"
done

require_file "${POL_TABLES}/politician_original_controls_coefficients.csv"
require_file "${POL_TABLES}/politician_original_controls_pre_post_averages.csv"
require_file "${PR_TABLES}/protest_original_controls_coefficients.csv"
require_file "${PR_TABLES}/protest_original_controls_pre_post_averages.csv"

if (( failures > 0 )); then
    echo "=================================================================" >&2
    echo "WARNING: RANDOM-SAMPLE PIPELINE FAILED ${failures} VALIDATION CHECK(S)." >&2
    echo "WARNING: FULL-SAMPLE JOBS WERE NOT SUBMITTED." >&2
    echo "Inspect the sample logs under each analysis logs/sample folder." >&2
    echo "=================================================================" >&2
    exit 1
fi

echo "All random-sample checks passed. Submitting the full pipeline."
unset ANALYSIS_SAMPLE_SUFFIX
FULL_LAUNCHER="${REPO}/code/_stacked_downup_replication/exploratory_analysis/submit_politician_and_protest_original_controls.sh"
if ! bash "${FULL_LAUNCHER}"; then
    echo "=================================================================" >&2
    echo "WARNING: SAMPLE VALIDATION PASSED, BUT FULL JOB SUBMISSION FAILED." >&2
    echo "Run ${FULL_LAUNCHER} manually after resolving the qsub error." >&2
    echo "=================================================================" >&2
    exit 1
fi
echo "Full-sample estimation and postprocessing jobs were submitted."

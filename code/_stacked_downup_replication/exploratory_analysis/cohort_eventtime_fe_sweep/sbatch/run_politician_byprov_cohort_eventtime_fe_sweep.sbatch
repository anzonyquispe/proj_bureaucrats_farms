#!/usr/bin/env bash
#$ -N pol_ctime_32
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

set -euo pipefail

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
ANALYSIS_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/cohort_eventtime_fe_sweep"
DOFILE="${ANALYSIS_DIR}/_politician_byprov_cohort_eventtime_fe_sweep.do"
POST_DOF="${ANALYSIS_DIR}/_postprocess_cohort_eventtime_fe_sweep.do"
PLOT_R="${ANALYSIS_DIR}/plot_cohort_eventtime_fe_sweep.R"
LOG_DIR="${ANALYSIS_DIR}/logs/politician"
WORK_DIR="${TMPDIR:-/tmp}/pol_ctime_${JOB_ID:-manual}"
TABLE_DIR="${REPO}/tables/exploratory_analysis/cohort_eventtime_fe_sweep"
FIGURE_DIR="${REPO}/figures/exploratory_analysis/cohort_eventtime_fe_sweep"
mkdir -p "${LOG_DIR}" "${WORK_DIR}" "${TABLE_DIR}" "${FIGURE_DIR}"
exec > >(tee "${LOG_DIR}/run_politician_byprov_cohort_eventtime_fe_sweep.log") 2>&1
cd "${WORK_DIR}"
ulimit -c 0 || true

for file in "${DOFILE}" "${POST_DOF}" "${PLOT_R}"; do
    [[ -f "${file}" ]] || { echo "Missing: ${file}" >&2; exit 66; }
done

if ! type module >/dev/null 2>&1; then
    for init in /etc/profile.d/modules.sh /usr/share/Modules/init/bash; do
        [[ -r "${init}" ]] && source "${init}" && break
    done
fi
if ! type module >/dev/null 2>&1; then
    [[ "${FARMS_LOGIN_RETRY:-0}" == "1" ]] && exit 127
    export FARMS_LOGIN_RETRY=1
    exec /bin/bash -l "$0" "$@"
fi
module purge 2>/dev/null || true
module load stata gcc
STATA_BIN="${STATA_BIN:-stata-mp}"
command -v "${STATA_BIN}" >/dev/null 2>&1 || exit 127

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1 JULIA_NUM_THREADS=1
export POL_CTIME_FE_LIST="1/32"
export ANALYSIS_SAMPLE_SUFFIX="${ANALYSIS_SAMPLE_SUFFIX:-}"

for fe in $(seq 1 32); do
    tag=$(printf '%02d' "${fe}")
    for kind in event did_interaction; do
        stem="${TABLE_DIR}/politician_byprov_cohorttime_fe${tag}_${kind}_rural_acpop_all"
        rm -f "${stem}.ster" "${stem}.csv" "${stem}_scalars.csv"
    done
    rm -f \
        "${FIGURE_DIR}/politician_byprov_cohorttime_fe${tag}_event_rural_acpop_all_ori.png" \
        "${FIGURE_DIR}/politician_byprov_cohorttime_fe${tag}_event_rural_acpop_all_rotated.png" \
        "${FIGURE_DIR}/politician_byprov_cohorttime_fe${tag}_did_interaction_rural_acpop_all_1.png"
done

echo "[$(date '+%F %T')] politician estimation: FE=1/32, cores=${NSLOTS:-1}"
"${STATA_BIN}" -b do "${DOFILE}"
cp "_politician_byprov_cohort_eventtime_fe_sweep.log" \
   "${LOG_DIR}/_politician_byprov_cohort_eventtime_fe_sweep.log"

echo "[$(date '+%F %T')] politician CSV and interaction-plot postprocessing"
"${STATA_BIN}" -b do "${POST_DOF}" politician "1/32"
POST_LOG=$(find . -maxdepth 1 -type f \
    -name '*postprocess_cohort_eventtime_fe_sweep.log' -print -quit)
if [[ -n "${POST_LOG}" ]]; then
    cp "${POST_LOG}" "${LOG_DIR}/_postprocess_cohort_eventtime_fe_sweep.log"
else
    echo "WARNING: Stata postprocessing log was not found; verified outputs determine success." >&2
fi

module load R/4.4.0/gcc/11.5.0
command -v Rscript >/dev/null 2>&1 || exit 127
Rscript "${PLOT_R}" --root "${REPO}" --analysis politician --first 1 --last 32 \
    > "${LOG_DIR}/plot_cohort_eventtime_fe_sweep.log" 2>&1

missing=0
for fe in $(seq 1 32); do
    tag=$(printf '%02d' "${fe}")
    for output in \
        "${TABLE_DIR}/politician_byprov_cohorttime_fe${tag}_event_rural_acpop_all.ster" \
        "${TABLE_DIR}/politician_byprov_cohorttime_fe${tag}_event_rural_acpop_all.csv" \
        "${TABLE_DIR}/politician_byprov_cohorttime_fe${tag}_did_interaction_rural_acpop_all.ster" \
        "${TABLE_DIR}/politician_byprov_cohorttime_fe${tag}_did_interaction_rural_acpop_all.csv" \
        "${FIGURE_DIR}/politician_byprov_cohorttime_fe${tag}_event_rural_acpop_all_ori.png" \
        "${FIGURE_DIR}/politician_byprov_cohorttime_fe${tag}_event_rural_acpop_all_rotated.png" \
        "${FIGURE_DIR}/politician_byprov_cohorttime_fe${tag}_did_interaction_rural_acpop_all_1.png"; do
        [[ -s "${output}" ]] || { echo "Missing: ${output}" >&2; missing=1; }
    done
done
(( missing == 0 )) || exit 1
echo "[$(date '+%F %T')] COMPLETED politician FE 1/32"

#!/usr/bin/env bash
#$ -N pr_ct_did
#$ -q largemem
#$ -pe smp 3
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

set -euo pipefail
: "${FE_ID:?FE_ID is required}"
case "${FE_ID}" in 23|24|25|26|28|29|30|31|32) ;; *)
    echo "FE_ID=${FE_ID} is not in the audited missing DiD set." >&2
    exit 198
esac

REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/cohort_eventtime_fe_sweep"
DOFILE="${DIR}/_protest_never_cohort_eventtime_fe_sweep.do"
POST_DOF="${DIR}/_postprocess_cohort_eventtime_fe_sweep.do"
PLOT_R="${DIR}/plot_cohort_eventtime_fe_sweep.R"
TAG=$(printf '%02d' "${FE_ID}")
LOG_DIR="${DIR}/logs/protest_did_fe${TAG}"
WORK_DIR="${TMPDIR:-/tmp}/pr_ct_did_${JOB_ID:-manual}_${TAG}"
TABLE_DIR="${REPO}/tables/exploratory_analysis/cohort_eventtime_fe_sweep"
FIGURE_DIR="${REPO}/figures/exploratory_analysis/cohort_eventtime_fe_sweep"
mkdir -p "${LOG_DIR}" "${WORK_DIR}" "${TABLE_DIR}" "${FIGURE_DIR}"
exec > >(tee "${LOG_DIR}/run_missing_protest_did_single_fe.log") 2>&1
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

export OMP_NUM_THREADS=3 OPENBLAS_NUM_THREADS=3 MKL_NUM_THREADS=3
export NUMEXPR_NUM_THREADS=3 JULIA_NUM_THREADS=3
export STATA_PROCESSORS=3
export PROTEST_CTIME_FE_LIST="${FE_ID}"
export ANALYSIS_STAGE="did"
export ANALYSIS_SAMPLE_SUFFIX="${ANALYSIS_SAMPLE_SUFFIX:-}"

DID_STEM="${TABLE_DIR}/protest_never_cohorttime_fe${TAG}_did_interaction_rural_acpop_all"
EVENT_STEM="${TABLE_DIR}/protest_never_cohorttime_fe${TAG}_event_rural_acpop_all"
INTERACTION_FIG="${FIGURE_DIR}/protest_never_cohorttime_fe${TAG}_did_interaction_rural_acpop_all_1.png"
rm -f "${DID_STEM}.ster" "${DID_STEM}.csv" "${DID_STEM}_scalars.csv" "${INTERACTION_FIG}"
[[ -s "${EVENT_STEM}.ster" ]] || { echo "Missing prerequisite: ${EVENT_STEM}.ster" >&2; exit 66; }

echo "[$(date '+%F %T')] protest missing DiD recovery: FE=${FE_ID}, cores=${NSLOTS:-3}"
"${STATA_BIN}" -b do "${DOFILE}"
cp "_protest_never_cohort_eventtime_fe_sweep.log" \
   "${LOG_DIR}/_protest_never_cohort_eventtime_fe_sweep.log"

"${STATA_BIN}" -b do "${POST_DOF}" protest "${FE_ID}"
POST_LOG=$(find . -maxdepth 1 -type f \
    -name '*postprocess_cohort_eventtime_fe_sweep.log' -print -quit)
if [[ -n "${POST_LOG}" ]]; then
    cp "${POST_LOG}" "${LOG_DIR}/_postprocess_cohort_eventtime_fe_sweep.log"
else
    echo "WARNING: Stata postprocessing log was not found; verified outputs determine success." >&2
fi

module load R/4.4.0/gcc/11.5.0
Rscript "${PLOT_R}" --root "${REPO}" --analysis protest \
    --first "${FE_ID}" --last "${FE_ID}" \
    > "${LOG_DIR}/plot_cohort_eventtime_fe_sweep.log" 2>&1

for output in \
    "${DID_STEM}.ster" "${DID_STEM}.csv" "${DID_STEM}_scalars.csv" \
    "${EVENT_STEM}.csv" "${EVENT_STEM}_scalars.csv" \
    "${INTERACTION_FIG}" \
    "${FIGURE_DIR}/protest_never_cohorttime_fe${TAG}_event_rural_acpop_all_ori.png" \
    "${FIGURE_DIR}/protest_never_cohorttime_fe${TAG}_event_rural_acpop_all_rotated.png"; do
    [[ -s "${output}" ]] || { echo "Missing: ${output}" >&2; exit 1; }
done
echo "[$(date '+%F %T')] COMPLETED protest DiD recovery FE=${FE_ID}"

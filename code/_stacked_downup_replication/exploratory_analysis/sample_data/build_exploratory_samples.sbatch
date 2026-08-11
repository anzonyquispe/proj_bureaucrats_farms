#!/usr/bin/env bash
#$ -N build_explore_samples
#$ -q largemem
#$ -pe smp 4
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

set -euo pipefail
REPO="${REPLICATION_REPO:-/users/aquisper/proj_bureaucrats_farms}"
INTERMEDIATE="/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate"
SCRIPT="${REPO}/code/_stacked_downup_replication/exploratory_analysis/sample_data/build_exploratory_samples.py"
PYTHON="${PYTHON_BIN:-/groups/sgulzar/india_forest_land/downup_geo/bin/python}"
LOG_DIR="${REPO}/code/_stacked_downup_replication/exploratory_analysis/sample_data/logs"
mkdir -p "${LOG_DIR}"
exec > >(tee "${LOG_DIR}/build_exploratory_samples.log") 2>&1

# A sample run must never pass because outputs from an earlier sample are still
# present.  Only the four exact sample-output directories are cleared.
sample_dirs=(
  "${REPO}/tables/exploratory_analysis/politician_original_controls_fe_sweep/sample"
  "${REPO}/figures/exploratory_analysis/politician_original_controls_fe_sweep/sample"
  "${REPO}/tables/exploratory_analysis/protest_original_controls_fe_sweep/sample"
  "${REPO}/figures/exploratory_analysis/protest_original_controls_fe_sweep/sample"
)
for sample_dir in "${sample_dirs[@]}"; do
  case "${sample_dir}" in
    "${REPO}/tables/exploratory_analysis/"*/sample|\
    "${REPO}/figures/exploratory_analysis/"*/sample) ;;
    *)
      echo "Refusing to clear unexpected path: ${sample_dir}" >&2
      exit 64
      ;;
  esac
  mkdir -p "${sample_dir}"
  find "${sample_dir}" -mindepth 1 -maxdepth 1 -delete
done

# Remove the two exact sample inputs as well, so a failed rebuild cannot fall
# back to a stale CSV from an earlier run.
rm -f \
  "${INTERMEDIATE}/politicians_characteristics_sample.csv" \
  "${INTERMEDIATE}/stacked_data_protest5km_sample.csv"

SAMPLE_SEED="${SAMPLE_SEED:-$(date +%s)}"
echo "[$(date '+%F %T')] random sample seed=${SAMPLE_SEED}"

args=(
  --intermediate "${INTERMEDIATE}"
  --seed "${SAMPLE_SEED}"
  --threads "${NSLOTS:-4}"
  --memory-limit "24GB"
)
if [[ -n "${POLITICIAN_COHORTS:-}" ]]; then
  args+=(--politician-cohorts "${POLITICIAN_COHORTS}")
fi
"${PYTHON}" "${SCRIPT}" "${args[@]}"

#!/usr/bin/env bash
# Defaults to sampled inputs. Set SAMPLE=none only after sample validation.

set -euo pipefail

REPLICATION_CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
INTERMEDIATE="${INTERMEDIATE:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate}"

export SAMPLE="${SAMPLE:-_sample}"
export ANALYSIS_SUBSAMPLE="rice_high"
export OUTPUT_TAG="_ricehigh"
export JOB_PREFIX="rh_"

echo "Rice-high exploratory analysis"
echo "Input sample suffix: ${SAMPLE}"
echo "Output tag: ${OUTPUT_TAG}"

required_samples=(
  combined_dt_sample.csv
  combined_dt_pop_sample.csv
  politicians_characteristics_byprov_sample.csv
  stacked_data_protest5km_election_sameterm_sample.csv
  stacked_downup_13kmpl_sample.csv
  stacked_downup_neigh_sample.csv
)
if [[ "${SAMPLE}" == "_sample" ]]; then
  for file in "${required_samples[@]}"; do
    path="${INTERMEDIATE}/${file}"
    if [[ ! -f "${path}" ]]; then
      echo "ERROR: missing sample input: ${path}" >&2
      exit 66
    fi
    if ! head -n 1 "${path}" | grep -q 'rice_prod_aclvl_ahigh'; then
      echo "ERROR: ${path} lacks rice_prod_aclvl_ahigh." >&2
      echo "Rebuild the corresponding stack/sample from 0_master_dataset first." >&2
      exit 65
    fi
  done
fi

exec bash "${REPLICATION_CODE}/sbatch/submit_estimations_only.sh"

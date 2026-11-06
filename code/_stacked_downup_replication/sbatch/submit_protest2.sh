#!/usr/bin/env bash
# Submit every protest regression on the Gemini-based protest2 data
# (stacked_data_protest2_5km_election_sameterm.csv, built by
# build_protest2_datasets.sbatch). _protest_definition.do tags every output
# _protest2, so the paper's keyword-rule estimates are never overwritten.
# Usage, from the repository clone on the cluster:
#   bash code/_stacked_downup_replication/sbatch/submit_protest2.sh
# Overrides: REPLICATION_ROOT, REPLICATION_CODE, SGE_QUEUE (default long).

set -euo pipefail

export REPLICATION_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
export REPLICATION_CODE="${REPLICATION_CODE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export SGE_QUEUE="${SGE_QUEUE:-long}"
export PROTEST_STACK="stacked_data_protest2_5km"

input="${REPLICATION_ROOT}/data_output/intermediate/${PROTEST_STACK}_election_sameterm.csv"
clusters="${REPLICATION_ROOT}/data_output/intermediate/grid_month_ac_area_tr_protest2.dta"
for file in "${input}" "${clusters}"; do
  [[ -f "${file}" ]] || { echo "ERROR: missing ${file}; run build_protest2_datasets.sbatch first." >&2; exit 66; }
done

# Main-text and appendix protest jobs, with the dependencies of submit_all.sh.
ONLY="protest_did_pop protest_did_area descriptives_protest protest_event protest_inter_area protest_inter_pop" \
  bash "${REPLICATION_CODE}/sbatch/submit_all.sh"

# The two remaining protest regressions are not part of submit_all.sh.
submit_appendix() {
  local name="$1" dofile="$2" fe_list="$3"
  local id
  id=$(qsub -terse -V -N "${name}" -j y -o /dev/null -q "${SGE_QUEUE}" -pe smp 3 \
    "${REPLICATION_CODE}/sbatch/run_dofile.sbatch" "${dofile}" \
    "${REPLICATION_ROOT}" "${REPLICATION_CODE}" shell none is_rural "${fe_list}" \
    none none "${PROTEST_STACK}" none all all)
  echo "Submitted ${name}: ${id}"
}
submit_appendix protest2_app12 _app_12_protest_5km_fe_did.do 3
submit_appendix protest2_app13_rice _app_13_protest_5km_fe12_did_ricemods.do 0/3

# Side-by-side table, released when every job above has left the queue.
held="protest_did_pop,protest_did_area,descriptives_protest,protest_event"
held+=",protest_inter_area,protest_inter_pop,protest2_app12,protest2_app13_rice"
id=$(qsub -terse -V -N protest2_compare -j y -o /dev/null -q "${SGE_QUEUE}" \
  -hold_jid "${held}" "${REPLICATION_CODE}/sbatch/run_dofile.sbatch" _compare_protest2.do \
  "${REPLICATION_ROOT}" "${REPLICATION_CODE}" shell none is_rural 1 none none none none all all)
echo "Submitted protest2_compare (after all protest2 jobs): ${id}"
echo "Comparison: ${REPLICATION_CODE}/../../tables/protest2_comparison.csv"
echo "Logs: ${REPLICATION_CODE}/logs/<job-name>_<job-id>.stata.log"

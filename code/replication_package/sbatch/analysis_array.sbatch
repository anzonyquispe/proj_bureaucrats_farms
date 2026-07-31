#!/usr/bin/env bash
#SBATCH --job-name=farms-analysis
#SBATCH --array=0-29
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --output=logs/analysis_%A_%a.out
#SBATCH --error=logs/analysis_%A_%a.err

set -euo pipefail

REPLICATION_CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/replication_package}"
REPLICATION_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
STATA_BIN="${STATA_BIN:-stata-mp}"
LOCATION="${LOCATION:-shell}"
SAMPLE="${SAMPLE:-none}"
RURAL_VAR="${RURAL_VAR:-is_rural_area}"
TABLE_FE_LIST="${FE_LIST:-1/3}"
EVENT_FE_LIST="${EVENT_FE_LIST:-1}"

analysis=(
  main_did_area.do
  bureaucrat_politician_area.do
  treatment_definitions_area.do
  alternative_outcomes_area.do
  by_year_area.do
  by_state_area.do
  protest_did_area.do
  protest_downup_area.do
  politician_characteristics_area.do
  main_did_acpop_stacked.do
  bureaucrat_politician_acpop_stacked.do
  alternative_outcomes_acpop_stacked.do
  by_year_acpop_stacked.do
  by_state_acpop_stacked.do
  treatment_definitions_acpop.do
  protest_downup_acpop.do
  politician_characteristics_acpop.do
  placebo_13km.do
  stacked_event_study_5pre_area.do
  stacked_event_study_5pre_acpop.do
  main_event_study_area.do
  politician_event_study_area.do
  protest_event_study_area.do
  politician_event_study_acpop.do
  protest_event_study_acpop.do
  protest_interaction_acpop.do
  politician_interaction_acpop.do
  protest_interaction_area.do
  politician_interaction_area.do
  neighbour_effects.do
)

suffix=(
  none none none none none none none none none
  _acpop_stacked _acpop_stacked _acpop_stacked _acpop_stacked _acpop_stacked
  _acpop _acpop _acpop
  none none none none none none
  _acpop _acpop _acpop _acpop
  none none none
)

fe_values=(
  "${TABLE_FE_LIST}" "${TABLE_FE_LIST}" "${TABLE_FE_LIST}" "${TABLE_FE_LIST}"
  "${TABLE_FE_LIST}" "${TABLE_FE_LIST}" "${TABLE_FE_LIST}" "${TABLE_FE_LIST}"
  "${TABLE_FE_LIST}" "${TABLE_FE_LIST}" "${TABLE_FE_LIST}" "${TABLE_FE_LIST}"
  "${TABLE_FE_LIST}" "${TABLE_FE_LIST}" "${TABLE_FE_LIST}" "${TABLE_FE_LIST}"
  "${TABLE_FE_LIST}" "${TABLE_FE_LIST}"
  "${EVENT_FE_LIST}" "${EVENT_FE_LIST}" "${EVENT_FE_LIST}" "${EVENT_FE_LIST}"
  "${EVENT_FE_LIST}" "${EVENT_FE_LIST}" "${EVENT_FE_LIST}"
  "${TABLE_FE_LIST}" "${TABLE_FE_LIST}" "${TABLE_FE_LIST}" "${TABLE_FE_LIST}"
  "${TABLE_FE_LIST}"
)

cd "${REPLICATION_CODE}"
"${STATA_BIN}" -b do sbatch/run_analysis.do \
  "${analysis[$SLURM_ARRAY_TASK_ID]}" "${LOCATION}" "${SAMPLE}" \
  "${RURAL_VAR}" "${fe_values[$SLURM_ARRAY_TASK_ID]}" "${suffix[$SLURM_ARRAY_TASK_ID]}" \
  "${REPLICATION_ROOT}" "${REPLICATION_CODE}"

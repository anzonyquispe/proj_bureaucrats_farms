********************************************************************************
* Master Stata workflow for all active main.tex outputs with identified code
********************************************************************************

version 17
set more off

do "config.do"
adopath ++ "${code}/tools"
quietly do "${code}/tools/estsave_csv.ado"
quietly do "${code}/tools/estload_csv.ado"

capture log close _all
log using "${code}/logs/master${sample}.log", replace text

display "Replication root: ${root}"
display "Rural classifier: ${is_rural_var}"
display "Sample suffix: ${sample}"

* Area-based main and appendix tables.
local table_fe_list "$fe_list"
global ster_suffix ""
do "${code}/analysis/main_did_area.do"
do "${code}/analysis/bureaucrat_politician_area.do"
do "${code}/analysis/treatment_definitions_area.do"
do "${code}/analysis/alternative_outcomes_area.do"
do "${code}/analysis/by_year_area.do"
do "${code}/analysis/by_state_area.do"
do "${code}/analysis/protest_did_area.do"
do "${code}/analysis/protest_downup_area.do"
do "${code}/analysis/politician_characteristics_area.do"

* Population-weighted/stacked versions. These authoritative files come from
* _stacked_downup_replication where available.
global ster_suffix "_acpop_stacked"
do "${code}/analysis/main_did_acpop_stacked.do"
do "${code}/analysis/bureaucrat_politician_acpop_stacked.do"
do "${code}/analysis/alternative_outcomes_acpop_stacked.do"
do "${code}/analysis/by_year_acpop_stacked.do"
do "${code}/analysis/by_state_acpop_stacked.do"

global ster_suffix "_acpop"
do "${code}/analysis/treatment_definitions_acpop.do"
do "${code}/analysis/protest_downup_acpop.do"
do "${code}/analysis/politician_characteristics_acpop.do"

* Placebo and event-study inputs.
global ster_suffix ""
do "${code}/analysis/placebo_13km.do"

* Plotting code expects one estimate per moderator, using FE specification 1.
global fe_list "1"
do "${code}/analysis/stacked_event_study_5pre_area.do"
do "${code}/analysis/stacked_event_study_5pre_acpop.do"
do "${code}/analysis/main_event_study_area.do"
do "${code}/analysis/politician_event_study_area.do"
do "${code}/analysis/protest_event_study_area.do"

global ster_suffix "_acpop"
do "${code}/analysis/politician_event_study_acpop.do"
do "${code}/analysis/protest_event_study_acpop.do"
do "${code}/analysis/protest_interaction_acpop.do"
do "${code}/analysis/politician_interaction_acpop.do"

global ster_suffix ""
do "${code}/analysis/protest_interaction_area.do"
do "${code}/analysis/politician_interaction_area.do"
do "${code}/analysis/neighbour_effects.do"

* Post-estimation Stata products.
do "${code}/generate_interaction_plots.do"
do "${code}/generate_neighbour_plot.do"
do "${code}/generate_tables.do"

display "Stata replication completed: $S_DATE $S_TIME"
log close

********************************************************************************

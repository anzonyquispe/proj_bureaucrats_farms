********************************************************************************
* Local postprocessing for the current 32-FE politician rerun.
*
* Inputs: 32 event-study STER files and 32 DiD-interaction STER files.
* Outputs: event/DiD CSVs and politician DiD-interaction PNGs.
* No analysis dataset is loaded and no regression is re-estimated.
********************************************************************************
version 18
clear all
set more off
set linesize 255

local root `"`c(pwd)'"'
local root : subinstr local root "\" "/", all
local code "`root'/code/_stacked_downup_replication"
local tables "`root'/tables/exploratory_analysis/cohort_eventtime_fe_sweep"
local figures "`root'/figures/exploratory_analysis/cohort_eventtime_fe_sweep"
local analysis_dir "`code'/exploratory_analysis/cohort_eventtime_fe_sweep"

confirm file "`root'/AGENTS.md"
capture mkdir "`figures'"
capture mkdir "`analysis_dir'/logs"
capture log close politician_postprocess
log using "`analysis_dir'/logs/postprocess_politician_current_local.log", ///
    text replace name(politician_postprocess)

capture program drop estsave_csv
quietly do "`code'/estsave_csv.ado"
quietly do "`code'/interaction_graph.ado"

forvalues fe = 1/32 {
    local tag : display %02.0f `fe'
    local tag = strtrim("`tag'")
    local prefix "politician_byprov_cohorttime_fe`tag'"
    local event "`tables'/`prefix'_event_rural_acpop_all"
    local did "`tables'/`prefix'_did_interaction_rural_acpop_all"

    confirm file "`event'.ster"
    est clear
    estread using "`event'.ster"
    quietly estimates dir
    local names `r(names)'
    estsave_csv `names' using "`event'.csv", replace
    confirm file "`event'.csv"
    confirm file "`event'_scalars.csv"

    confirm file "`did'.ster"
    est clear
    estread using "`did'.ster"
    quietly estimates dir
    local names `r(names)'
    estsave_csv `names' using "`did'.csv", replace
    confirm file "`did'.csv"
    confirm file "`did'_scalars.csv"

    est clear
    interaction_graph using "`did'.ster", estimates(1) ///
        output("`figures'/`prefix'_did_interaction_rural_acpop_all") ///
        type(politician) modvar(downup_ac_pop)
    confirm file "`figures'/`prefix'_did_interaction_rural_acpop_all_1.png"
    display as result "POSTPROCESSED POLITICIAN FE `tag'"
}

display as result "COMPLETED current politician FE01-FE32 postprocessing"
log close politician_postprocess

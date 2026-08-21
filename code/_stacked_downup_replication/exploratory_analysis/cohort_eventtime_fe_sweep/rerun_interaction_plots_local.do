********************************************************************************
* Recreate all cohort-event-time interaction plots from saved STER estimates.
* Run from the repository root. The log records every plotted linear combination.
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
capture mkdir "`analysis_dir'/logs"
capture log close interaction_plots
log using "`analysis_dir'/logs/interaction_plots_rerun.log", ///
    text replace name(interaction_plots)

quietly do "`code'/interaction_graph.ado"

foreach analysis in politician protest {
    forvalues fe = 1/32 {
        local tag : display %02.0f `fe'
        local tag = strtrim("`tag'")

        if "`analysis'" == "politician" {
            local prefix "politician_byprov_cohorttime_fe`tag'"
            local graph_type "politician"
        }
        else {
            local prefix "protest_never_cohorttime_fe`tag'"
            local graph_type "protest"
        }

        local input "`tables'/`prefix'_did_interaction_rural_acpop_all.ster"
        local output "`figures'/`prefix'_did_interaction_rural_acpop_all"
        confirm file "`input'"

        est clear
        interaction_graph using "`input'", estimates(1) ///
            output("`output'") type(`graph_type') modvar(downup_ac_pop)
        confirm file "`output'_1.png"
    }
}

display as result "COMPLETED 64 interaction plots: politician and protest FE01-FE32"
log close interaction_plots

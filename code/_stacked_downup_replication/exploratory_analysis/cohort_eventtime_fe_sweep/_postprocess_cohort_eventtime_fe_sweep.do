********************************************************************************
* Export CSVs and interaction plots from cohort-event-time FE sweep STER files.
* No analysis dataset is loaded. This runs only after all assigned regressions.
********************************************************************************
version 17
clear all
set more off

args analysis_arg fe_arg
if !inlist("`analysis_arg'", "politician", "protest") {
    display as error "First argument must be politician or protest."
    exit 198
}
if "`fe_arg'" == "" {
    display as error "Second argument must be an FE numlist."
    exit 198
}
foreach fe of numlist `fe_arg' {
    if !inrange(`fe', 1, 32) exit 198
}

global code "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
global tables "${code}/../../tables/exploratory_analysis/cohort_eventtime_fe_sweep"
global figures "${code}/../../figures/exploratory_analysis/cohort_eventtime_fe_sweep"
capture mkdir "${code}/../../figures/exploratory_analysis"
capture mkdir "${figures}"

capture program drop estsave_csv
quietly do "${code}/estsave_csv.ado"
quietly do "${code}/interaction_graph.ado"

foreach fe of numlist `fe_arg' {
    local tag : display %02.0f `fe'
    local tag = strtrim("`tag'")
    if "`analysis_arg'" == "politician" {
        local prefix "politician_byprov_cohorttime_fe`tag'"
        local graph_type "politician"
    }
    else {
        local prefix "protest_never_cohorttime_fe`tag'"
        local graph_type "protest"
    }

    local event "${tables}/`prefix'_event_rural_acpop_all"
    confirm file "`event'.ster"
    est clear
    estread using "`event'.ster"
    quietly estimates dir
    local names `r(names)'
    estsave_csv `names' using "`event'.csv", replace
    confirm file "`event'.csv"
    confirm file "`event'_scalars.csv"

    local did "${tables}/`prefix'_did_interaction_rural_acpop_all"
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
        output("${figures}/`prefix'_did_interaction_rural_acpop_all") ///
        type(`graph_type') modvar(downup_ac_pop)
    confirm file "${figures}/`prefix'_did_interaction_rural_acpop_all_1.png"
}

display as result "COMPLETED `analysis_arg' postprocessing: FE `fe_arg'"


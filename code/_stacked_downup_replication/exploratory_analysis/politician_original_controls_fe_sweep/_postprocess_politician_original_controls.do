********************************************************************************
* Read politician .ster files only; export CSVs and DiD interaction plots.
* No analysis dataset is loaded, so estsave_csv may safely replace memory.
********************************************************************************
version 17
clear all
set more off
global root "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
global code "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
local sample_env : environment ANALYSIS_SAMPLE_SUFFIX
global sample "`sample_env'"
global tables "${code}/../../tables/exploratory_analysis/politician_original_controls_fe_sweep"
global figures "${code}/../../figures/exploratory_analysis/politician_original_controls_fe_sweep"
if "${sample}" == "_sample" {
    global tables "${tables}/sample"
    global figures "${figures}/sample"
}
capture mkdir "${figures}"
capture program drop estsave_csv
quietly do "${code}/estsave_csv.ado"
quietly do "${code}/interaction_graph.ado"

foreach controls in never both notyet {
    forvalues fe = 1/32 {
        local tag : display %02.0f `fe'
        local tag = strtrim("`tag'")
        local prefix "politician_original_fe`tag'_controls_`controls'"

        local event "${tables}/`prefix'_event_rural_acpop_all"
        confirm file "`event'.ster"
        est clear
        estread using "`event'.ster"
        quietly estimates dir
        local names `r(names)'
        estsave_csv `names' using "`event'.csv", replace
        confirm file "`event'_scalars.csv"

        local did "${tables}/`prefix'_did_interaction_rural_acpop_all"
        confirm file "`did'.ster"
        est clear
        estread using "`did'.ster"
        quietly estimates dir
        local names `r(names)'
        estsave_csv `names' using "`did'.csv", replace
        confirm file "`did'_scalars.csv"

        est clear
        interaction_graph using "`did'.ster", estimates(1) ///
            output("${figures}/`prefix'_did_interaction_rural_acpop_all") ///
            type(politician) modvar(downup_ac_pop)
        confirm file "${figures}/`prefix'_did_interaction_rural_acpop_all_1.png"
    }
}
display as result "COMPLETED politician CSV and interaction-plot postprocessing"

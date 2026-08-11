********************************************************************************
* Local/cluster post-processing for the 32 politician-by-province DiD models.
* Uses interaction_graph.ado unchanged so the established interaction-figure
* format is preserved exactly.
********************************************************************************

version 17
set more off

if "$root" == "" {
    clear all
    global location     "dbox"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1/32"
    global ster_suffix  "_acpop"

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
    global code_shell "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
    global code_dbox  "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"

    if "$location" == "dbox" {
        global root "$dbox"
        global code "$code_dbox"
    }
    else {
        global root "$shell"
        global code "$code_shell"
    }
}

global tables_root "${code}/../../tables"
global tables "${tables_root}/exploratory_analysis/politician_byprov_fe_sweep"
global figures_root "${code}/../../figures"
global figures "${figures_root}/exploratory_analysis/politician_byprov_fe_sweep"
capture mkdir "${figures_root}/exploratory_analysis"
capture mkdir "${figures}"

quietly do "${code}/interaction_graph.ado"

foreach fe of numlist $fe_list {
    local fe_tag : display %02.0f `fe'
    local fe_tag = strtrim("`fe_tag'")
    local input_ster "${tables}/politician_byprov_fe`fe_tag'_did_interaction${sample}_rural${ster_suffix}_all.ster"
    local output_stem "${figures}/politician_byprov_fe`fe_tag'_did_interaction_rural_acpop_all"

    confirm file "`input_ster'"
    est clear
    interaction_graph using "`input_ster'", ///
        estimates(1) ///
        output("`output_stem'") ///
        type(politician) modvar(downup_ac_pop)
    confirm file "`output_stem'_1.png"
}

display as result "COMPLETED all available politician by-province DiD interaction plots"


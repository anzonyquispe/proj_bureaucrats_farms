********************************************************************************
* One Stata process, one control definition, all 32 politician FE models.
* Every FE is saved independently by the adapted template dofile.
********************************************************************************
version 17
clear all
set more off
args control_arg
local control_env : environment POL_ORIGINAL_CONTROL_SAMPLE
local control_sample "`control_arg'"
if "`control_sample'" == "" local control_sample "`control_env'"
if !inlist("`control_sample'", "never", "both", "notyet") exit 198

set processors 1
global location     "shell"
global sample       ""
global is_rural_var "is_rural"
global fe_list      "1/32"
global ster_suffix  "_acpop"
global root "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
global code "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
quietly do "${code}/estsave_csv.ado"

forvalues fe = 1/32 {
    display as result "POLITICIAN controls=`control_sample' FE=`fe'/32"
    do "${code}/exploratory_analysis/politician_original_controls_fe_sweep/_politician_original_controls_fe_sweep.do" `fe' `control_sample'
}

* Plot only after all 32 event-study and DiD result sets exist.
global tables "${code}/../../tables/exploratory_analysis/politician_original_controls_fe_sweep"
global figures "${code}/../../figures/exploratory_analysis/politician_original_controls_fe_sweep"
quietly do "${code}/interaction_graph.ado"
forvalues fe = 1/32 {
    local tag : display %02.0f `fe'
    local tag = strtrim("`tag'")
    local stem "politician_original_fe`tag'_controls_`control_sample'"
    local input "${tables}/`stem'_did_interaction_rural_acpop_all.ster"
    local output "${figures}/`stem'_did_interaction_rural_acpop_all"
    interaction_graph using "`input'", estimates(1) ///
        output("`output'") type(politician) modvar(downup_ac_pop)
    confirm file "`output'_1.png"
}
display as result "COMPLETED politician controls=`control_sample', FE 1/32"

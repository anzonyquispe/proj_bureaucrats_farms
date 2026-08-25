********************************************************************************
* Generate every interaction figure from independently produced .ster files
********************************************************************************

version 17
set more off
set graphics off

if "$root" == "" {
    clear all
    global location     "dbox"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1"
    global ster_suffix  ""
    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
    global code_shell "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
    global code_dbox "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"
    if "$location" == "dbox" {
        global root "$dbox"
        global code "$code_dbox"
    }
    else {
        global root "$shell"
        global code "$code_shell"
    }
}

global tables  "${code}/../../tables"
global figures "${code}/../../figures"
capture mkdir "${figures}/Interaction_downwind"
quietly do "${code}/interaction_graph.ado"

* Population-weighted figures actively referenced by main.tex.
est clear
interaction_graph using ///
    "${tables}/_app_18_protest_5km_fe12_did_downup_plot${sample}_rural_acpop${ster_suffix}.ster", ///
    estimates(1) ///
    output("${figures}/_app_18_protest_5km_fe12_did_downup_plot_rural_acpop${sample}${ster_suffix}") ///
    type(protest) modvar(downup_ac_pop)
copy "${figures}/_app_18_protest_5km_fe12_did_downup_plot_rural_acpop${sample}${ster_suffix}_1.png" ///
     "${figures}/_app_18_protest_5km_fe12_did_downup_plot_rural_acpop${sample}${ster_suffix}.png", replace

est clear
interaction_graph using ///
    "${tables}/_app_19_polischar_fe12_did_downup_inter_plot${sample}_rural_acpop${ster_suffix}.ster", ///
    estimates(1) ///
    output("${figures}/_app_19_polischar_fe12_did_downup_inter_plot_rural_acpop${sample}${ster_suffix}") ///
    type(politician) modvar(downup_ac_pop)
copy "${figures}/_app_19_polischar_fe12_did_downup_inter_plot_rural_acpop${sample}${ster_suffix}_1.png" ///
     "${figures}/_app_19_polischar_fe12_did_downup_inter_plot_rural_acpop${sample}${ster_suffix}.png", replace

* Area-weighted counterparts retained under their historical names.
est clear
interaction_graph using ///
    "${tables}/_app_18_protest_5km_fe12_did_downup_plot${sample}_rural${ster_suffix}.ster", ///
    estimates(1) ///
    output("${figures}/Interaction_downwind/_app_downup_rel_protest${sample}${ster_suffix}") ///
    type(protest) modvar(downup_ac)
copy "${figures}/Interaction_downwind/_app_downup_rel_protest${sample}${ster_suffix}_1.png" ///
     "${figures}/Interaction_downwind/_app_downup_rel_protest${sample}${ster_suffix}.png", replace

est clear
interaction_graph using ///
    "${tables}/_app_19_polischar_fe12_did_downup_inter_plot${sample}_rural${ster_suffix}.ster", ///
    estimates(1) ///
    output("${figures}/Interaction_downwind/_app_downup_rel_polischar${sample}${ster_suffix}") ///
    type(politician) modvar(downup_ac)
copy "${figures}/Interaction_downwind/_app_downup_rel_polischar${sample}${ster_suffix}_1.png" ///
     "${figures}/Interaction_downwind/_app_downup_rel_polischar${sample}${ster_suffix}.png", replace

display as result "Generated protest and politician interaction figures in ${figures}"

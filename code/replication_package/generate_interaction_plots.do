********************************************************************************
* Interaction plots referenced by main.tex
********************************************************************************

if "$root" == "" do "config.do"
quietly do "${code}/tools/estload_csv.ado"
quietly do "${code}/tools/interaction_graph.ado"
capture mkdir "${figures}/Interaction_downwind"

* Population-weighted figures used in the main paper.
est clear
interaction_graph using ///
    "${tables}/_app_18_protest_5km_fe12_did_downup_plot${sample}_rural_acpop.ster", ///
    estimates(1) ///
    output("${figures}/_app_18_protest_5km_fe12_did_downup_plot_rural_acpop") ///
    type(protest) modvar(downup_ac_pop)

est clear
interaction_graph using ///
    "${tables}/_app_19_polischar_fe12_did_downup_inter_plot${sample}_rural_acpop.ster", ///
    estimates(1) ///
    output("${figures}/_app_19_polischar_fe12_did_downup_inter_plot_rural_acpop") ///
    type(politician) modvar(downup_ac_pop)

* Area-based figures use the historical filenames expected by main.tex.
est clear
interaction_graph using ///
    "${tables}/_app_18_protest_5km_fe12_did_downup_plot${sample}_rural.ster", ///
    estimates(1) ///
    output("${figures}/Interaction_downwind/_app_downup_rel_protest") ///
    type(protest) modvar(downup_ac)
copy "${figures}/Interaction_downwind/_app_downup_rel_protest_1.png" ///
     "${figures}/Interaction_downwind/_app_downup_rel_protest.png", replace

est clear
interaction_graph using ///
    "${tables}/_app_19_polischar_fe12_did_downup_inter_plot${sample}_rural.ster", ///
    estimates(1) ///
    output("${figures}/Interaction_downwind/_app_downup_rel_polischar") ///
    type(politician) modvar(downup_ac)
copy "${figures}/Interaction_downwind/_app_downup_rel_polischar_1.png" ///
     "${figures}/Interaction_downwind/_app_downup_rel_polischar.png", replace

********************************************************************************

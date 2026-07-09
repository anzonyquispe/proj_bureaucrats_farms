* Load the ado
clear all
set more off

* Auto-detect environment
global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
// global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"

capture confirm file "${shell}/code/tools/interaction_graph.ado"
if _rc == 0 {
    global root "$shell"
    display "Running on cluster (shell)"
}
else {
    global root "$dbox"
    display "Running locally (dbox)"
}

cd "${root}"
qui do "code/tools/interaction_graph.ado" 

global tables "${root}/tex/paper/tables"
global figures "${root}/tex/paper/figures"
																							   

* ---- app_18 protest downup plot (rural) ------------------------------------
est clear
interaction_graph using "${tables}/_app_18_protest_5km_fe12_did_downup_plot_rural.ster", ///
  estimates(1) ///
  output("${figures}/_app_18_protest_5km_fe12_did_downup_plot_rural") ///
  type(protest) ///
  modvar(downup_ac)

* ---- app_18 protest downup plot (acpop) ------------------------------------
est clear
interaction_graph using "${tables}/_app_18_protest_5km_fe12_did_downup_plot_rural_acpop.ster", ///
  estimates(1) ///
  output("${figures}/_app_18_protest_5km_fe12_did_downup_plot_rural_acpop") ///
  type(protest) ///
  modvar(downup_ac_pop)

* ---- app_19 polischar downup inter plot (rural) ----------------------------
est clear
interaction_graph using "${tables}/_app_19_polischar_fe12_did_downup_inter_plot_rural.ster", ///
  estimates(1) ///
  output("${figures}/_app_19_polischar_fe12_did_downup_inter_plot_rural") ///
  type(politician) ///
  modvar(downup_ac)

* ---- app_19 polischar downup inter plot (acpop) ----------------------------
est clear
interaction_graph using "${tables}/_app_19_polischar_fe12_did_downup_inter_plot_rural_acpop.ster", ///
  estimates(1) ///
  output("${figures}/_app_19_polischar_fe12_did_downup_inter_plot_rural_acpop") ///
  type(politician) ///
  modvar(downup_ac_pop)

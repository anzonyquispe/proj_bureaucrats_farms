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
																							   
* With STER file                                                                                 
interaction_graph using "${tables}/_main_4_protest_5km_fe12_did_downup_rural.ster", ///                        
  estimates(6) ///                                                                                     
  output("${figures}/_main_4_protest_5km_fe12_did_downup_rural") ///                                         
  type(protest) ///                                                                                    
  modvar(moderator) 

est clear
interaction_graph using "${tables}/_main_5_polischar_fe12_did_downup_inter_rural.ster", ///                        
  estimates(6) ///                                                                                     
  output("${figures}/_main_5_polischar_fe12_did_downup_inter_rural") ///                                         
  type(politician) ///                                                                                    
  modvar(moderator) yrange(-20 10)

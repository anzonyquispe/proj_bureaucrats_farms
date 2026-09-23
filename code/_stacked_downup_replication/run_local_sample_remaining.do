********************************************************************************
* Resume the local sample smoke test after the unavailable 13 km placebo input.
********************************************************************************

version 17
clear all
set more off

global location     "dbox"
global sample       "_sample"
global is_rural_var "is_rural"
global fe_list      "1"
global ster_suffix  ""
global root "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
global code "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"
global int_data "${root}/data_output/intermediate"
global tables "${code}/../../tables"
global figures "${code}/../../figures"

capture program drop reghdfejl
program define reghdfejl, eclass
    reghdfe `0'
end

capture log close _all
log using "${code}/logs/local_sample_remaining.log", replace text

confirm file "${int_data}/stacked_downup_neigh${sample}.csv"
do "${code}/_main_6_neighbour.do"
do "${code}/_main_6_neighbour_plot.do"
do "${code}/_generate_interaction_plots.do"

display as result "LOCAL SAMPLE REMAINING STAGES COMPLETED"
log close


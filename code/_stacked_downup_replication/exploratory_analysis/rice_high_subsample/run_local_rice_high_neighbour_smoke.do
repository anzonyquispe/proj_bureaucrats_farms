********************************************************************************
* Local neighbour regression test for the master-derived rice-high sample.
********************************************************************************

version 17
clear all
set more off

global location "dbox"
global sample "_sample"
global is_rural_var "is_rural"
global fe_list "1"
global ster_suffix "_ricehigh"
global analysis_subsample "rice_high"
global root "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
global code "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"
global int_data "${root}/data_output/intermediate"
global tables "${code}/../../tables"
global figures "${code}/../../figures"

capture program drop reghdfejl
program define reghdfejl, eclass
    reghdfe `0'
end

do "${code}/_main_6_neighbour.do"
confirm file "${tables}/main_figure4_neighbour_sample_rural_ricehigh.ster"
display as result "LOCAL RICE-HIGH NEIGHBOUR SMOKE TEST PASSED"

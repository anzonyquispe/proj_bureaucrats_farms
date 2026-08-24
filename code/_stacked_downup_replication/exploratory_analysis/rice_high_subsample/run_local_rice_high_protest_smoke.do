********************************************************************************
* Local protest regression test for the rice-high sampled observations.
********************************************************************************

version 17
clear all
set more off

global location "dbox"
global sample "_sample"
global is_rural_var "is_rural"
global fe_list "1/3"
global ster_suffix "_acpop_ricehigh"
global analysis_subsample "rice_high"
global stacked_file "stacked_data_protest5km"
global downup_var "downup_ac_pop"
global root "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
global code "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"
global int_data "${root}/data_output/intermediate"
global tables "${code}/../../tables"
global figures "${code}/../../figures"

capture program drop reghdfejl
program define reghdfejl, eclass
    reghdfe `0'
end

do "${code}/_main_4_protest_5km_fe12_did_downup.do"
confirm file ///
    "${tables}/_main_4_protest_5km_fe12_did_downup_sample_rural_acpop_ricehigh.ster"

global fe_list "3"
do "${code}/_app_18_protest_5km_fe12_did_downup_plot.do"
confirm file ///
    "${tables}/_app_18_protest_5km_fe12_did_downup_plot_sample_rural_acpop_ricehigh.ster"
display as result "LOCAL RICE-HIGH PROTEST SMOKE TEST PASSED"

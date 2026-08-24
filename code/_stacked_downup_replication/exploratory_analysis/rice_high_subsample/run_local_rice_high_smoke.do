********************************************************************************
* Representative local regression test using the population main DiD sample.
********************************************************************************

version 17
clear all
set more off

global location "dbox"
global sample "_sample"
global is_rural_var "is_rural"
global fe_list "1/4"
global ster_suffix "_stacked_ricehigh"
global analysis_subsample "rice_high"
global stacked_file "combined_dt_pop"
global downup_var "downup_ac_pop"
global did_output "main_did_downup_pop_ac"
global root "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
global code "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"
global int_data "${root}/data_output/intermediate"
global tables "${code}/../../tables"
global figures "${code}/../../figures"

capture program drop reghdfejl
program define reghdfejl, eclass
    reghdfe `0'
end

do "${code}/_main_1_did.do"
confirm file "${tables}/main_did_downup_pop_ac_sample_rural_stacked_ricehigh.ster"
display as result "LOCAL RICE-HIGH REGRESSION SMOKE TEST PASSED"

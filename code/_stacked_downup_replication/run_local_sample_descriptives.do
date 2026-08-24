********************************************************************************
* Focused local smoke test for the three canonical descriptive tables.
********************************************************************************

version 17
clear all
set more off

global location "dbox"
global sample "_sample"
global is_rural_var "is_rural"
global fe_list "1"
global ster_suffix ""
global analysis_subsample "all"
global root "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
global repo "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms"
global code "${repo}/code/_stacked_downup_replication"
global tables "${repo}/tables"

capture program drop reghdfejl
program define reghdfejl, eclass
    reghdfe `0'
end

capture log close _all
log using "${code}/logs/local_sample_descriptives.log", replace text
do "${code}/app_main_descriptive.do"
do "${code}/app_5km_descriptive.do"
do "${code}/app_polischar_descriptive.do"
display as result "LOCAL SAMPLE DESCRIPTIVE TABLES COMPLETED"
log close

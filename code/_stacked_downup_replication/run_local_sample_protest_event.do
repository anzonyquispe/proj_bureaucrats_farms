********************************************************************************
* Focused local smoke test for the canonical protest event study.
********************************************************************************

version 17
clear all
set more off

global location "dbox"
global sample "_sample"
global is_rural_var "is_rural"
global fe_list "3"
global ster_suffix ""
global control_samples ""
global root "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
global repo "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms"
global code "${repo}/code/_stacked_downup_replication"
global tables "${repo}/tables"
global figures "${repo}/figures"

capture program drop reghdfejl
program define reghdfejl, eclass
    reghdfe `0'
end

capture log close _all
log using "${code}/logs/local_sample_protest_event.log", replace text
do "${code}/_app_17_5km_fe12_evst_all.do"
do "${code}/_export_event_study_csv.do"
display as result "LOCAL SAMPLE PROTEST EVENT STUDY COMPLETED"
log close


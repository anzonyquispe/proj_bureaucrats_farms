********************************************************************************
* Local post-processing smoke test for *_sample estimation outputs.
********************************************************************************

version 17
clear all
set more off

global location "dbox"
global sample "_sample"
global is_rural_var "is_rural"
global fe_list "1"
global ster_suffix ""
global root "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
global repo "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms"
global code "${repo}/code/_stacked_downup_replication"
global tables "${repo}/tables"
global figures "${repo}/figures"

capture log close _all
log using "${code}/logs/local_sample_postprocessing.log", replace text
do "${code}/_run_local_ster_postprocessing.do"
display as result "LOCAL SAMPLE POST-PROCESSING COMPLETED"
log close


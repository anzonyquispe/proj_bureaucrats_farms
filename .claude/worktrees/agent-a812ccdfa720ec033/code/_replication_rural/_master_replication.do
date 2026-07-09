********************************************************************************
* _master_replication_rural.do
* Master replication file - RURAL GRIDS ONLY
* "Democratic Accountability and Environmental Regulation"
* Authors: Dipoppa, Gulzar, Pezone, Quispe
********************************************************************************

clear all
set more off
set matsize 10000

********************************************************************************
* EASY TOGGLES - SET THESE BEFORE RUNNING
********************************************************************************

* TOGGLE 1: Location - "dbox" for local, "shell" for cluster
global location "shell"

* TOGGLE 2: Data - "_sample" for sample data, "" for complete data
global sample ""

********************************************************************************
* SET PATHS BASED ON TOGGLES
********************************************************************************

global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"

* Set root based on location toggle
if "$location" == "dbox" {
    global root "$dbox"
}
else {
    global root "$shell"
}

* Derived paths
global code     "${root}/code/_replication_rural"
global int_data "${root}/data_output/intermediate"
global tables   "${root}/tex/paper/tables"
global figures  "${root}/tex/paper/figures"

cd "${root}"

* Log file
cap log close
log using "${code}/_master_replication_log${sample}.txt", replace text

display "=============================================="
display "MASTER REPLICATION FILE"
display "Location: $location"
display "Sample mode: $sample"
display "Root path: $root"
display "Started: $S_DATE $S_TIME"
display "=============================================="


/// Generating Ado File
qui do "${root}/code/_replication_rural/estsave_csv.ado"


********************************************************************************
* RUN DO-FILES
********************************************************************************

* ==============================================================================
* MAIN DiD ANALYSES (using 0_master_merge_data_gen)
* ==============================================================================


do "${code}/_main_1_did.do"
do "${code}/_main_2_event_study.do"
do "${code}/_main_3_bureau_polisc_did.do"
do "${code}/_main_4_protest_5km_fe12_did_downup.do"
do "${code}/_main_5_polischar_fe12_did_downup_inter.do"
do "${code}/_app_6_main_did_treat_definition.do"
do "${code}/_app_7_main_did_downup_area_ac_dv.do"
do "${code}/_app_8_main_did_by_year.do"
do "${code}/_app_9_main_did_by_state.do"
do "${code}/_app_10_did_rice_moderators.do"
do "${code}/_app_11_placebo_pop_13km.do"
do "${code}/_app_12_protest_5km_fe_did.do"
do "${code}/_app_13_protest_5km_fe12_did_ricemods.do"
do "${code}/_app_14_polischar_fe12_did_ricemods.do"
do "${code}/_app_15_polischar_fe12_did.do"
do "${code}/_app_16_polischar_fe12_evst_all.do"
do "${code}/_app_17_5km_fe12_evst_all.do"



********************************************************************************
* COMPLETION
********************************************************************************

display _n "=============================================="
display "MASTER REPLICATION COMPLETED"
display "Finished: $S_DATE $S_TIME"
display "=============================================="

log close

********************************************************************************

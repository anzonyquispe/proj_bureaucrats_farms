********************************************************************************
* Sequential Stata fallback. Cluster runs should use sbatch/submit_all.sh,
* which submits every dofile below as an independent job.
********************************************************************************

version 17
set more off
set matsize 10000

if "$root" == "" {
    clear all

    * Five sbatch-array parameters; defaults apply only to standalone runs.
    global location "shell"
    global sample ""
    global is_rural_var "is_rural_area"
    global fe_list "1/4"
    global ster_suffix ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
    global code_shell "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
    global code_dbox "/Users/anzony.quisperojas/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"

    if "$location" == "dbox" {
        global root "$dbox"
        global code "$code_dbox"
    }
    else {
        global root "$shell"
        global code "$code_shell"
    }
}

* A caller may set $root and $code explicitly (the sbatch runner does this).
if "$code" == "" {
    global code "${root}/code/_stacked_downup_replication"
}

global int_data "${root}/data_output/intermediate"
global tables "${root}/tex/paper/tables"
global figures "${root}/tex/paper/figures"

capture log close _all
log using "${code}/_master_replication_log${sample}.txt", replace text

quietly do "${code}/estsave_csv.ado"
quietly do "${code}/estload_csv.ado"

display "============================================================"
display "STACKED DOWN/UP REPLICATION"
display "Root: ${root}"
display "Rural classifier: ${is_rural_var}"
display "Sample suffix: ${sample}"
display "Started: $S_DATE $S_TIME"
display "============================================================"

local requested_fe_list "$fe_list"
local requested_ster_suffix "$ster_suffix"

********************************************************************************
* 1. Main DiD estimates: area- and population-weighted treatment stacks
********************************************************************************

global fe_list "1/4"

global stacked_file "combined_dt"
global downup_var "downup_ac"
global did_output "main_did_downup_area_ac"
global ster_suffix "_stacked"
do "${code}/_main_1_did.do"

global stacked_file "combined_dt_pop"
global downup_var "downup_ac_pop"
global did_output "main_did_downup_pop_ac"
global ster_suffix "_stacked"
do "${code}/_main_1_did.do"

********************************************************************************
* 2. Remaining active-result table estimates and descriptive tables
********************************************************************************

global ster_suffix ""
global fe_list "1/5"
do "${code}/_main_3_bureau_polisc_did.do"

global fe_list "1/7"
do "${code}/_app_6_main_did_treat_definition.do"

global fe_list "1/3"
do "${code}/_app_7_main_did_downup_area_ac_dv.do"

global fe_list "1/10"
do "${code}/_app_8_main_did_by_year.do"

global fe_list "1/4"
do "${code}/_app_9_main_did_by_state.do"

global fe_list "1"
do "${code}/app_main_descriptive.do"
do "${code}/app_5km_descriptive.do"
do "${code}/app_polischar_descriptive.do"

********************************************************************************
* 3. Five-pre-period event studies from the two main stacks
********************************************************************************

global fe_list "1"
global ster_suffix ""
do "${code}/_main_2_stacked_event_study_5pre_area.do"
do "${code}/_main_2_stacked_event_study_5pre.do"

********************************************************************************
* 4. Protest and politician-characteristic analyses
*
* Event studies write three control-sample versions:
*   baseline             treated + never treated
*   _controls_both       treated + never treated + not yet treated
*   _controls_notyet     treated + not yet treated
********************************************************************************

global fe_list "1/3"

global downup_var "downup_ac"
global ster_suffix ""
do "${code}/_main_4_protest_5km_fe12_did_downup.do"
do "${code}/_main_5_polischar_fe12_did_downup_inter.do"

global fe_list "1"
do "${code}/_app_18_protest_5km_fe12_did_downup_plot.do"
do "${code}/_app_19_polischar_fe12_did_downup_inter_plot.do"

global downup_var "downup_ac_pop"
global ster_suffix "_acpop"
do "${code}/_main_4_protest_5km_fe12_did_downup.do"
do "${code}/_main_5_polischar_fe12_did_downup_inter.do"

global fe_list "1"
do "${code}/_app_18_protest_5km_fe12_did_downup_plot.do"
do "${code}/_app_19_polischar_fe12_did_downup_inter_plot.do"

global fe_list "1"

global downup_var "downup_ac"
global ster_suffix ""
do "${code}/_app_16_polischar_fe12_evst_all.do"
do "${code}/_app_17_5km_fe12_evst_all.do"

global downup_var "downup_ac_pop"
global ster_suffix "_acpop"
do "${code}/_app_16_polischar_fe12_evst_all.do"
do "${code}/_app_17_5km_fe12_evst_all.do"

********************************************************************************
* 5. New 13 km placebo stack and neighbour-border analysis
********************************************************************************

global fe_list "1"
global ster_suffix ""
do "${code}/_app_11_placebo_pop_13km.do"

* This input is produced by the separate neighbour-stack builder. Missing it
* is a hard error because neighbor_output.pdf is active in main.tex.
confirm file "${int_data}/stacked_downup_neigh${sample}.csv"
global fe_list "1"
do "${code}/_main_6_neighbour.do"
do "${code}/_main_6_neighbour_plot.do"

* Interaction plots consume the four area/population .ster files above.
do "${code}/_generate_interaction_plots.do"

********************************************************************************
* 6. Render all LaTeX tables from .ster files
********************************************************************************

do "${code}/_generate_all_tables.do"

global fe_list "`requested_fe_list'"
global ster_suffix "`requested_ster_suffix'"

display "============================================================"
display "STATA REPLICATION COMPLETED: $S_DATE $S_TIME"
display "Run plotting_event_studies.R next for all event-study and HonestDiD figures."
display "============================================================"

log close

********************************************************************************
* Local post-processing of already-generated .ster files.
*
* Inputs:  .ster files in the repository-level tables folder
* Outputs: the same tables folder (.csv and .tex files)
*
* Cluster jobs stop after creating .ster files. Run this dofile in local Stata.
********************************************************************************

version 17
clear all
set more off

global location "dbox"
global sample ""
global is_rural_var "is_rural"
global fe_list "1"
global ster_suffix ""

global root "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
global repo "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms"
global code "${repo}/code/_stacked_downup_replication"
global tables "${repo}/tables"
global figures "${repo}/figures"

capture mkdir "${tables}"
capture mkdir "${figures}"
adopath ++ "${code}"

display as text "Local .ster input folder: ${tables}"

* These eight files are required for the politician/protest plots that compare
* never-treated, pooled, and not-yet-treated control definitions. Warn without
* blocking unrelated CSV and table generation.
local control_sters ///
    "_app_16_polischar_fe12_evst_all_rural_controls_never.ster" ///
    "_app_16_polischar_fe12_evst_all_rural_controls_both.ster" ///
    "_app_16_polischar_fe12_evst_all_rural_controls_notyet.ster" ///
    "_app_16_polischar_fe12_evst_all_rural_acpop_controls_never.ster" ///
    "_app_16_polischar_fe12_evst_all_rural_acpop_controls_both.ster" ///
    "_app_16_polischar_fe12_evst_all_rural_acpop_controls_notyet.ster" ///
    "_app_17_5km_fe12_evst_all_rural_controls_never.ster" ///
    "_app_17_5km_fe12_evst_all_rural_controls_both.ster" ///
    "_app_17_5km_fe12_evst_all_rural_controls_notyet.ster" ///
    "_app_17_5km_fe12_evst_all_rural_acpop_controls_never.ster" ///
    "_app_17_5km_fe12_evst_all_rural_acpop_controls_both.ster" ///
    "_app_17_5km_fe12_evst_all_rural_acpop_controls_notyet.ster"

local missing_controls = 0
foreach ster_file of local control_sters {
    capture confirm file "${tables}/`ster_file'"
    if _rc {
        display as error "MISSING OPTIONAL CONTROL-SAMPLE STER: `ster_file'"
        local missing_controls = `missing_controls' + 1
    }
}
if `missing_controls' > 0 {
    display as error "Control-sample event-study ster files missing: `missing_controls'"
    display as error "Their R figures cannot be made until these files are copied locally."
}

display as text "Exporting event-study CSV files..."
do "${code}/_export_event_study_csv.do"

display as text "Generating LaTeX tables..."
do "${code}/_generate_all_tables.do"

display as result "LOCAL STATA POST-PROCESSING COMPLETED"
display as result "CSV/TEX outputs: ${tables}"

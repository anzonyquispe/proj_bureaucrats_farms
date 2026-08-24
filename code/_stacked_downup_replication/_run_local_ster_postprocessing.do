********************************************************************************
* Local post-processing of already-generated .ster files.
*
* Inputs:  .ster files in the repository-level tables folder
* Outputs: the same tables folder (.csv and .tex files)
*
* Cluster jobs stop after creating .ster files. Run this dofile in local Stata.
********************************************************************************

version 17
set more off

if "$root" == "" {
    clear all
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
}
else {
    clear
    if "$repo" == "" global repo "${code}/../.."
    global tables "${repo}/tables"
    global figures "${repo}/figures"
}

capture mkdir "${tables}"
capture mkdir "${figures}"
adopath ++ "${code}"

display as text "Local .ster input folder: ${tables}"

* Both production analyses use their final pooled samples. Protest produces a
* single ster containing FE1-FE5 for the baseline and rice-production result.
local control_sters ///
    "_app_16_polischar_fe12_evst_all${sample}_rural_controls_both.ster" ///
    "_app_16_polischar_fe12_evst_all${sample}_rural_acpop_controls_both.ster" ///
    "_app_17_5km_fe12_evst_all${sample}_rural.ster"

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

display as text "Generating interaction figures from local .ster files..."
do "${code}/_generate_interaction_plots.do"

display as text "Generating the neighbour figure from its local .ster file..."
do "${code}/_main_6_neighbour_plot.do"

display as result "LOCAL STATA POST-PROCESSING COMPLETED"
display as result "CSV/TEX outputs: ${tables}"
display as result "Stata figure outputs: ${figures}"

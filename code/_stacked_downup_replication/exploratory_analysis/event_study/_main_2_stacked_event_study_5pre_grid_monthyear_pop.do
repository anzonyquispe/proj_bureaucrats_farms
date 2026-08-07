********************************************************************************
* Population-weighted stacked event study, relative months -6 through 5.
* Fixed effects: grid x cohort and month-year x cohort only.
* Period -1 remains the omitted reference category.
*
* Optional direct-call arguments:
*   controls_mode: controls | nocontrols
*   cluster_mode:  cohort | grid_monthyear
*   output_stem:   filename stem written under tables/
********************************************************************************

args controls_mode cluster_mode output_stem

if "$root" == "" {
    clear all
    set more off

    * Five sbatch-array parameters; defaults apply only to standalone runs.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1"
    global ster_suffix  ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
    global code_shell "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
    global code_dbox  "/Users/anzony.quisperojas/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"
    if "$location" == "dbox" {
        global root "$dbox"
        global code "$code_dbox"
    }
    else {
        global root "$shell"
        global code "$code_shell"
    }
    quietly do "${code}/estsave_csv.ado"
}

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"

if "`controls_mode'" == "" local controls_mode "controls"
if "`cluster_mode'" == "" local cluster_mode "cohort"
if "`output_stem'" == "" {
    local output_stem "stacked_event_study_pop_5pre_grid_monthyear_fe"
}

if !inlist("`controls_mode'", "controls", "nocontrols") {
    display as error "controls_mode must be controls or nocontrols."
    exit 198
}
if !inlist("`cluster_mode'", "cohort", "grid_monthyear") {
    display as error "cluster_mode must be cohort or grid_monthyear."
    exit 198
}

if "`controls_mode'" == "controls" {
    local weather_controls "wind_direction av_wind_speed"
    local controls_tag "Y"
}
else {
    local weather_controls ""
    local controls_tag "N"
}

if "`cluster_mode'" == "cohort" {
    local cluster_variables ///
        "ac_uq_id#cohort#monthyear unique_small_grid_id#cohort"
    local cluster_tag "AC x cohort x month-year; grid x cohort"
}
else {
    local cluster_variables "unique_small_grid_id monthyear"
    local cluster_tag "Grid; month-year"
}

import delimited using "${int_data}/combined_dt_pop${sample}.csv", clear varnames(1)
keep if inrange(relative_monthyear, -6, 5)
gen relative_year_bin = relative_monthyear
gen relative_year_bin_aux = relative_year_bin + 7
local base = 6
capture drop countk
gen countk = count * 1000

merge m:1 unique_small_grid_id using "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

capture confirm variable rice_prod_aclvl_ahigh
if _rc {
    merge m:1 unique_small_grid_id ac_uq_id using ///
        "${int_data}/rice_moderators.dta", keep(master match) nogen ///
        keepusing(rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh)
}

local dep_var countk
local fe1 "unique_small_grid_id#cohort monthyear#cohort"
local moderators_list moderator rice_prod_aclvl_ahigh
* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
gen moderator = 0
egen tag_ac = tag(ac_uq_id)
count if tag_ac == 1
local numacs = r(N)

est clear
local i = 1
local estimate_names ""
foreach mod of local moderators_list {
    replace moderator = `mod'
    local rhs ///
        "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' `weather_controls'"

    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1
    local ymean = r(mean)
    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)

    foreach fe of numlist $fe_list {
        if `fe' != 1 {
            display as error "This standalone file supports only FE specification 1."
            exit 198
        }

        reghdfejl `dep_var' `rhs', absorb(`fe`fe'') ///
            cluster(`cluster_variables')
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"
        estadd local fespec "Grid x cohort and month-year x cohort"
        estadd local mod "`mod'"
        estadd local monthyearfe "Y"
        estadd local acfe "N"
        estadd local acmonthfe "N"
        estadd local gridfe "Y"
        estadd local weathercontrols "`controls_tag'"
        estadd local clusterspec "`cluster_tag'"
        local estname evreg`i'
        local i = `i' + 1
        est store `estname'
        local estimate_names "`estimate_names' `estname'"
    }
}

local outbase "${tables}/`output_stem'${sample}_rural${ster_suffix}"
estwrite `estimate_names' using "`outbase'.ster", replace
estsave_csv `estimate_names' using "`outbase'.csv", replace

display as result "Saved `outbase'.ster and `outbase'.csv"

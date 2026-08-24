********************************************************************************
* Population-weighted stacked event study with a configurable event window.
* Exploratory normalization: relative month 0 is the omitted reference period.
*
* Arguments:
*   fe_mode:       main | grid_monthyear
*   controls_mode: controls | nocontrols
*   cluster_mode:  cohort | grid_monthyear
*   output_stem:   filename stem written under tables/
*   window_min:    first retained relative month; default -6
*   window_max:    last retained relative month; default +5
********************************************************************************

version 17
args fe_mode controls_mode cluster_mode output_stem window_min window_max

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

if !inlist("`fe_mode'", "main", "grid_monthyear") {
    display as error "fe_mode must be main or grid_monthyear."
    exit 198
}
if !inlist("`controls_mode'", "controls", "nocontrols") {
    display as error "controls_mode must be controls or nocontrols."
    exit 198
}
if !inlist("`cluster_mode'", "cohort", "grid_monthyear") {
    display as error "cluster_mode must be cohort or grid_monthyear."
    exit 198
}
if "`output_stem'" == "" {
    display as error "output_stem is required."
    exit 198
}
if "`window_min'" == "" local window_min = -6
if "`window_max'" == "" local window_max = 5
if `window_min' >= 0 | `window_max' <= 0 {
    display as error "The event window must contain negative periods, 0, and positive periods."
    exit 198
}
if `window_min' != floor(`window_min') | `window_max' != floor(`window_max') {
    display as error "window_min and window_max must be integers."
    exit 198
}

if "`fe_mode'" == "main" {
    local fe1 "unique_small_grid_id#cohort ac_uq_id#monthyear#cohort"
    local fespec_tag "Grid x cohort; AC x month-year x cohort"
    local monthyearfe "N"
    local acfe "N"
    local acmonthfe "Y"
    local gridfe "Y"
}
else {
    local fe1 "unique_small_grid_id#cohort monthyear#cohort"
    local fespec_tag "Grid x cohort; month-year x cohort"
    local monthyearfe "Y"
    local acfe "N"
    local acmonthfe "N"
    local gridfe "Y"
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
keep if inrange(relative_monthyear, `window_min', `window_max')
gen relative_year_bin = relative_monthyear
local shift = 1 - `window_min'
gen relative_year_bin_aux = relative_year_bin + `shift'
* Relative month 0 maps to `shift' and is the omitted category.
local base = `shift'
capture drop countk
gen countk = count * 1000

merge m:1 unique_small_grid_id using "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

confirm variable rice_prod_aclvl_ahigh
assert inlist(rice_prod_aclvl_ahigh, 0, 1)

local dep_var countk
local moderators_list moderator rice_prod_aclvl_ahigh
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
            display as error "This exploratory file supports only FE specification 1."
            exit 198
        }

        reghdfejl `dep_var' `rhs', absorb(`fe`fe'') ///
            cluster(`cluster_variables')
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"
        estadd local fespec "`fespec_tag'"
        estadd local mod "`mod'"
        estadd local monthyearfe "`monthyearfe'"
        estadd local acfe "`acfe'"
        estadd local acmonthfe "`acmonthfe'"
        estadd local gridfe "`gridfe'"
        estadd local weathercontrols "`controls_tag'"
        estadd local clusterspec "`cluster_tag'"
        estadd local omittedperiod "0"
        estadd local eventwindow "`window_min' to `window_max'"
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

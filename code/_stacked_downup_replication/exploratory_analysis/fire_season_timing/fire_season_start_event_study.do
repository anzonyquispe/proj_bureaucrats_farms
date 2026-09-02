********************************************************************************
* Exploratory seasonality-balance event study for the downup_ac_pop stack.
*
* Outcome: 1 in October or November, 0 in every other calendar month.
* Window and omitted period match the main population event study: -5 to +6,
* with relative month 0 omitted.
*
* IMPORTANT: the main AC x month-year x cohort FE cannot be used here because
* it absorbs this calendar-month outcome exactly. We retain grid x cohort FE,
* the production sample restrictions, weather controls, and clustering.
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    * Standalone defaults for the five sbatch-array parameters:
    * location, sample, is_rural_var, fe_list, and ster_suffix.
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
global output_dir "${code}/../../tables/exploratory_analysis/fire_season_timing"
capture mkdir "${code}/../../tables/exploratory_analysis"
capture mkdir "${output_dir}"

import delimited using "${int_data}/combined_dt_pop${sample}.csv", ///
    clear varnames(1)

keep if inrange(relative_monthyear, -5, 6)
keep if year < 2022 | (year == 2022 & month <= 8)

gen relative_year_bin = relative_monthyear
gen relative_year_bin_aux = relative_year_bin + 6
local base = 6
assert relative_year_bin == 0 if relative_year_bin_aux == `base'

* This is Saad's proposed diagnostic outcome. It marks the beginning-of-fire-
* season window in every calendar year; it does not restrict the sample.
gen byte fire_season_start = inlist(month, 10, 11)
label variable fire_season_start "October-November fire-season window"
assert inlist(fire_season_start, 0, 1)
assert fire_season_start == 1 if inlist(month, 10, 11)
assert fire_season_start == 0 if !inlist(month, 10, 11)

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1

confirm variable downup_ac_pop
confirm variable treat
confirm variable cohort
confirm variable monthyear
isid unique_small_grid_id monthyear cohort treat

* Preserve the main event-study moderator structure even though this diagnostic
* intentionally has no heterogeneity moderator.
* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
gen byte moderator = 0
local moderators_list moderator
local dep_var fire_season_start
local fe1 "unique_small_grid_id#cohort"

do "${code}/_apply_analysis_subsample.do"

egen tag_ac = tag(ac_uq_id)
count if tag_ac == 1
local numacs = r(N)

est clear
local i = 1
local estimate_names ""
foreach mod of local moderators_list {
    replace moderator = `mod'
    local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"

    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1
    local ymean = r(mean)
    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)

    foreach fe of numlist $fe_list {
        local fespec `fe`fe''
        reghdfejl `dep_var' `rhs', absorb(`fespec') ///
            cluster(ac_uq_id#cohort#monthyear unique_small_grid_id#cohort)

        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"
        estadd local fespec "fe`fe'"
        estadd local mod "`mod'"
        estadd local outcome "fire_season_start"
        local estname evreg`i'
        local i = `i' + 1
        est store `estname'
        local estimate_names "`estimate_names' `estname'"
    }
}

local outbase "${output_dir}/fire_season_start_event_study${sample}_rural${ster_suffix}"
estwrite `estimate_names' using "`outbase'.ster", replace
estsave_csv `estimate_names' using "`outbase'.csv", replace
confirm file "`outbase'.ster"
confirm file "`outbase'.csv"
display as result "Generated exploratory fire-season timing results: `outbase'"

********************************************************************************

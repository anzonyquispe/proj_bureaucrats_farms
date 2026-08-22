********************************************************************************
* Area-based stacked event study over relative months -5 through 6.
* Period 0 is the omitted reference category.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for location, sample, rural definition, FE list,
    * and output suffix. Sbatch wrappers may override all five.
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

import delimited using "${int_data}/combined_dt${sample}.csv", clear varnames(1)
keep if inrange(relative_monthyear, -5, 6)
gen relative_year_bin = relative_monthyear
gen relative_year_bin_aux = relative_year_bin + 6
local base = 6
assert relative_year_bin == 0 if relative_year_bin_aux == `base'
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
local fe1 "unique_small_grid_id#cohort ac_uq_id#monthyear#cohort"
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
    local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1
    local ymean = r(mean)
    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)
    foreach fe of numlist $fe_list {
        reghdfejl `dep_var' `rhs', absorb(`fe`fe'') ///
            cluster(ac_uq_id#cohort#monthyear unique_small_grid_id#cohort)
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"
        estadd local fespec "fe`fe'"
        estadd local mod "`mod'"
        local estname evreg`i'
        local i = `i' + 1
        est store `estname'
        local estimate_names "`estimate_names' `estname'"
    }
}

local outbase "${tables}/stacked_event_study_5pre${sample}_rural${ster_suffix}"
estwrite evreg* using "`outbase'.ster", replace
estsave_csv `estimate_names' using "`outbase'.csv", replace

********************************************************************************

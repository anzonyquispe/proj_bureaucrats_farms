********************************************************************************
* Protest DiD interaction estimates used by _generate_interaction_plots.do
********************************************************************************

version 17
set more off

if "$root" == "" {
    clear all
    * Standalone defaults for the five cluster parameters.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural_area"
    global fe_list      "1"
    global ster_suffix  ""
    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }
}
if "$downup_var" == "" {
    global downup_var "downup_ac"
}

global int_data "${root}/data_output/intermediate"
global tables   "${root}/tex/paper/tables"

import delimited using "${int_data}/stacked_data_protest5km${sample}.csv", ///
    clear varnames(1)
capture confirm variable relative_year_bin
if _rc {
    rename relative_year relative_year_bin
}

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural_area is_rural_farzad) nogen
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

* Do not exclude grids intersecting more than one AC.
* merge m:1 unique_small_grid_id using "${int_data}/grids_with_more_1_ac.dta"
* drop if dpl_ac == 1
* drop _merge

capture drop countk
gen countk = count * 1000
egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort)
egen province_cohort = group(province cohort)
egen ac_elec_yr = group(ac_uq_id election_year cohort)
gen post_ = relative_year_bin >= 0
gen moderator = ${downup_var}

local dep_var countk
local moderators_list ${downup_var}
local fe1 "unique_small_grid_id_cohort relative_year_bin province_cohort#election_year province_cohort#c.monthyear"
egen tag_ac = tag(ac_uq_id)
count if tag_ac == 1
local numacs = r(N)

est clear
local i = 1
foreach mod of local moderators_list {
    local rhs "ib0.post_##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1
    local ymean = r(mean)
    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)
    foreach fe of numlist $fe_list {
        reghdfejl `dep_var' `rhs', absorb(`fe`fe'') vce(cluster ac_elec_yr)
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"
        estadd local mod "`mod'"
        est store evreg`i'
        local i = `i' + 1
    }
}

estwrite evreg* using ///
    "${tables}/_app_18_protest_5km_fe12_did_downup_plot${sample}_rural${ster_suffix}.ster", replace

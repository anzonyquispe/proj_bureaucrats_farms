********************************************************************************
* Politician-characteristics interaction estimates used by plot generator.
* Final input and FE follow politician_byprov_fe_sweep.
********************************************************************************

version 17
set more off

if "$root" == "" {
    clear all
    * Standalone defaults for the five cluster parameters.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
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
global tables   "${code}/../../tables"

import delimited using "${int_data}/politicians_characteristics_byprov${sample}.csv", ///
    clear varnames(1)
capture confirm variable relative_year_bin
if _rc {
    rename relative_year relative_year_bin
}

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural) nogen
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)
keep if inrange(relative_year_bin, -5, 4)

* Do not exclude grids intersecting more than one AC.
* merge m:1 unique_small_grid_id using "${int_data}/grids_with_more_1_ac.dta"
* drop if dpl_ac == 1
* drop _merge

capture drop countk
gen countk = count * 1000
confirm variable cohort_id
confirm variable cohort_province
confirm variable control_type
assert cohort_id == floor(cohort_id) & cohort_id > 0
assert control_type == 0 if treat == 1
assert inlist(control_type, 1, 2) if treat == 0
sort cohort_id unique_small_grid_id monthyear
by cohort_id: assert province == province[1]
by cohort_id: assert cohort == cohort[1]
by cohort_id: assert cohort_province == cohort_province[1]
by cohort_id unique_small_grid_id: assert treat == treat[1]
by cohort_id unique_small_grid_id: assert control_type == control_type[1]
isid unique_small_grid_id monthyear cohort_id treat

egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
egen ac_elec_yr = group(ac_uq_id election_year cohort_id)
quietly summarize relative_year_bin
local rmin = r(min)
gen int relative_year_bin_aux = relative_year_bin - `rmin' + 1
gen post_ = relative_year_bin >= 0
gen moderator = ${downup_var}

local dep_var countk
local moderators_list ${downup_var}
local fe1 "unique_small_grid_id_cohort relative_year_bin_aux#cohort_id"
do "${code}/exploratory_analysis/rice_high_subsample/_apply_rice_high_subsample.do"

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
        estadd local fespec "`fe`fe''"
        estadd local mod "`mod'"
        est store evreg`i'
        local i = `i' + 1
    }
}

estwrite evreg* using ///
    "${tables}/_app_19_polischar_fe12_did_downup_inter_plot${sample}_rural${ster_suffix}.ster", replace

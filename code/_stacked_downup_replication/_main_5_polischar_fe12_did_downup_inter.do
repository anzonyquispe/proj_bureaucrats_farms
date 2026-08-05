********************************************************************************
* Politician-characteristics DiD with down/up interaction
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for the five sbatch-array parameters.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural_area"
    global fe_list      "1/3"
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

import delimited using "${int_data}/politicians_characteristics${sample}.csv", ///
    clear varnames(1)
capture confirm variable relative_year_bin
if _rc {
    rename relative_year relative_year_bin
}
* Always express the fire-count outcome in thousands.
capture drop countk
gen countk = count * 1000

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural_area is_rural_farzad)
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort)
egen province_cohort = group(province cohort)
egen ac_elec_yr = group(ac_uq_id election_year cohort)
gen post_ = relative_year_bin >= 0
gen moderator = 0

local fe1 "unique_small_grid_id_cohort relative_year_bin"
local fe2 "unique_small_grid_id_cohort relative_year_bin province_cohort#election_year"
local fe3 "unique_small_grid_id_cohort relative_year_bin province_cohort#election_year province_cohort#c.monthyear"
local moderators_list moderator ${downup_var}

est clear
local i = 1
foreach mod of local moderators_list {
    replace moderator = `mod'
    local rhs "ib0.post_##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
    quietly summarize countk if treat == 1 & relative_year_bin <= -1
    local ymean = r(mean)
    quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)
    unique ac_uq_id
    local numacs = r(unique)

    foreach fe of numlist $fe_list {
        reghdfejl countk `rhs', absorb(`fe`fe'') vce(cluster ac_elec_yr)
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"
        estadd local gridfe "Y"
        estadd local time "Y"
        estadd local electionfe = cond(`fe' >= 2, "Y", "N")
        estadd local provtrendfe = cond(`fe' == 3, "Y", "N")
        estadd local mod "`mod'"
        local estname evreg`i'
        local i = `i' + 1
        est store `estname'
    }
}

estwrite evreg* using ///
    "${tables}/_main_5_polischar_fe12_did_downup_inter${sample}_rural${ster_suffix}.ster", replace

********************************************************************************

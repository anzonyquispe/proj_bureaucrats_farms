********************************************************************************
* Presentation table A14: Agricultural politician x high rice production.
* Eight models: four without rice heterogeneity, followed by the same four
* FE specifications interacted with high rice production.
********************************************************************************
if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for the five sbatch-array parameters.
    global location "shell"
    global sample ""
    global is_rural_var "is_rural"
    global fe_list "0/3"
    global ster_suffix ""
    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
    global code "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
    if "$location" == "dbox" {
        global root "$dbox"
        global code "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"
    }
    else global root "$shell"
}
global int_data "${root}/data_output/intermediate"
global tables "${code}/../../tables"

import delimited using ///
    "${int_data}/politicians_characteristics_byprov${sample}.csv", clear varnames(1)
capture confirm variable relative_year_bin
if _rc rename relative_year relative_year_bin
keep if inrange(relative_year_bin, -5, 4)
keep if year < 2022 | (year == 2022 & month <= 8)
confirm variable rice_prod_aclvl_ahigh
drop if missing(rice_prod_aclvl_ahigh)
merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1

capture drop countk
gen countk = count * 1000
gen byte post_ = relative_year_bin >= 0
gen byte nofe = 1
gen byte moderator = 0
egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
egen relativeyear_cohort = group(relative_year_bin cohort_id)
egen province_cohort = group(province cohort_id)
egen ac_elec_yr = group(ac_uq_id election_year cohort_id)

local fe0 "nofe"
local fe1 "unique_small_grid_id_cohort"
local fe2 "unique_small_grid_id_cohort relativeyear_cohort"
local fe3 "unique_small_grid_id_cohort relativeyear_cohort province_cohort#c.monthyear"
local common_rhs "ib0.post_##ib0.treat##ib0.rice_prod_aclvl_ahigh wind_direction av_wind_speed"
do "${code}/_apply_analysis_subsample.do"
quietly reghdfejl countk `common_rhs', absorb(`fe3') vce(cluster ac_elec_yr)
gen byte common_sample = e(sample)
quietly count if common_sample
local common_n = r(N)
keep if common_sample
drop common_sample

egen byte tag_ac = tag(ac_uq_id)
quietly count if tag_ac
local numacs = r(N)
quietly summarize countk if treat == 1 & relative_year_bin <= -1
local ymean = r(mean)

est clear
local moderators_list moderator rice_prod_aclvl_ahigh
local i = 1
foreach mod of local moderators_list {
    replace moderator = `mod'
    local rhs "ib0.post_##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
    quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)
    foreach fe of numlist $fe_list {
        reghdfejl countk `rhs', absorb(`fe`fe'') vce(cluster ac_elec_yr)
        assert e(N) == `common_n'
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"
        local grid_label = cond(`fe' == 0, "N", "Y")
        estadd local gridfe "`grid_label'"
        local time_label = cond(`fe' >= 2, "Y", "N")
        local trend_label = cond(`fe' == 3, "Y", "N")
        estadd local time "`time_label'"
        estadd local provtrendfe "`trend_label'"
        estadd local mod "`mod'"
        est store eq`i'
        local i = `i' + 1
    }
}
estwrite eq1 eq2 eq3 eq4 eq5 eq6 eq7 eq8 using ///
    "${tables}/_app_14_polischar_fe12_did_ricemods${sample}_rural_acpop${ster_suffix}.ster", replace
display as result "Saved updated presentation ster: _app_14_polischar_fe12_did_ricemods${sample}_rural_acpop${ster_suffix}.ster"
********************************************************************************

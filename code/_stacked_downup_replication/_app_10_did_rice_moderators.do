********************************************************************************
* Presentation table A10: Downwind exposure x high rice production.
* Uses the population-based stacked treatment (combined_dt_pop/downup_ac_pop).
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

import delimited using "${int_data}/combined_dt_pop${sample}.csv", ///
    clear varnames(1)
keep if inrange(relative_monthyear, -5, 6)
keep if year < 2022 | (year == 2022 & month <= 8)
merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1
confirm variable rice_prod_aclvl_ahigh
assert inlist(rice_prod_aclvl_ahigh, 0, 1) if !missing(rice_prod_aclvl_ahigh)
drop if missing(rice_prod_aclvl_ahigh)

capture drop countk
gen countk = count * 1000
egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort)
egen relative_month_cohort = group(relative_monthyear cohort)
egen ac_relative_month_cohort = group(ac_uq_id relative_monthyear cohort)
egen cluster_grid = group(unique_small_grid_id cohort)
egen cluster_actime = group(ac_uq_id cohort monthyear)
gen byte nofe = 1
gen byte moderator = 0

local fe0 "nofe"
local fe1 "unique_small_grid_id_cohort"
local fe2 "unique_small_grid_id_cohort relative_month_cohort"
local fe3 "unique_small_grid_id_cohort ac_relative_month_cohort"
local common_rhs "ib0.downup_ac_pop##ib0.rice_prod_aclvl_ahigh av_wind_speed wind_direction"
do "${code}/_apply_analysis_subsample.do"
quietly reghdfejl countk `common_rhs', absorb(`fe3') ///
    vce(cluster cluster_grid cluster_actime)
gen byte common_sample = e(sample)
quietly count if common_sample
local common_n = r(N)
keep if common_sample
drop common_sample

egen byte tag_ac = tag(ac_uq_id)
quietly count if tag_ac
local numacs = r(N)
quietly summarize countk if downup_ac_pop == 1 & relative_monthyear <= -1
local ymean = r(mean)

est clear
local moderators_list moderator rice_prod_aclvl_ahigh
local i = 1
foreach mod of local moderators_list {
    replace moderator = `mod'
    local rhs "ib0.downup_ac_pop##ib0.`mod' av_wind_speed wind_direction"
    quietly summarize countk if downup_ac_pop == 1 & ///
        relative_monthyear <= -1 & moderator == 1
    local ymean2 = r(mean)
    foreach fe of numlist $fe_list {
        reghdfejl countk `rhs', absorb(`fe`fe'') ///
            vce(cluster cluster_grid cluster_actime)
        assert e(N) == `common_n'
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"
        local grid_label = cond(`fe' == 0, "N", "Y")
        estadd local gridfe "`grid_label'"
        local time_label = cond(`fe' == 2, "Y", "N")
        local actime_label = cond(`fe' == 3, "Y", "N")
        estadd local time "`time_label'"
        estadd local actimefe "`actime_label'"
        estadd local mod "`mod'"
        est store eq`i'
        local i = `i' + 1
    }
}
estwrite eq1 eq2 eq3 eq4 eq5 eq6 eq7 eq8 using ///
    "${tables}/_app_10_did_rice_moderators${sample}_rural_acpop${ster_suffix}.ster", replace
display as result "Saved updated presentation ster: _app_10_did_rice_moderators${sample}_rural_acpop${ster_suffix}.ster"
********************************************************************************

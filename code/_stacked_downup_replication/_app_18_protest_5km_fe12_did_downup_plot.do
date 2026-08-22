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

local protest_input ///
    "${int_data}/stacked_data_protest5km_election_sameterm${sample}.csv"
capture confirm file "`protest_input'"
if _rc {
    local protest_input ///
        "${int_data}/cohortes_protest_term/stacked_data_protest5km_election_sameterm${sample}.csv"
}
capture confirm file "`protest_input'"
if _rc {
    local protest_input ///
        "${int_data}/cohorts_protest_term/stacked_data_protest5km_election_sameterm${sample}.csv"
}
confirm file "`protest_input'"
display as text "Final same-term protest input: `protest_input'"
import delimited using "`protest_input'", clear varnames(1)

confirm variable cohort_id
confirm variable cohort_election_year
confirm variable cohort_term_start
confirm variable cohort_analysis_max
assert monthyear >= cohort_term_start
assert monthyear <= cohort_analysis_max
assert cohort_term_start <= cohort
assert inrange(cohort_analysis_max - cohort_term_start, 0, 59)
bysort cohort_id: assert cohort == cohort[1]
bysort cohort_id: assert cohort_election_year == cohort_election_year[1]
bysort cohort_id: assert cohort_term_start == cohort_term_start[1]
bysort cohort_id: assert cohort_analysis_max == cohort_analysis_max[1]
capture confirm variable relative_year_bin
if _rc {
    rename relative_year relative_year_bin
}
assert relative_year_bin == floor((monthyear - cohort) / 12)
drop if relative_year_bin == -5
display as text "Canonical protest sample: full same-term support except relative year -5"

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural) nogen
keep if ${is_rural_var} == 1

* Do not exclude grids intersecting more than one AC.
* merge m:1 unique_small_grid_id using "${int_data}/grids_with_more_1_ac.dta"
* drop if dpl_ac == 1
* drop _merge

capture drop countk
gen countk = count * 1000
egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
egen province_cohort = group(province cohort_id)
egen relativeyear_cohort = group(relative_year_bin cohort_id)
egen ac_elec_yr = group(ac_uq_id cohort_election_year cohort_id)

bysort unique_small_grid_id_cohort: egen byte has_pre = max(relative_year_bin < 0)
bysort unique_small_grid_id_cohort: egen byte has_post = max(relative_year_bin >= 0)
egen byte unit_tag = tag(unique_small_grid_id_cohort)
quietly count if unit_tag
local units_before = r(N)
quietly count if unit_tag & has_pre == 1 & has_post == 1
local units_balanced = r(N)
display as text "Grid-cohort units with pre and post periods: `units_balanced' of `units_before'"
keep if has_pre == 1 & has_post == 1
assert has_pre == 1 & has_post == 1
drop unit_tag has_pre has_post

gen post_ = relative_year_bin >= 0
gen moderator = ${downup_var}

local dep_var countk
local moderators_list ${downup_var}
local fe1 "unique_small_grid_id_cohort relativeyear_cohort province_cohort#election_year province_cohort#c.monthyear"
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

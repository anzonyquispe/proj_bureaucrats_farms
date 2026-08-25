********************************************************************************
* Protest DiD: three regular specifications followed by the same three
* specifications interacted with downup_ac_pop.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for the five sbatch-array parameters.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1/3"
    global ster_suffix  "_acpop"
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
    global downup_var "downup_ac_pop"
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

merge m:1 unique_small_grid_id month year using ///
    "${int_data}/grid_month_ac_area_tr.dta", ///
    keep(master match) keepusing(ac_area_tr)
assert _merge == 3
drop _merge
assert !missing(ac_area_tr)

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
keep if year < 2022 | (year == 2022 & month <= 8)
keep if inrange(relative_year_bin, -4, 4)
quietly summarize relative_year_bin
assert r(min) >= -4 & r(max) <= 4
display as text "Canonical protest DiD support restricted to: [" r(min) ", " r(max) "]"
* Always express the fire-count outcome in thousands.
capture drop countk
gen countk = count * 1000

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1

egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
capture drop province_cohort
egen province_cohort = group(province cohort_id)
egen monthyearco = group(monthyear cohort_id)
egen relativeyear_cohort = group(relative_year_bin cohort_id)

* The production stack must already contain both sides of the switch for every
* retained grid-cohort. Fail loudly instead of silently changing the sample.
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
gen moderator = 0

local fe1 "unique_small_grid_id_cohort"
local fe2 "unique_small_grid_id_cohort province_cohort#election_year"
local fe3 "unique_small_grid_id_cohort province_cohort#election_year province_cohort#c.monthyear"
local moderators_list moderator ${downup_var}

* Anchor every regular and interacted model to the sample retained by the
* richest FE specification with the full downup interaction.
local common_rhs "ib0.post_##ib0.treat##ib0.${downup_var} wind_direction av_wind_speed"
do "${code}/_apply_analysis_subsample.do"

quietly reghdfejl countk `common_rhs', ///
    absorb(`fe3' relativeyear_cohort) vce(cluster ac_area_tr)
gen byte common_sample = e(sample)
quietly count
local candidate_n = r(N)
quietly count if common_sample
local common_n = r(N)
display as text "Common-sample anchor: interacted FE specification 3"
display as text "Common estimation sample: `common_n' of `candidate_n' observations"
keep if common_sample
drop common_sample

egen tag_ac = tag(ac_uq_id)
count if tag_ac == 1
local numacs = r(N)

est clear
local i = 1
foreach mod of local moderators_list {
    replace moderator = `mod'
    local rhs "ib0.post_##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
    quietly summarize countk if treat == 1 & relative_year_bin <= -1
    local ymean = r(mean)
    quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)
    foreach fe of numlist $fe_list {
        reghdfejl countk `rhs', ///
            absorb(`fe`fe'' relativeyear_cohort) vce(cluster ac_area_tr)
        if e(N) != `common_n' {
            display as error "FE specification `fe' with moderator `mod' changed the anchored sample."
            exit 459
        }
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"
        estadd local fespec "`fe`fe'' relativeyear_cohort"
        estadd local gridfe "Y"
        estadd local time "Y"
        local election_label = cond(`fe' >= 2, "Y", "N")
        local provtrend_label = cond(`fe' == 3, "Y", "N")
        estadd local electionfe "`election_label'"
        estadd local provtrendfe "`provtrend_label'"
        estadd local mod "`mod'"
        local estname evreg`i'
        local i = `i' + 1
        est store `estname'
    }
}

estwrite evreg1 evreg2 evreg3 evreg4 evreg5 evreg6 using ///
    "${tables}/_main_4_protest_5km_fe12_did_downup${sample}_rural${ster_suffix}.ster", replace

********************************************************************************

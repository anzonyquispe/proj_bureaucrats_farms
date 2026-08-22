********************************************************************************
* _app_12_protest_5km_fe_did_rural.do
* Protest DiD analysis WITHOUT moderator - RURAL GRIDS ONLY
* 3 columns: 3 FE specs (baseline only, no downup_ac interaction)
********************************************************************************

********************************************************************************
* Setup - Only set globals if running standalone (not from master)
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    * Set toggles for standalone run
    global location "shell"
    global sample ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"

    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }
}

cd "${root}"

********************************************************************************
* Import Data
********************************************************************************

local protest_input ///
    "${root}/data_output/intermediate/stacked_data_protest5km_election_sameterm${sample}.csv"
capture confirm file "`protest_input'"
if _rc local protest_input ///
    "${root}/data_output/intermediate/cohortes_protest_term/stacked_data_protest5km_election_sameterm${sample}.csv"
capture confirm file "`protest_input'"
if _rc local protest_input ///
    "${root}/data_output/intermediate/cohorts_protest_term/stacked_data_protest5km_election_sameterm${sample}.csv"
confirm file "`protest_input'"
import delimited using "`protest_input'", clear varnames(1)

capture confirm variable relative_year_bin
if _rc rename relative_year relative_year_bin
assert relative_year_bin == floor((monthyear - cohort) / 12)
assert monthyear >= cohort_term_start
assert monthyear <= cohort_analysis_max
assert cohort_term_start <= cohort
assert inrange(cohort_analysis_max - cohort_term_start, 0, 59)
bysort cohort_id: assert cohort_election_year == cohort_election_year[1]

* Merge with rice moderators
merge m:1 unique_small_grid_id ac_uq_id using "data_output/intermediate/rice_moderators.dta"
keep if _merge == 3
drop _merge

* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge

* Keep only rural grids
keep if is_rural == 1
keep if year < 2022 | (year == 2022 & month <= 8)
keep if inrange(relative_year_bin, -4, 1)

display "Observations after rural filter: " _N

* Express the fire-count outcome in thousands in every regression.
capture drop countk
gen countk = count * 1000

********************************************************************************
* Generate Variables
********************************************************************************

sum relative_year_bin
local rmin = r(min)
gen post_ = relative_year_bin >= 0
gen moderator = 0

egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
egen monthyearco = group(monthyear cohort_id)
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

local dep_var countk
local rhs "ib0.post_##ib0.treat##ib0.moderator wind_direction av_wind_speed"

* FE specifications
local fe1 "unique_small_grid_id_cohort"
local fe2 "unique_small_grid_id_cohort monthyearco"
local fe3 "unique_small_grid_id_cohort province_cohort#c.monthyear"

* Statistics
quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1
local ymean_fmt = r(mean)
quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1
local ymean2_fmt = r(mean)
unique ac_uq_id
local numacs = r(unique)

********************************************************************************
* Run Regressions (only 3 FE specs, no moderator loop)
********************************************************************************

local i = 1

foreach fe of numlist 1/3 {

    reghdfejl `dep_var' `rhs', ///
        absorb(`fe`fe'' relativeyear_cohort) cluster(ac_elec_yr)

    * Store FE indicators
    estadd local gridfe "Y"
	estadd local time "Y"
    estadd local electionfe = cond(`fe' >= 2, "Y", "N")
    estadd local provtrendfe = cond(`fe' == 3, "Y", "N")
    estadd scalar ymean `ymean_fmt'
    estadd scalar ymean2 `ymean2_fmt'
    estadd scalar acq `numacs'

    est store evreg`i'
    local i = `i' + 1
}

********************************************************************************
* Save ster file
********************************************************************************

estwrite evreg* using "${code}/../../tables/_app_12_protest_5km_fe_did${sample}_rural.ster", replace

display "Ster: ${code}/../../tables/_app_12_protest_5km_fe_did${sample}_rural.ster"

********************************************************************************

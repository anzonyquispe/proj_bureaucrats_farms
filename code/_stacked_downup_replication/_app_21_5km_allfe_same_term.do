*-------------------------------------------------------------------------------
* _app_21_5km_allfe_same_term.do
* Protest Event Study - RURAL GRIDS ONLY - ALL 32 FE SPECIFICATIONS
*
* Data: stacked_data_protest5km_election_sameterm.csv, the election-cohort variant of the
*       protest stack. Cohorts are (switch month x election year) and every grid
*       in a stack starts at the first month of the election term containing the
*       treatment, so the pre-period trimming that this dofile used to do by hand
*       is already baked into the data.
*
* Output: _app_21_5km_allfe_same_term.csv (32 estimates, no moderators)
*-------------------------------------------------------------------------------

********************************************************************************
* Setup - Only set globals if running standalone (not from master)
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    * Set toggles for standalone run
    global location "shell"
    global sample ""
    global is_rural_var "is_rural"
    global fe_list "1/32"
    global ster_suffix ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"

    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }
	* Load custom ado for exporting results
	qui do "${root}/code/_replication_rural/estsave_csv.ado"

}


*-------------------------------------------------------------------------------
* Import and Merge Data
*-------------------------------------------------------------------------------
cd "${root}"
local protest_input ///
    "${root}/data_output/intermediate/stacked_data_protest5km_election_sameterm${sample}.csv"
capture confirm file "`protest_input'"
if _rc {
    local protest_input ///
        "${root}/data_output/intermediate/cohortes_protest_term/stacked_data_protest5km_election_sameterm${sample}.csv"
}
capture confirm file "`protest_input'"
if _rc {
    local protest_input ///
        "${root}/data_output/intermediate/cohorts_protest_term/stacked_data_protest5km_election_sameterm${sample}.csv"
}
confirm file "`protest_input'"
import delimited using "`protest_input'", clear varnames(1)

d *

* The builder truncates each stack at the first month of the election term of the
* treatment, and every cohort shares one election year. Verify both instead of
* trimming here.
assert monthyear >= cohort_term_start
assert monthyear <= cohort_analysis_max
assert cohort_term_start <= cohort
assert inrange(cohort_analysis_max - cohort_term_start, 0, 59)
bys cohort_id: assert cohort_election_year == cohort_election_year[1]

quietly levelsof cohort_id, local(stack_ids)
local nstacks : word count `stack_ids'
display "Number of stacks (cohort x election year): `nstacks'"

capture confirm variable relative_year_bin
if _rc {
    confirm variable relative_year
    rename relative_year relative_year_bin
}
assert relative_year_bin == floor((monthyear - cohort) / 12)
keep if inrange(relative_year_bin, -4, 1)
display as text "Final protest event-study sample: relative_year_bin in [-4, 1]"

* election_year and yeargov arrive as floats; the factor and interaction
* operators below need integers.
foreach v of varlist election_year yeargov {
    capture confirm numeric variable `v'
    if _rc destring `v', replace
}
recast int election_year, force
recast byte yeargov, force

* Merge with rice moderators (kept as the sample definition, not as moderators)
merge m:1 unique_small_grid_id ac_uq_id using "data_output/intermediate/rice_moderators.dta"
keep if _merge == 3
drop _merge

* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge

* Keep only the final rural event-study sample.
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

display "Observations after rural filter: " _N

*-------------------------------------------------------------------------------
* Generate Variables
*-------------------------------------------------------------------------------

gen provsel = 0
replace provsel = 1 if province == "Punjab_IND" | province == "Haryana"

* Fixed-effect groupings. They key off cohort_id, not cohort: one switch month
* now hosts several stacks (one per election year), so grouping on cohort would
* silently pool them.
egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
egen monthyearco                 = group(month year cohort_id)
egen province_cohort             = group(cohort_id province)
egen ac_elec_yr                  = group(ac_uq_id cohort_election_year cohort_id)

* Retain only grid-cohort units observed on both sides of the protest switch.
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

sum relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin - `rmin' + 1
local base = -1 - `rmin' + 1

gen countk = count * 1000

*-------------------------------------------------------------------------------
* Regression Setup
*-------------------------------------------------------------------------------

local dep_var countk

* Keep the standard moderator structure. The zero-valued stub makes this a
* plain event study while retaining the same coefficient naming convention as
* the other production event-study dofiles.
gen byte moderator = 0
local moderators_list moderator
* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh

* Filters
local filter1 "1"   // all sample

* Fixed effects: every combination of the five components on top of grid^cohort
local fe1  "unique_small_grid_id_cohort"
local fe2  "unique_small_grid_id_cohort monthyearco"
local fe3  "unique_small_grid_id_cohort province_cohort#c.monthyear"
local fe4  "unique_small_grid_id_cohort yeargov"
local fe5  "unique_small_grid_id_cohort province_cohort#election_year"
local fe6  "unique_small_grid_id_cohort province_cohort#election_year#yeargov"
local fe7  "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear"
local fe8  "unique_small_grid_id_cohort monthyearco yeargov"
local fe9  "unique_small_grid_id_cohort monthyearco province_cohort#election_year"
local fe10 "unique_small_grid_id_cohort monthyearco province_cohort#election_year#yeargov"
local fe11 "unique_small_grid_id_cohort province_cohort#c.monthyear yeargov"
local fe12 "unique_small_grid_id_cohort province_cohort#c.monthyear province_cohort#election_year"
local fe13 "unique_small_grid_id_cohort province_cohort#c.monthyear province_cohort#election_year#yeargov"
local fe14 "unique_small_grid_id_cohort yeargov province_cohort#election_year"
local fe15 "unique_small_grid_id_cohort yeargov province_cohort#election_year#yeargov"
local fe16 "unique_small_grid_id_cohort province_cohort#election_year province_cohort#election_year#yeargov"
local fe17 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear yeargov"
local fe18 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear province_cohort#election_year"
local fe19 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear province_cohort#election_year#yeargov"
local fe20 "unique_small_grid_id_cohort monthyearco yeargov province_cohort#election_year"
local fe21 "unique_small_grid_id_cohort monthyearco yeargov province_cohort#election_year#yeargov"
local fe22 "unique_small_grid_id_cohort monthyearco province_cohort#election_year province_cohort#election_year#yeargov"
local fe23 "unique_small_grid_id_cohort province_cohort#c.monthyear yeargov province_cohort#election_year"
local fe24 "unique_small_grid_id_cohort province_cohort#c.monthyear yeargov province_cohort#election_year#yeargov"
local fe25 "unique_small_grid_id_cohort province_cohort#c.monthyear province_cohort#election_year province_cohort#election_year#yeargov"
local fe26 "unique_small_grid_id_cohort yeargov province_cohort#election_year province_cohort#election_year#yeargov"
local fe27 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear yeargov province_cohort#election_year"
local fe28 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear yeargov province_cohort#election_year#yeargov"
local fe29 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear province_cohort#election_year province_cohort#election_year#yeargov"
local fe30 "unique_small_grid_id_cohort monthyearco yeargov province_cohort#election_year province_cohort#election_year#yeargov"
local fe31 "unique_small_grid_id_cohort province_cohort#c.monthyear yeargov province_cohort#election_year province_cohort#election_year#yeargov"
local fe32 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear yeargov province_cohort#election_year province_cohort#election_year#yeargov"

local nfe = 32
egen relativeyear_cohort = group(relative_year_bin cohort_id)

*-------------------------------------------------------------------------------
* Loop over fixed-effect specifications
*-------------------------------------------------------------------------------

local i = 1

foreach mod of local moderators_list {
    local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"

    * Select filter condition
    local fcond `filter1'

    * Project-standard treated-group pre-treatment means.
    quietly summarize `dep_var' if `fcond' & treat == 1 & relative_year_bin <= -1
    local ymean = r(mean)
    quietly summarize `dep_var' if `fcond' & treat == 1 & ///
        relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)

    * Count number of unique ACs in subsample
    unique ac_uq_id if `fcond'
    local numacs = r(unique)

    foreach fe of numlist 1/`nfe' {

        * Select FE spec
        local fespec `fe`fe''
        local padded " `fespec' "

        display _newline "FE`fe': `fespec'"

        * Run regression with clustering
        reghdfejl `dep_var' `rhs' if `fcond', ///
            absorb(`fespec' relativeyear_cohort) vce(cluster ac_elec_yr)

        * Attach all metadata before storing the estimate.
        estadd scalar ymean `ymean'
        estadd scalar ymean2 `ymean2'
        estadd scalar acq `numacs'
        estadd local smpl "Rural"
        estadd local mod "`mod'"
        estadd local fespec "`fespec' relativeyear_cohort"
        estadd local fename "FE`fe'"
        * FE indicators, read off the selected specification
        estadd local gridfe "Y"
        estadd local mtyr        = cond(strpos("`padded'", " monthyearco ") > 0, "Y", "N")
        estadd local provtrend   = cond(strpos("`padded'", " province_cohort#c.monthyear ") > 0, "Y", "N")
        estadd local yeargov     = cond(strpos("`padded'", " yeargov ") > 0, "Y", "N")
        estadd local provelec    = cond(strpos("`padded'", " province_cohort#election_year ") > 0, "Y", "N")
        estadd local provelecgov = cond(strpos("`padded'", " province_cohort#election_year#yeargov ") > 0, "Y", "N")

        est store evreg`i'

        local i = `i' + 1
        display("`i'")
    }
}

*-------------------------------------------------------------------------------
* Export Results
*-------------------------------------------------------------------------------

local est_list
forvalues j = 1/`nfe' {
    local est_list `est_list' evreg`j'
}

estsave_csv `est_list' using "${root}/tex/paper/tables/_app_21_5km_allfe_same_term${sample}.csv", replace

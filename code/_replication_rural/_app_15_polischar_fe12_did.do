********************************************************************************
* _app_15_polischar_fe12_did_rural.do
* Politician characteristics DiD WITHOUT moderator - RURAL GRIDS ONLY
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

import delimited using "${root}/data_output/intermediate/politicians_characteristics${sample}.csv", clear varnames(1)

* Merge with rice moderators
merge m:1 unique_small_grid_id ac_uq_id using "${root}/data_output/intermediate/rice_moderators.dta"
keep if _merge == 3
drop _merge

* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge

* Keep only rural grids
keep if is_rural == 1

display "Observations after rural filter: " _N

* Drop grids with more than 1 ac
merge m:1 unique_small_grid_id using "data_output/intermediate/grids_with_more_1_ac.dta"
drop if dpl_ac ==1
drop _merge

********************************************************************************
* Generate Variables
********************************************************************************

* Date
gen date_ym = ym(year, month)

* Fixed Effects
egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort)
egen monthyearco = group(month year cohort)
egen ac_elec_yr = group(ac_uq_id election_year cohort)
egen province_cohort = group(cohort province)


* Government year
bys ac_uq_id election_year: egen min_monthyear = min(date_ym)
gen gov_year = date_ym - min_monthyear
replace gov_year = gov_year / 12

* Relative years
sum relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin - `rmin' + 1
local base = -1 - `rmin' + 1
gen post_ = (relative_year_bin >= 0)

* Ever treated
bys unique_small_grid_id: egen TREAT_down = max(downup_ac)

********************************************************************************
* Regression Setup
********************************************************************************
gen countk = count * 1000
local dep_var countk
local rhs "ib0.post_##ib0.treat wind_direction av_wind_speed"

* FE specifications
local fe1 "unique_small_grid_id_cohort relative_year_bin_aux"
local fe2 "unique_small_grid_id_cohort relative_year_bin_aux province_cohort#election_year"
local fe3 "unique_small_grid_id_cohort relative_year_bin_aux province_cohort#election_year province_cohort#c.monthyear"

********************************************************************************
* Run Regressions (only 3 FE specs, no moderator)
********************************************************************************

* Compute mean of dep var where untreated
quietly summarize `dep_var' if treat == 1 & relative_year_bin < 0
local ymean = r(mean)
local ymean_fmt = string(`ymean', "%9.3f")

* Count number of unique ACs
unique ac_uq_id
local numacs = r(unique)

local i = 1

forvalues feval = 1/3 {

    local fespec `fe`feval''

    * Run regression with clustering
    reghdfejl `dep_var' `rhs', absorb(`fespec') vce(cluster ac_elec_yr)

    * Store statistics
    estadd local ymean "`ymean_fmt'"
    estadd local acq "`numacs'"
    estadd local gridfe "Y"
	estadd local time "Y"
    estadd local electionfe = cond(`feval' >= 2, "Y", "N")
    estadd local provtrendfe = cond(`feval' == 3, "Y", "N")

    est store evreg`i'
    local i = `i' + 1
    display("`i'")
}

********************************************************************************
* Save ster file
********************************************************************************

estwrite evreg* using "${root}/tex/paper/tables/_app_15_polischar_fe12_did${sample}_rural.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_15_polischar_fe12_did${sample}_rural.ster"

********************************************************************************

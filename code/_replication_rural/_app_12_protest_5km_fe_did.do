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

import delimited using "${root}/data_output/intermediate/stacked_data_protest${sample}.csv", clear varnames(1)

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

display "Observations after rural filter: " _N

********************************************************************************
* Generate Variables
********************************************************************************

sum relative_year_bin
local rmin = r(min)
gen post_ = relative_year_bin >= 0

local dep_var countk
local rhs "ib0.post_##ib0.treat wind_direction av_wind_speed"

* FE specifications
local fe1 "unique_small_grid_id_cohort relative_year_bin"
local fe2 "unique_small_grid_id_cohort relative_year_bin province_cohort#election_year"
local fe3 "unique_small_grid_id_cohort relative_year_bin province_cohort#election_year province_cohort#c.monthyear "

* Statistics
quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1
local ymean_fmt = r(mean)
unique ac_uq_id
local numacs = r(unique)

********************************************************************************
* Run Regressions (only 3 FE specs, no moderator loop)
********************************************************************************

local i = 1

foreach fe of numlist 1/3 {

    reghdfejl `dep_var' `rhs', absorb(`fe`fe'') cluster(ac_area_tr)

    * Store FE indicators
    estadd local gridfe "Y"
	estadd local time "Y"
    estadd local electionfe = cond(`fe' >= 2, "Y", "N")
    estadd local provtrendfe = cond(`fe' == 3, "Y", "N")
    estadd scalar ymean `ymean_fmt'
    estadd scalar acq `numacs'

    est store evreg`i'
    local i = `i' + 1
}

********************************************************************************
* Save ster file
********************************************************************************

estwrite evreg* using "${root}/tex/paper/tables/_app_12_protest_5km_fe_did${sample}_rural.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_12_protest_5km_fe_did${sample}_rural.ster"

********************************************************************************

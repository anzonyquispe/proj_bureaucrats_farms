********************************************************************************
* _app_13_protest_5km_fe12_did_ricemods_rural.do
* Protest DiD analysis with rice moderators - RURAL GRIDS ONLY
* 3 columns: Rice Area, Harvested Rice Area, Rice Production
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

* Drop grids with more than 1 ac
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/grids_with_more_1_ac.dta"
drop if dpl_ac ==1
drop _merge

********************************************************************************
* Generate Variables
********************************************************************************

* Create count in thousands if not exists
capture confirm variable countk
if _rc {
    gen countk = count * 1000
}

* Post indicator
gen post_ = relative_year_bin >= 0

* Controls
local dep_var countk
local rhs "wind_direction av_wind_speed"

* FE specifications (Grid, Relative Year, Government Term-Year)
local fe12 "unique_small_grid_id_cohort relative_year_bin province_cohort#election_year province_cohort#c.monthyear "

* Statistics
unique ac_uq_id
local numacs = r(unique)

* Mean DV for control group
quietly summarize `dep_var' if treat == 1 & post_ == 0
local ymean = r(mean)
local modlist rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh

********************************************************************************
* Run Regressions - 3 Rice Moderators
********************************************************************************
local i = 1
foreach mod of local modlist{

	quietly summarize `dep_var' if treat == 1 & post_ == 0 & `mod' == 1
	local ymean2 = r(mean)
	
	quietly summarize `dep_var' if treat == 1 & post_ == 0 & `mod' == 0
	local ymean3 = r(mean)


	* Equation 1: Rice Area
	reghdfejl `dep_var' ib0.post_##ib0.treat##ib0.`mod' `rhs', ///
		absorb(`fe12') cluster(ac_area_tr)
	estadd local gridfe "Y"
	estadd local time "Y"
	estadd local electionfe "Y"
	estadd local provtrendfe "Y"
	estadd scalar ymean `ymean'
	estadd scalar ymean2 `ymean2'
	estadd scalar ymean3 `ymean3'
	estadd scalar acq `numacs'
	est store eq`i'
	local i = `i' + 1
}


********************************************************************************
* Save ster file
********************************************************************************

estwrite eq1 eq2 eq3 using "${root}/tex/paper/tables/_app_13_protest_5km_fe12_did_ricemods${sample}_rural.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_13_protest_5km_fe12_did_ricemods${sample}_rural.ster"

********************************************************************************

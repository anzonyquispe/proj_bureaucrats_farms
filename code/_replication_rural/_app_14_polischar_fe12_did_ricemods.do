********************************************************************************
* _app_14_polischar_fe12_did_ricemods_rural.do
* Politician characteristics DiD with rice moderators - RURAL GRIDS ONLY
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


* FE specifications
local dep_var countk
local rhs "wind_direction av_wind_speed"
local fe12 "unique_small_grid_id_cohort relative_year_bin_aux province_cohort#election_year province_cohort#c.monthyear"

unique ac_uq_id
local numacs = r(unique)
gen moderator = 0
local mods_list moderator rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
********************************************************************************
* Run Regressions
********************************************************************************

local i = 1

foreach mod of local mods_list {

	quietly summarize `dep_var' if treat == 1 & post_ == 0
	local ymean = cond(r(N) == 0, " ", string(r(mean), "%9.3f"))

	quietly summarize `dep_var' if treat == 1 & post_ == 0 & `mod' == 1
	local ymean2 = cond(r(N) == 0, " ", string(r(mean), "%9.3f"))
	
	quietly summarize `dep_var' if treat == 1 & post_ == 0 & `mod' == 0
	local ymean3 = cond(r(N) == 0, " ", string(r(mean), "%9.3f"))

	reghdfejl `dep_var' ib0.post_##ib0.treat##ib0.`mod' `rhs', absorb(`fe12') cluster(ac_elec_yr)

	* Store FE indicators
	estadd local gridfe "Y"
	estadd local time "Y"
	estadd local electionfe "Y"
	estadd local provtrendfe "Y"
	estadd local ymean "`ymean'"
	estadd local ymean2 "`ymean2'"
	estadd local ymean3 "`ymean3'"
	estadd scalar acq `numacs'

	est store evreg`i'
	local i = `i' + 1

}

********************************************************************************
* Save ster file
********************************************************************************

estwrite evreg* using "${root}/tex/paper/tables/_app_14_polischar_fe12_did_ricemods${sample}_rural.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_14_polischar_fe12_did_ricemods${sample}_rural.ster"

********************************************************************************

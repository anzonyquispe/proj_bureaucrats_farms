*-------------------------------------------------------------------------------
* _app_16_polischar_fe12_evst_all_rural.do
* Politician Characteristics Event Study - RURAL GRIDS ONLY
* Output: _app_16_polischar_fe12_evst_all_rural.csv
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

* Import politician characteristics data
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

*-------------------------------------------------------------------------------
* Generate Variables
*-------------------------------------------------------------------------------

* Date
gen date_ym = ym(year, month)

* Generation of Fixed Effects
egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort)
egen monthyearco = group(month year cohort)
egen ac_elec_yr = group(ac_uq_id election_year cohort)
egen province_cohort = group(cohort province)

* Government year
bys ac_uq_id election_year: egen min_monthyear = min(date_ym)
gen gov_year = date_ym - min_monthyear
replace gov_year = gov_year / 12
g yeargov = int(gov_year + 1)

* Generation of Relative Years
sum relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin - `rmin' + 1
local base = -1 - `rmin' + 1
dis `base'
g post_ = (relative_year_bin >= 0)

*-------------------------------------------------------------------------------
* Regression Setup
*-------------------------------------------------------------------------------

gen countk = count * 1000
local dep_var countk


* FE13 specification
local fe12 "unique_small_grid_id_cohort province_cohort#c.monthyear province_cohort#election_year"

* Filters
local filter1 "1"   // all sample

* Moderator variables
local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh

*-------------------------------------------------------------------------------
* Loop over moderators
*-------------------------------------------------------------------------------

local i = 1
gen moderator = 0

foreach mod of local moderators_list {
	
	local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"

    replace moderator = `mod'

    * Select filter condition
    local fcond `filter1'

    * Compute mean of dep var where untreated
    quietly summarize `dep_var' if `fcond' & treat == 1 & relative_year_bin < 0
    local ymean = r(mean)
	

    * Count number of unique ACs in subsample
    unique ac_uq_id if `fcond'
    local numacs = r(unique)

    * Select FE spec
    local fespec `fe12'

    * Run regression with clustering
    reghdfejl `dep_var' `rhs' if `fcond', absorb(`fespec') vce(cluster ac_elec_yr)

    * Store coefficient + SE of main var
    est store evreg`i'
    estadd scalar ymean = `ymean'
    estadd scalar acq = `numacs'
    estadd local sample "Rural"
    * FE indicators for FE13 specification
    estadd local gridfe "Y"
    estadd local mtyr "Y"
    estadd local provtrend "Y"
    estadd local yeargov "Y"

    local i = `i' + 1
    display("`i'")
}

*-------------------------------------------------------------------------------
* Export Results
*-------------------------------------------------------------------------------

estsave_csv evreg1 evreg2 evreg3 evreg4 evreg5 using "${root}/tex/paper/tables/_app_16_polischar_fe12_evst_all${sample}_rural.csv", replace

********************************************************************************
* _app_main_did_by_year_rural.do
* Replicates _app_main_did_by_year.R - RURAL GRIDS ONLY
* DiD regressions by agricultural year (Sep-Aug)
********************************************************************************

********************************************************************************
* Setup - Only set globals if running standalone (not from master)
********************************************************************************

if "$root" == "" {
    clear all
    set more off

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

import delimited "${root}/data_output/intermediate/0_master_merge_data_gen${sample}.csv", clear

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

* Create count in thousands
gen countk = count * 1000

* Filter data: year < 2022 or (year == 2022 & month <= 8)
keep if year < 2022 | (year == 2022 & month <= 8)

* Sort data
sort unique_small_grid_id monthyear

********************************************************************************
* Encode IDs
********************************************************************************

capture confirm numeric variable unique_small_grid_id
if _rc {
    encode unique_small_grid_id, gen(grid_id)
}
else {
    gen grid_id = unique_small_grid_id
}

capture confirm numeric variable ac_uq_id
if _rc {
    encode ac_uq_id, gen(ac_id)
}
else {
    gen ac_id = ac_uq_id
}

* Create cluster variable
egen cluster_acmonth = group(ac_id monthyear)
bysort unique_small_grid_id: egen treat = max(downup_ac)


* Count unique ACs
unique ac_id
local numacs = r(unique)

********************************************************************************
* Run Regressions by Agricultural Year (Sep-Aug)
********************************************************************************

global controls av_wind_speed wind_direction

* Store year labels for table header
local yearlabels ""

local i = 1
forvalues yr = 2012/2021 {

    local yr_next = `yr' + 1

    * Define agricultural year: Sep of yr to Aug of yr+1
    * (year == yr & month >= 9) | (year == yr+1 & month <= 8)

    preserve
		keep if (year == `yr' & month >= 9) | (year == `yr_next' & month <= 8)

		* Calculate mean DV for this year
		summarize countk if treat == 1 & downup_ac == 0
		local meandv`i' = string(r(mean), "%9.2f")

		* Run regression
		reghdfejl countk downup_ac $controls, ///
			absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)

		* Store statistics
		estadd local gridfe "Y"
		estadd local acmonthfe "Y"
		estadd local ymean "`meandv`i''"
		estadd local acq "`numacs'"
		est store eq`i'
		
    restore

    * Build year label
    local yearlabels "`yearlabels' `yr'/`yr_next'"

    local i = `i' + 1
}

********************************************************************************
* Save ster file
********************************************************************************

estwrite eq* using "${root}/tex/paper/tables/_app_8_main_did_by_year${sample}_rural.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_8_main_did_by_year${sample}_rural.ster"

********************************************************************************

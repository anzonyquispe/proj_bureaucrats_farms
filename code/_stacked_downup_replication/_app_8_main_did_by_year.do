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
    global is_rural_var "is_rural"
    global fe_list "1/10"
    global ster_suffix ""

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
global int_farms "${root}/data_output/intermediate"
global table_farms "${root}/tex/paper/tables"
global figure_farms "${root}/tex/paper/figures"
********************************************************************************
* Import Data
********************************************************************************

import delimited using "${int_farms}/combined_dt_pop${sample}.csv", clear varnames(1)

* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge

* Keep only rural grids
keep if ${is_rural_var} == 1

display "Observations after rural filter: " _N

* Do not drop grids that intersect more than one assembly constituency.
* merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/grids_with_more_1_ac.dta"
* drop if dpl_ac == 1
* drop _merge

* Create count in thousands
capture drop countk
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

* Create cluster variable (stacked: interact with cohort)
global cluster unique_small_grid_id#cohort ac_uq_id#cohort#monthyear


* Count unique ACs
egen tag_ac = tag(ac_id)
count if tag_ac == 1
local numacs = r(N)

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

		* Project-standard treated-group pre-treatment means for this subsample.
		gen relative_year_bin = floor(relative_monthyear / 12)
		gen moderator = 0
		quietly summarize countk if treat == 1 & relative_year_bin <= -1
		local meandv`i' = r(mean)
		quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
		local meandv2`i' = r(mean)

		* Run regression
		reghdfejl countk downup_ac_pop $controls , ///
			absorb(grid_id#cohort ac_id#monthyear#cohort) cluster($cluster )

		* Store statistics
		estadd local gridfe "Y"
		estadd local acmonthfe "Y"
		estadd scalar ymean = `meandv`i''
		estadd scalar ymean2 = `meandv2`i''
		estadd scalar acq = `numacs'
		est store eq`i'
		
    restore

    * Build year label
    local yearlabels "`yearlabels' `yr'/`yr_next'"

    local i = `i' + 1
}

********************************************************************************
* Save ster file
********************************************************************************

estwrite eq* using ///
    "${root}/tex/paper/tables/_app_8_main_did_by_year${sample}_rural_stacked${ster_suffix}.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_8_main_did_by_year${sample}_rural_stacked${ster_suffix}.ster"

********************************************************************************

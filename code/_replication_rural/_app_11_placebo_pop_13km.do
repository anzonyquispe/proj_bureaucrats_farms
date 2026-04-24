********************************************************************************
* _app_11_placebo_pop_13km_rural.do
* Placebo test: Does farmers' pro-sociality explain the results? - RURAL ONLY
* Tests whether fires decrease when downwind population is larger in a 13km
* radius circle (median size of assembly constituency)
*
* From paper Section 3.3.1: "Farmers' Pro-sociality and Political Enforcement"
* "We test prosocial behavior of farmers. When a large number of people is
*  affected by crop burning, farmers may reduce the number of fires given
*  that it may affect population health."
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

import delimited "${root}/data_output/intermediate/0_master_merge_data_gen${sample}.csv", clear

* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge

* Keep only rural grids
keep if is_rural == 1

display "Observations after rural filter: " _N

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
rename downup_13kmpl downup_pop_13km

********************************************************************************
* Create placebo treatment variable
* downup_pop_13km should be in the data: 1 if population downwind > upwind
* in a 13km radius circle around each grid
********************************************************************************

* Check if variable exists, if not create placeholder
capture confirm variable downup_pop_13km
if _rc {
    display as error "Variable downup_pop_13km not found in data"
    display as error "This variable should indicate whether downwind pop > upwind pop"
    display as error "in a 13km radius circle around each grid"
    exit 1
}

********************************************************************************
* Calculate statistics
********************************************************************************

* Count unique ACs
unique ac_id
local numacs = r(unique)
bysort unique_small_grid_id: egen treat = max(downup_pop_13km)

global controls av_wind_speed wind_direction

* Define sample conditions and labels
local cond1 "downup_pop_13km == 0 & treat == 1"
local cond2 "downup_pop_13km == 0 & downup_ac == 1 & treat == 1"
local cond3 "downup_pop_13km == 0 & downup_ac == 0 & treat == 1"

local if2 "if downup_ac == 1"
local if3 "if downup_ac == 0"

* Pre-compute means
quietly summarize countk if downup_pop_13km == 0 & treat == 1
local meandv = cond(r(N) == 0, ".", string(r(mean), "%9.3f"))

* Run regressions
forvalues i = 1/3 {
    reghdfejl countk downup_pop_13km $controls `if`i'', ///
        absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
    estadd local gridfe    "Y"
    estadd local acmonthfe "Y"
    estadd local ymean     "`meandv'"
    estadd local acq       "`numacs'"
    est store eq`i'
}

********************************************************************************
* Save ster file
********************************************************************************

estwrite eq* using "${root}/tex/paper/tables/_app_11_placebo_pop_13km${sample}_rural.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_11_placebo_pop_13km${sample}_rural.ster"

********************************************************************************

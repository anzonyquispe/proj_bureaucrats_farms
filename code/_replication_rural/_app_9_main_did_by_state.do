********************************************************************************
* _app_main_did_by_state_rural.do
* Replicates _app_main_did_by_state.R - RURAL GRIDS ONLY
* DiD regressions by state/province
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
bys unique_small_grid_id: egen treat_wind = max(downup_ac)

********************************************************************************
* Get list of states (using numeric encoding to handle spaces)
********************************************************************************

* Encode province to handle names with spaces (like "Uttar Pradesh")
encode province, gen(province_id)
label list province_id

* Get number of states
summarize province_id
local nstates = r(max)
display "Number of states: `nstates'"

********************************************************************************
* Run Regressions by State
********************************************************************************

global controls av_wind_speed wind_direction

local i = 1
local state_labels ""

forvalues prov_num = 1/`nstates' {

    * Get province name from label
    local st : label province_id `prov_num'
    display "Running regression for: `st'"

    preserve
    keep if province_id == `prov_num'

    * Count unique ACs for this state
    unique ac_id
    local numacs`i' = r(unique)

    * Calculate mean DV for this state
    summarize countk if treat_wind == 1 & downup_ac == 0
    local meandv`i' = string(r(mean), "%9.3f")

    * Run regression
    reghdfejl countk downup_ac $controls, ///
        absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)

    * Store statistics
    estadd local gridfe "Y"
    estadd local acmonthfe "Y"
    estadd local ymean "`meandv`i''"
    estadd local acq "`numacs`i''"

    est store eq`i'

    restore

    * Build state label (clean name for table)
    local clean_st = subinstr("`st'", "_", " ", .)
    local clean_st = subinstr("`clean_st'", "IND", "", .)
    local state_labels `"`state_labels' "`clean_st'""'

    local i = `i' + 1
}

local nregs = `i' - 1

********************************************************************************
* Save ster file
********************************************************************************

estwrite eq* using "${root}/tex/paper/tables/_app_9_main_did_by_state${sample}_rural.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_9_main_did_by_state${sample}_rural.ster"

********************************************************************************

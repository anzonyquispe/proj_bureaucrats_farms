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
    global is_rural_var "is_rural"
    global fe_list "1/4"
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
global table_farms "${code}/../../tables"
global figure_farms "${code}/../../figures"
********************************************************************************
* Import Data
********************************************************************************

import delimited using "${int_farms}/combined_dt_pop${sample}.csv", clear varnames(1)
keep if inrange(relative_monthyear, -5, 6)
display as text "Final event-study sample: relative_monthyear in [-5, 6]"

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

* FE
global setfe ac_id#cohort ac_id#monthyear#cohort

* Controls
global controls av_wind_speed wind_direction

* Cluster variables
global cluster unique_small_grid_id#cohort ac_uq_id#cohort#monthyear
bys unique_small_grid_id: egen treat_wind = max(downup_ac_pop)

local i = 1
local state_labels ""

forvalues prov_num = 1/`nstates' {

    * Get province name from label
    local st : label province_id `prov_num'
    display "Running regression for: `st'"

    preserve
    keep if province_id == `prov_num'

    * Count unique ACs for this state
    egen tag_ac = tag(ac_id)
    count if tag_ac == 1
    local numacs`i' = r(N)

    * Project-standard treated-group pre-treatment means for this state.
    gen relative_year_bin = floor(relative_monthyear / 12)
    gen moderator = 0
    quietly summarize countk if treat == 1 & relative_year_bin <= -1
    local meandv`i' = r(mean)
    quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local meandv2`i' = r(mean)

    * Run regression
    reghdfejl countk downup_ac_pop $controls, ///
        absorb(grid_id#cohort ac_id#monthyear#cohort) cluster($cluster)

    * Store statistics
    estadd local gridfe "Y"
    estadd local acmonthfe "Y"
    estadd scalar ymean = `meandv`i''
    estadd scalar ymean2 = `meandv2`i''
    estadd scalar acq = `numacs`i''

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

estwrite eq* using ///
    "${code}/../../tables/_app_9_main_did_by_state${sample}_rural_stacked${ster_suffix}.ster", replace

display "Ster: ${code}/../../tables/_app_9_main_did_by_state${sample}_rural_stacked${ster_suffix}.ster"

********************************************************************************

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

import delimited using ///
    "${int_farms}/main_downup_ac_pop_esample${sample}.csv", clear varnames(1)
display as text "Loaded canonical main specification-4 sample: " _N " rows"

* Create count in thousands
capture drop countk
gen countk = count * 1000

* Sort data
sort unique_small_grid_id monthyear

********************************************************************************
* Encode IDs
********************************************************************************

capture drop grid_id ac_id
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

    * Run regression
    reghdfejl countk downup_ac_pop $controls, ///
        absorb(grid_id#cohort ac_id#monthyear#cohort) cluster($cluster)
    gen byte state_sample = e(sample)

    * Statistics use the exact state-regression sample, itself restricted to
    * the canonical specification-4 population sample.
    egen byte tag_ac = tag(ac_id) if state_sample == 1
    quietly count if tag_ac == 1
    local numacs`i' = r(N)
    gen byte moderator = 0
    quietly summarize countk if treat == 1 & relative_monthyear <= -1 & state_sample == 1
    local meandv`i' = r(mean)
    quietly summarize countk if treat == 1 & relative_monthyear <= -1 & moderator == 1 & state_sample == 1
    local meandv2`i' = r(mean)

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

********************************************************************************
* _app_main_did_downup_area_ac_dv_rural.do
* Replicates _app_main_did_downup_area_ac_dv.R - RURAL GRIDS ONLY
* Different dependent variables: Any Fire, Log Fires, Mean Brightness
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

import delimited "${int_farms}/combined_dt_pop.csv", clear

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

********************************************************************************
* Create dependent variables
********************************************************************************

* Any fire (binary)
gen anyfire = (countk > 0)

* Log fires
gen logfire = ln(count + 1)

* Mean brightness - replace missing with 0
replace mean_brightness = 0 if missing(mean_brightness)

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



* Count unique ACs
unique ac_id
local numacs = r(unique)

********************************************************************************
* Calculate Mean DV for control group (downup_ac_pop == 0)
********************************************************************************
bys unique_small_grid_id: egen treat = max(downup_ac_pop)
summarize anyfire if downup_ac_pop == 0 & treat == 1
local meandv1 = string(r(mean), "%9.4f")

summarize logfire if downup_ac_pop == 0  & treat == 1
local meandv2 = string(r(mean), "%9.4f")

summarize mean_brightness if downup_ac_pop == 0  & treat == 1
local meandv3 = string(r(mean), "%9.2f")

********************************************************************************
* Run Regressions
********************************************************************************

* FE
global setfe grid_id#cohort ac_id#monthyear#cohort

* Controls
global controls av_wind_speed wind_direction

* Cluster variables
global cluster ac_uq_id#cohort#monthyear unique_small_grid_id#cohort



* Eq1: Any Fire
reghdfejl anyfire downup_ac_pop $controls , ///
    absorb($setfe ) cluster($cluster )
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd local ymean "`meandv1'"
estadd local acq "`numacs'"
est store eq1

* Eq2: Log Fires
reghdfejl logfire downup_ac_pop $controls , ///
    absorb($setfe ) cluster($cluster )
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd local ymean "`meandv2'"
estadd local acq "`numacs'"
est store eq2

* Eq3: Mean Brightness
reghdfejl mean_brightness downup_ac_pop $controls , ///
    absorb($setfe ) cluster($cluster )
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd local ymean "`meandv3'"
estadd local acq "`numacs'"
est store eq3

********************************************************************************
* Save ster file
********************************************************************************

estwrite eq* using "${root}/tex/paper/tables/_app_7_main_did_downup_area_ac_dv_rural_stacked.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_7_main_did_downup_area_ac_dv_rural_stacked.ster"

********************************************************************************

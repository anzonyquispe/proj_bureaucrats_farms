

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
    global is_rural_var "is_rural_area"
    global fe_list "1/3"
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

********************************************************************************
* Import Data
********************************************************************************

import delimited "${root}/data_output/intermediate/0_master_merge_data_gen${sample}.csv", clear

* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural_area is_rural_farzad)
keep if _merge == 3
drop _merge

* Keep only rural grids
keep if ${is_rural_var} == 1

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

* Create cluster variable
egen cluster_acmonth = group(ac_id monthyear)

* Count unique ACs
unique ac_id
local numacs = r(unique)

********************************************************************************
* Calculate Mean DV for control group (downup_ac == 0)
********************************************************************************
bys unique_small_grid_id: egen treat = max(downup_ac)
capture confirm variable relative_year_bin
if _rc gen relative_year_bin = relative_monthyear
gen moderator = 0
quietly summarize anyfire if treat == 1 & relative_year_bin <= -1
local meandv1 = r(mean)
quietly summarize anyfire if treat == 1 & relative_year_bin <= -1 & moderator == 1
local meandv1_m = r(mean)

quietly summarize logfire if treat == 1 & relative_year_bin <= -1
local meandv2 = r(mean)
quietly summarize logfire if treat == 1 & relative_year_bin <= -1 & moderator == 1
local meandv2_m = r(mean)

quietly summarize mean_brightness if treat == 1 & relative_year_bin <= -1
local meandv3 = r(mean)
quietly summarize mean_brightness if treat == 1 & relative_year_bin <= -1 & moderator == 1
local meandv3_m = r(mean)

********************************************************************************
* Run Regressions
********************************************************************************

global controls av_wind_speed wind_direction

* Eq1: Any Fire
reghdfejl anyfire downup_ac $controls, ///
    absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv1'
estadd scalar ymean2 = `meandv1_m'
estadd scalar acq = `numacs'
est store eq1

* Eq2: Log Fires
reghdfejl logfire downup_ac $controls, ///
    absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv2'
estadd scalar ymean2 = `meandv2_m'
estadd scalar acq = `numacs'
est store eq2

* Eq3: Mean Brightness
reghdfejl mean_brightness downup_ac $controls, ///
    absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv3'
estadd scalar ymean2 = `meandv3_m'
estadd scalar acq = `numacs'
est store eq3

********************************************************************************
* Save ster file
********************************************************************************

estwrite eq* using "${root}/tex/paper/tables/_app_7_main_did_downup_area_ac_dv${sample}_rural${ster_suffix}.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_7_main_did_downup_area_ac_dv${sample}_rural${ster_suffix}.ster"

********************************************************************************

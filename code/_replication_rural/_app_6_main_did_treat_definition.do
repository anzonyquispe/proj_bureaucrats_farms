********************************************************************************
* _app_main_did_treat_definition_rural.do
* Replicates _app_main_did_treat_definition.R - RURAL GRIDS ONLY
* Different treatment definitions for downup
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

********************************************************************************
* Create treatment variables
********************************************************************************

* Total area
// gen total_area = downwind_area_ac_nosmall + upwind_area_ac_nosmall

* Difference: downwind - upwind
// gen downup_diff = downwind_area_ac_nosmall - upwind_area_ac_nosmall

* 1 std threshold
summarize downup_diff
local sd_val = r(sd)
// gen downup_1sd = .
// replace downup_1sd = 1 if downup_diff > `sd_val' & !missing(downup_diff)
// replace downup_1sd = 0 if downup_diff <= `sd_val' & !missing(downup_diff)

* Downwind percentage over total
// gen down_percent = (downwind_area_ac_nosmall * 100) / total_area

* Difference percentage
// gen downup_diff_percent = (downup_diff * 100) / total_area

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
* Calculate Mean DV for each treatment definition
********************************************************************************

* Mean DV for downup_ac == 0
bys unique_small_grid_id: egen treat = max(downup_ac)
summarize countk if downup_ac == 0 & treat == 1
local meandv1 = string(r(mean), "%9.1f")
drop treat

* Mean DV for downup_ac_pop == 0
bys unique_small_grid_id: egen treat = max(downup_ac_pop)
summarize countk if downup_ac_pop == 0 & treat == 1
local meandv2 = string(r(mean), "%9.1f")
drop treat

* Mean DV for downup_1sd == 0
bys unique_small_grid_id: egen treat = max(downup_1sd)
summarize countk if downup_1sd == 0 & treat == 1
local meandv3 = string(r(mean), "%9.1f")
drop treat

* Mean DV for down_percent == 0 (or close to 0)
summarize countk 
local meandv4 = string(r(mean), "%9.1f")


* Mean DV for all (downup_diff_percent is continuous)
summarize countk
local meandv5 = string(r(mean), "%9.1f")

********************************************************************************
* Run Regressions
********************************************************************************

global controls av_wind_speed wind_direction

* Eq1: downup_ac (exclude grid 116147 as in R code)
reghdfejl countk downup_ac $controls if grid_id != 116147, ///
    absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd local ymean "`meandv1'"
estadd local acq "`numacs'"
est store eq1

* Eq2: downup_ac_pop
reghdfejl countk downup_ac_pop $controls, ///
    absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd local ymean "`meandv2'"
estadd local acq "`numacs'"
est store eq2

* Eq3: downup_1sd
reghdfejl countk downup_1sd $controls, ///
    absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd local ymean "`meandv3'"
estadd local acq "`numacs'"
est store eq3

* Eq4: down_percent
reghdfejl countk down_percent $controls, ///
    absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd local ymean "`meandv4'"
estadd local acq "`numacs'"
est store eq4

* Eq5: downup_diff_percent
reghdfejl countk downup_diff_percent $controls, ///
    absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd local ymean "`meandv5'"
estadd local acq "`numacs'"
est store eq5

********************************************************************************
* Save ster file
********************************************************************************

estwrite eq* using "${root}/tex/paper/tables/_app_6_main_did_treat_definition${sample}_rural.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_6_main_did_treat_definition${sample}_rural.ster"

********************************************************************************

********************************************************************************
* _main_did_rural.do
* Replicates analysis from _main_did.R - RURAL GRIDS ONLY
* Generates DiD table with downup_ac treatment
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

global int_farms "${root}/data_output/intermediate"
global table_farms "${root}/tex/paper/tables"
global figure_farms "${root}/tex/paper/figures"

********************************************************************************
* Import Data
********************************************************************************

import delimited "${int_farms}/0_master_merge_data_gen${sample}.csv", clear

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
* Create TREAT_abs variable (to identify pure control)
********************************************************************************

bysort unique_small_grid_id: egen TREAT_abs = max(downup_ac)

********************************************************************************
* Encode string IDs if necessary
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
* Calculate statistics for table footer
********************************************************************************

* Calculate mean DV for control group (downup_ac==0 & TREAT_abs==1)
summarize countk if downup_ac == 0 & TREAT_abs == 1
local meandv = r(mean)
local meandv_fmt = string(`meandv', "%9.3f")

* Count unique ACs
unique ac_id
local numacs = r(unique)

********************************************************************************
* DiD Regressions
********************************************************************************

* Controls
global controls av_wind_speed wind_direction

* Cluster variables
egen cluster_acmonth = group(ac_id monthyear)

* Specification 1: No FE (baseline with controls only)
reg countk downup_ac $controls, vce(cluster grid_id)
estadd local ymean `meandv_fmt'
estadd local acq `numacs'
estadd local monthyearfe "N"
estadd local acfe "N"
estadd local acmonthfe "N"
estadd local gridfe "N"
estimates store eq1

* Specification 2: AC FE + MonthYear FE
reghdfejl countk downup_ac $controls, ///
    absorb(ac_id monthyear) ///
    cluster(grid_id cluster_acmonth)
estadd local ymean `meandv_fmt'
estadd local acq `numacs'
estadd local monthyearfe "Y"
estadd local acfe "Y"
estadd local acmonthfe "N"
estadd local gridfe "N"
estimates store eq2

* Specification 3: AC x MonthYear FE
reghdfejl countk downup_ac $controls, ///
    absorb(ac_id#monthyear) ///
    cluster(grid_id cluster_acmonth)
estadd local ymean `meandv_fmt'
estadd local acq `numacs'
estadd local monthyearfe "N"
estadd local acfe "N"
estadd local acmonthfe "Y"
estadd local gridfe "N"
estimates store eq3

* Specification 4: Grid FE + AC x MonthYear FE
reghdfejl countk downup_ac $controls, ///
    absorb(grid_id ac_id#monthyear) ///
    cluster(grid_id cluster_acmonth)
estadd local ymean `meandv_fmt'
estadd local acq `numacs'
estadd local monthyearfe "N"
estadd local acfe "N"
estadd local acmonthfe "Y"
estadd local gridfe "Y"
estimates store eq4

********************************************************************************
* Save estimates to ster file
********************************************************************************

estwrite eq1 eq2 eq3 eq4 using "${table_farms}/main_did_downup_area_ac${sample}_rural.ster", replace

display "Estimates saved to: ${table_farms}/main_did_downup_area_ac${sample}_rural.ster"

********************************************************************************

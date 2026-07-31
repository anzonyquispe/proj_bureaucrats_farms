

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
    global is_rural_var "is_rural_area"
    global fe_list "1/3"
    global ster_suffix "_acpop_stacked"

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

use  "${int_farms}/combined_dt_pop.dta", clear

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

* Sort data
sort unique_small_grid_id monthyear

********************************************************************************
* Create TREAT_abs variable (to identify pure control)
********************************************************************************

bysort unique_small_grid_id: egen TREAT_abs = max(downup_ac)
gen treat = TREAT_abs
capture confirm variable relative_year_bin
if _rc gen relative_year_bin = relative_monthyear
gen moderator = 0

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

* Treated-group pre-treatment means required by the replication convention.
quietly summarize countk if treat == 1 & relative_year_bin <= -1
local meandv = r(mean)
quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
local meandv2 = r(mean)

* Count unique ACs
unique ac_id
local numacs = r(unique)

********************************************************************************
* DiD Regressions
********************************************************************************

* FE
global setfe ac_id#cohort ac_id#monthyear#cohort

* Controls
global controls av_wind_speed wind_direction

* Cluster variables
global cluster ac_uq_id#cohort#monthyear unique_small_grid_id#cohort


* Specification 1: No FE (baseline with controls only)
reg countk downup_ac $controls, vce(cluster grid_id)
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
estadd local monthyearfe "N"
estadd local acfe "N"
estadd local acmonthfe "N"
estadd local gridfe "N"
estimates store eq1

* Specification 2: AC FE + MonthYear FE
reghdfejl countk downup_ac $controls, ///
    absorb(ac_id#cohort monthyear#cohort) ///
    cluster($cluster)
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
estadd local monthyearfe "Y"
estadd local acfe "Y"
estadd local acmonthfe "N"
estadd local gridfe "N"
estimates store eq2

* Specification 3: AC x MonthYear FE
reghdfejl countk downup_ac $controls, ///
    absorb(ac_id#monthyear#cohort) ///
    cluster($cluster)
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
estadd local monthyearfe "N"
estadd local acfe "N"
estadd local acmonthfe "Y"
estadd local gridfe "N"
estimates store eq3

* Specification 4: Grid FE + AC x MonthYear FE
reghdfejl countk downup_ac $controls, ///
    absorb(grid_id#cohort ac_id#monthyear#cohort) ///
    cluster($cluster)
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
estadd local monthyearfe "N"
estadd local acfe "N"
estadd local acmonthfe "Y"
estadd local gridfe "Y"
estimates store eq4

********************************************************************************
* Save estimates to ster file
********************************************************************************

estwrite eq1 eq2 eq3 eq4 using "${table_farms}/main_did_downup_area_ac${sample}_rural${ster_suffix}.ster", replace

display "Estimates saved to: ${table_farms}/main_did_downup_area_ac${sample}_rural${ster_suffix}.ster"

********************************************************************************

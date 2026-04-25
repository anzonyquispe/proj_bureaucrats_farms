********************************************************************************
* _main_bureau_polisc_did_rural.do
* Replicates analysis from _main_bureau_polisc_did.R - RURAL GRIDS ONLY
* Generates DiD table with bureaucrat and politician downup treatments
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
* Create interaction variable
********************************************************************************

gen downup_interaction = downup_ac * downup_dummy

********************************************************************************
* Encode string IDs if necessary
********************************************************************************

* Check if variables need encoding
capture confirm numeric variable unique_small_grid_id
if _rc {
    encode unique_small_grid_id, gen(grid_id)
}
else {
    gen grid_id = unique_small_grid_id
}

capture confirm numeric variable distr_id
if _rc {
    encode distr_id, gen(district_id)
}
else {
    gen district_id = distr_id
}

capture confirm numeric variable ac_uq_id
if _rc {
    encode ac_uq_id, gen(assembly_id)
}
else {
    gen assembly_id = ac_uq_id
}

********************************************************************************
* Calculate statistics for table footer
********************************************************************************

* Count unique assemblies
egen tag_assembly = tag(assembly_id)
count if tag_assembly == 1
local n_assemblies = r(N)

* Count unique districts
egen tag_district = tag(district_id)
count if tag_district == 1
local n_districts = r(N)

* Calculate mean DV for control group (downup_ac==0 & downup_dummy==0)
bysort unique_small_grid_id: egen treat = max(downup_ac)
summarize countk if downup_ac == 0 & treat == 1
local meandv = r(mean)


summarize countk if downup_ac == 0 & downup_dummy == 0 & treat == 1
local meandv2 = r(mean)


********************************************************************************
* DiD Regressions
********************************************************************************

* Controls
global controls av_wind_speed wind_direction

* Cluster variables
egen cluster_distmonth = group(district_id monthyear)

* Specification 1: No FE (baseline)
reg countk downup_dummy downup_ac downup_interaction $controls, ///
    vce(cluster grid_id)
estadd scalar ymean `meandv'
estadd scalar ymean2 `meandv2'
estadd local monthyearfe "N"
estadd local acfe "N"
estadd local acmonthfe "N"
estadd local gridfe "N"
estimates store eq1

* Specification 2: MonthYear FE + AC FE
reghdfejl countk downup_dummy downup_ac downup_interaction $controls, ///
    absorb(monthyear assembly_id) ///
    cluster(grid_id cluster_distmonth)
estadd scalar ymean `meandv'
estadd scalar ymean2 `meandv2'
estadd local monthyearfe "Y"
estadd local acfe "Y"
estadd local acmonthfe "N"
estadd local gridfe "N"
estimates store eq2

* Specification 3: AC x MonthYear FE
reghdfejl countk downup_dummy downup_ac downup_interaction $controls, ///
    absorb(assembly_id#monthyear) ///
    cluster(grid_id cluster_distmonth)
estadd scalar ymean `meandv'
estadd scalar ymean2 `meandv2'
estadd local monthyearfe "N"
estadd local acfe "N"
estadd local acmonthfe "Y"
estadd local gridfe "N"
estimates store eq3

* Specification 4: AC x MonthYear FE + Grid FE
reghdfejl countk downup_dummy downup_ac downup_interaction $controls, ///
    absorb(grid_id assembly_id#monthyear) ///
    cluster(grid_id cluster_distmonth)
estadd scalar ymean `meandv'
estadd scalar ymean2 `meandv2'
estadd local monthyearfe "N"
estadd local acfe "N"
estadd local acmonthfe "Y"
estadd local gridfe "Y"
estimates store eq4

* Specification 5: Grid FE + District x MonthYear FE (alternative)
reghdfejl countk downup_dummy downup_ac downup_interaction $controls, ///
    absorb(grid_id district_id#monthyear) ///
    cluster(grid_id cluster_distmonth)
estadd scalar ymean `meandv'
estadd scalar ymean2 `meandv2'
estadd local monthyearfe "N"
estadd local acfe "N"
estadd local acmonthfe "Y"
estadd local gridfe "Y"
estimates store eq5

********************************************************************************
* Save estimates
********************************************************************************

estwrite eq1 eq2 eq3 eq4 eq5 using "${table_farms}/_main_3_bureau_polisc_did${sample}_rural.ster", replace

display "Estimates saved to: ${table_farms}/_main_3_bureau_polisc_did${sample}_rural.ster"

********************************************************************************

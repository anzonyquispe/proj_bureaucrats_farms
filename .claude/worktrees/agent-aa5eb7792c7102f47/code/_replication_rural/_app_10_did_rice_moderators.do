********************************************************************************
* _main_did_rice_moderators_rural.do
* Main DiD analysis with rice moderators - RURAL GRIDS ONLY
* Tests heterogeneity by rice area, harvested rice area, and rice production
*
* From paper Appendix Table: main_did_downup_area_ac_rice_moderators.tex
* "Effect on the number of fires of constituency exposure to smoke by rice
*  producing area"
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

********************************************************************************
* Create rice moderator variables
* These should be in the data or merged from rice_moderators.dta
********************************************************************************

* Merge rice moderators if not already present
capture confirm variable rice_area_aclvl_ahigh
if _rc {
    display "Merging rice moderators..."
    merge m:1 unique_small_grid_id ac_uq_id using "${root}/data_output/intermediate/rice_moderators.dta", nogen
}

* Create indicator variables for above median rice characteristics
capture confirm variable rice_area_aclvl_ahigh
if _rc {
    * If variables don't exist, create from raw data
    * rice_area_aclvl_ahigh: Above median rice area
    * rice_harvarea_aclvl_ahigh: Above median harvested rice area
    * rice_prod_aclvl_ahigh: Above median rice production
    display as error "Rice moderator variables not found"
    display as error "Expected: rice_area_aclvl_ahigh, rice_harvarea_aclvl_ahigh, rice_prod_aclvl_ahigh"
    exit 1
}

********************************************************************************
* Calculate statistics
********************************************************************************

* Count unique ACs
unique ac_id
local numacs = r(unique)

* Mean DV for control group
bys unique_small_grid_id: egen ever_treat = max(downup_ac)
summarize countk if downup_ac == 0 & ever_treat == 1
local meandv = r(mean)

********************************************************************************
* Run Regressions
********************************************************************************

global controls av_wind_speed wind_direction
local moderators rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh

local i = 1
foreach mod of local moderators {
    
    * Mean DV for low moderator group
	quietly summarize countk if downup_ac == 0 & ever_treat == 1
    local meandv = cond(r(N) == 0, ., r(mean))
	
    quietly summarize countk if downup_ac == 0 & ever_treat == 1 & `mod' == 0
    local meandv2 = cond(r(N) == 0, ., r(mean))
	
	quietly summarize countk if downup_ac == 0 & ever_treat == 1 & `mod' == 1
    local meandv3 = cond(r(N) == 0, ., r(mean))
    
    * Regression
    reghdfejl countk ib0.downup_ac##ib0.`mod' $controls, ///
        absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
    
    * Store results
    estadd local gridfe    "Y"
    estadd local acmonthfe "Y"
    estadd local ymean    = cond(missing(`meandv'), "", string(`meandv', "%9.3f"))
    estadd local ymean2    = cond(missing(`meandv2'), "", string(`meandv2', "%9.3f"))
	estadd local ymean3    = cond(missing(`meandv3'), "", string(`meandv3', "%9.3f"))
    estadd scalar acq      `numacs'
    
    est store eq`i'
    local i = `i' + 1
}

********************************************************************************
* Save ster file
********************************************************************************

estwrite eq* using "${root}/tex/paper/tables/_app_10_did_rice_moderators${sample}_rural.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_10_did_rice_moderators${sample}_rural.ster"

********************************************************************************

*-------------------------------------------------------------------------------
* Stacked Event Study - RURAL GRIDS ONLY - downup_ac_pop treatment
*
* Mirror of _stacked_analysis.do, but reads the combined dataset built on
* downup_ac_pop switches (combined_dt_pop.dta) and uses downup_ac_pop wherever
* the original used downup_ac.
*
* Output: stacked_event_study_pop${sample}_rural.ster / .csv
*-------------------------------------------------------------------------------

********************************************************************************
* Setup - Only set globals if running standalone (not from master)
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    * Set toggles for standalone run
    global location "dbox"
    global sample ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"

    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }

    * Load Ados
    qui do "${root}/code/_replication_rural/estsave_csv.ado"

}


*-------------------------------------------------------------------------------
* Import and Merge Data
*-------------------------------------------------------------------------------

use "${root}/data_output/intermediate/combined_dt_pop.dta"

keep if abs(relative_monthyear) <= 6
egen relative_monthyear_aux = group(relative_monthyear)
gen countk = count * 1000

global controls  av_wind_speed wind_direction
global setfe unique_small_grid_id#cohort ac_uq_id#monthyear#cohort
global cluster ac_uq_id#cohort#monthyear unique_small_grid_id#cohort


merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge
keep if is_rural == 1
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/grids_with_more_1_ac.dta"
drop if dpl_ac ==1
drop _merge
keep if year < 2022 | (year == 2022 & month <= 8)

local dep_var countk
quietly summarize `dep_var' if downup_ac_pop ==0 & treat == 1
local ymean = r(mean)

quietly summarize `dep_var' if downup_ac_pop ==0 & treat == 1 & rice_prod_aclvl_ahigh == 1
local ymean2 = r(mean)

unique ac_uq_id
local numacs = r(unique)


reghdfejl countk ib7.relative_monthyear_aux##ib0.treat $controls, absorb($setfe) cluster($cluster)
estadd local ymean `ymean'
estadd local acq `numacs'
est store evreg1


reghdfejl countk ib7.relative_monthyear_aux##ib0.treat##ib0.rice_prod_aclvl_ahigh $controls, absorb($setfe) cluster($cluster)
estadd local ymean `ymean'
estadd local ymean2 `ymean2'
estadd local acq `numacs'
est store evreg2


estwrite evreg* using "${root}/tex/paper/tables/stacked_event_study_pop${sample}_rural.ster", replace
estsave_csv evreg1  evreg2    using "${root}/tex/paper/tables/stacked_event_study_pop${sample}_rural.csv", replace

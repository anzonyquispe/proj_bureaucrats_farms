*-------------------------------------------------------------------------------
* Main Event Study - RURAL GRIDS ONLY - 5 pre-treatment periods
* Window: relative_monthyear in [-5, +6] (5 pre + 6 post)
* Base period: ib5.relative_monthyear_aux = period -1 (group() maps -5→1 ... -1→5)
* Output: stacked_event_study_5pre${sample}_rural.ster / .csv
*-------------------------------------------------------------------------------

********************************************************************************
* Setup - Only set globals if running standalone (not from master)
********************************************************************************
macro drop root
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

use "${root}/data_output/intermediate/combined_dt.dta"

keep if relative_monthyear >= -5 & relative_monthyear <= 6
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
quietly summarize `dep_var' if downup_ac ==0 & treat == 1
local ymean = r(mean)

quietly summarize `dep_var' if downup_ac ==0 & treat == 1 & rice_prod_aclvl_ahigh == 1
local ymean2 = r(mean)

unique ac_uq_id
local numacs = r(unique)


reghdfejl countk ib5.relative_monthyear_aux##ib0.treat $controls, absorb($setfe) cluster($cluster)
estadd local ymean `ymean'
estadd local acq `numacs'
est store evreg1


reghdfejl countk ib5.relative_monthyear_aux##ib0.treat##ib0.rice_prod_aclvl_ahigh $controls, absorb($setfe) cluster($cluster)
estadd local ymean `ymean'
estadd local ymean2 `ymean2'
estadd local acq `numacs'
est store evreg2


estwrite evreg* using "${root}/tex/paper/tables/stacked_event_study_5pre${sample}_rural.ster", replace
estsave_csv evreg1  evreg2    using "${root}/tex/paper/tables/stacked_event_study_5pre${sample}_rural.csv", replace

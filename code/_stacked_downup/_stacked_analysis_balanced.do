*-------------------------------------------------------------------------------
* Stacked Event Study - balanced control panel - RURAL GRIDS ONLY
*
* Same specification as _stacked_analysis.do, but enforces that every CONTROL
* grid be observed in every relative_monthyear in [-6, 6] within its cohort.
* Controls that don't span the full 13-period window are dropped. Treated
* grids are kept regardless of their balance (consistent with the user's
* request: the requirement applies to the control group only).
*
* Output: stacked_event_study_balanced${sample}_rural.ster / .csv
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
* Import data
*-------------------------------------------------------------------------------

use "${root}/data_output/intermediate/combined_dt.dta", clear

*-------------------------------------------------------------------------------
* Apply analysis-sample filters first so balance is judged on the
* final regression sample, not the raw stacked dataset.
*-------------------------------------------------------------------------------

merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge
keep if is_rural == 1

merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/grids_with_more_1_ac.dta"
drop if dpl_ac == 1
drop _merge

keep if year < 2022 | (year == 2022 & month <= 8)

* Restrict to the [-6, 6] event window
keep if abs(relative_monthyear) <= 6

*-------------------------------------------------------------------------------
* Balanced-control filter
*
* For each (cohort, unique_small_grid_id), count distinct relative_monthyear
* values present in the [-6, 6] window. Drop CONTROL grids (treat == 0)
* that do not cover all 13 periods (-6, -5, ..., 0, ..., 5, 6).
*-------------------------------------------------------------------------------

bysort cohort unique_small_grid_id relative_monthyear: gen byte _first_rmy = (_n == 1)
bysort cohort unique_small_grid_id: egen int n_periods_window = total(_first_rmy)
drop _first_rmy

count if treat == 0
local n_ctrl_before = r(N)
count if treat == 0 & n_periods_window < 13
local n_ctrl_dropped = r(N)

drop if treat == 0 & n_periods_window < 13
drop n_periods_window

display "Balanced-control filter: dropped " `n_ctrl_dropped' " of " `n_ctrl_before' ///
        " control rows (control grids missing any of the 13 periods in [-6, 6])."

*-------------------------------------------------------------------------------
* Build the event-time factor and outcome
*-------------------------------------------------------------------------------

egen relative_monthyear_aux = group(relative_monthyear)
gen countk = count * 1000

global controls  av_wind_speed wind_direction
global setfe    unique_small_grid_id#cohort ac_uq_id#monthyear#cohort
global cluster  ac_uq_id#cohort#monthyear unique_small_grid_id#cohort

local dep_var countk
quietly summarize `dep_var' if downup_ac == 0 & treat == 1
local ymean = r(mean)

quietly summarize `dep_var' if downup_ac == 0 & treat == 1 & rice_prod_aclvl_ahigh == 1
local ymean2 = r(mean)

unique ac_uq_id
local numacs = r(unique)

*-------------------------------------------------------------------------------
* Event-study regressions
*-------------------------------------------------------------------------------

reghdfejl countk ib6.relative_monthyear_aux##ib0.treat $controls, absorb($setfe) cluster($cluster)
estadd local ymean `ymean'
estadd local acq `numacs'
est store evreg1

reghdfejl countk ib6.relative_monthyear_aux##ib0.treat##ib0.rice_prod_aclvl_ahigh $controls, absorb($setfe) cluster($cluster)
estadd local ymean `ymean'
estadd local ymean2 `ymean2'
estadd local acq `numacs'
est store evreg2

*-------------------------------------------------------------------------------
* Persist estimates
*-------------------------------------------------------------------------------

estwrite evreg* using "${root}/tex/paper/tables/stacked_event_study_balanced${sample}_rural.ster", replace
estsave_csv evreg1 evreg2 using "${root}/tex/paper/tables/stacked_event_study_balanced${sample}_rural.csv", replace

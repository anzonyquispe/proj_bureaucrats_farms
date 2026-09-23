
*-------------------------------------------------------------------------------
* Main Event Study - RURAL GRIDS ONLY
* Output: main_event_study_rural.ster
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
    global is_rural_var "is_rural_area"
    global fe_list "1"
    global ster_suffix ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"

    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }
	
	* Load Ados
	qui do "${code}/tools/estsave_csv.ado"

}


*-------------------------------------------------------------------------------
* Import and Merge Data
*-------------------------------------------------------------------------------

import delimited "${root}/data_output/intermediate/0_master_merge_data_gen${sample}.csv", clear varnames(1)

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

* Keep relevant time period
keep if year < 2022 | (year == 2022 & month <= 8)
keep unique_small_grid_id monthyear downup_ac av_wind_speed wind_direction count ac_uq_id ///
    rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh

*-------------------------------------------------------------------------------
* Generate Event Study Variables
*-------------------------------------------------------------------------------

* Temporarily rename variables
rename downup_ac abs

* First, set switchtoexp = 1 everytime there is a switch
gsort unique_small_grid_id monthyear
bys unique_small_grid_id: gen switchtoexp=1 if abs==1 & abs[_n-1]==0

* Set switch to unexp = 1 if switch to unexposed
gsort unique_small_grid_id monthyear
bys unique_small_grid_id: gen switchtounexp=1 if abs==0 & abs[_n-1]==1

* Second, set rtime = +n after the switch and -n after
gen rtime_abs=switchtoexp
replace rtime_abs=-1 if switchtounexp==1
    bys unique_small_grid_id: replace rtime_abs=rtime_abs[_n-1]+1 if abs==1 & rtime_abs==.
gsort unique_small_grid_id -monthyear
replace rtime_abs=. if rtime_abs==-1
replace rtime_abs=-1 if rtime_abs==. & rtime_abs[_n-1]==1
    bys unique_small_grid_id: replace rtime_abs=rtime_abs[_n-1]-1 if abs==0 & rtime_abs==.

drop switchtoexp switchtounexp
gsort unique_small_grid_id monthyear

* Time invariant treatment
bys unique_small_grid_id: egen TREAT_abs=max(abs)

* First treated time is zero
replace rtime_abs=rtime_abs-1 if rtime_abs>0

rename abs downup_ac

gen countk = count * 1000
keep if inrange(rtime_abs, -6, 6)
gen relative_year_bin = rtime_abs
summarize relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin - `rmin' + 1
local base = -1 - `rmin' + 1
gen treat = TREAT_abs

*-------------------------------------------------------------------------------
* Regressions
*-------------------------------------------------------------------------------

global controls av_wind_speed wind_direction
global cluster unique_small_grid_id monthyear#ac_uq_id
local dep_var countk

local fe1 "unique_small_grid_id ac_uq_id#monthyear"
gen moderator = 0
local moderators_list moderator rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
local i = 1
foreach mod of local moderators_list {
    replace moderator = `mod'
    local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"

    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1
    local ymean = r(mean)
    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)
    unique ac_uq_id
    local numacs = r(unique)

    foreach fe of numlist $fe_list {
        reghdfejl `dep_var' `rhs', absorb(`fe`fe'') cluster($cluster)
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"
        estadd local fespec "Grid and AC-month FE"
        estadd local mod "`mod'"
        est store evreg`i'
        local ++i
    }
}

estwrite evreg* using "${root}/tex/paper/tables/main_event_study${sample}_rural${ster_suffix}.ster", replace
estsave_csv evreg1  evreg2  evreg3  evreg4 using "${root}/tex/paper/tables/main_event_study${sample}_rural${ster_suffix}.csv", replace


*-------------------------------------------------------------------------------


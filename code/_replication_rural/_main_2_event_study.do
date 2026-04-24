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
	
	* Load Ados
	qui do "${root}/code/_replication_rural/estsave_csv.ado"

}


*-------------------------------------------------------------------------------
* Import and Merge Data
*-------------------------------------------------------------------------------

import delimited "${root}/data_output/intermediate/0_master_merge_data_gen${sample}.csv", clear varnames(1)

* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge

* Keep only rural grids
keep if is_rural == 1

display "Observations after rural filter: " _N

* Keep relevant time period
keep if year < 2022 | (year == 2022 & month <= 8)
keep unique_small_grid_id monthyear downup_ac av_wind_speed wind_direction count ac_uq_id is_rural rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh

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

* Generate event study dummies
su rtime_abs
forvalues l = 0/6 {
    gen byte La`l'_abs = rtime_abs ==`l'
    label var La`l'_abs "`l'"
}
forvalues l = 1/6 {
    gen byte Le`l'_abs = rtime_abs ==-`l'
    label var Le`l'_abs "-`l'"
}

drop La0_abs // normalize rtime = 0

gen countk = count * 1000

global tr abs

drop if TREAT_$tr==1 & rtime_$tr>=7
drop if TREAT_$tr==1 & rtime_$tr<=-7
bys unique_small_grid_id: egen TREAT = max(downup_ac)

*-------------------------------------------------------------------------------
* Regressions
*-------------------------------------------------------------------------------

global controls av_wind_speed wind_direction
global cluster unique_small_grid_id monthyear#ac_uq_id
local dep_var countk

local fe1 "unique_small_grid_id ac_uq_id#monthyear"

* Compute mean of dep var where untreated
quietly summarize `dep_var' if downup_ac ==0 & TREAT == 1
local ymean = r(mean)
gen moderator = 0
* Count number of unique ACs in subsample
unique ac_uq_id
local numacs = r(unique)
local modlist moderator rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
local i = 1
foreach mod of local modlist{
	
	local rhs Le*_${tr} La*_${tr} 1.Le*_${tr}#1.`mod' 1.La*_${tr}#1.`mod' $controls
	
	quietly summarize `dep_var' if downup_ac ==0 & TREAT == 1 & `mod' == 1
	local ymean2 = cond(r(N) == 0, `ymean', r(mean))
	
	quietly summarize `dep_var' if downup_ac ==0 & TREAT == 1 & `mod' == 0
	local ymean3 = cond(r(N) == 0, `ymean', r(mean))
	
	* Run regression with clustering
	reghdfejl `dep_var' `rhs', absorb(`fe1') cluster($cluster) nocons

	* Store coefficient + SE of main var
	estadd local ymean `ymean'
	estadd local ymean2 `ymean2'
	estadd local ymean3 `ymean3'
	estadd local acq `numacs'
	est store evreg`i'
	local i = `i' + 1
}

estwrite evreg* using "${root}/tex/paper/tables/main_event_study${sample}_rural.ster", replace
estsave_csv evreg1  evreg2  evreg3  evreg4 using "${root}/tex/paper/tables/main_event_study${sample}_rural.csv", replace


*-------------------------------------------------------------------------------




********************************************************************************
* _main_4_protest_5km_fe12_did_downup_rural.do
* Protest DiD analysis with downup_ac_pop moderator - RURAL GRIDS ONLY
* 6 columns: 3 FE specs Ãƒâ€” 2 moderator types (baseline + downup_ac_pop)
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
    global ster_suffix "_acpop"

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

import delimited using "${root}/data_output/intermediate/stacked_data_protest${sample}.csv", clear varnames(1)

* Merge with rice moderators
merge m:1 unique_small_grid_id ac_uq_id using "data_output/intermediate/rice_moderators.dta"
keep if _merge == 3
drop _merge

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

*-------------------------------------------------------------------------------
* Merge in downup_ac_pop from master data (not present in this dataset)
*-------------------------------------------------------------------------------
preserve
import delimited "${root}/data_output/intermediate/0_master_merge_data_gen${sample}.csv", ///
    clear varnames(1)
keep unique_small_grid_id monthyear downup_ac_pop
duplicates drop unique_small_grid_id monthyear, force
tempfile downup_ac_pop_lookup
save `downup_ac_pop_lookup'
restore
merge m:1 unique_small_grid_id monthyear using `downup_ac_pop_lookup', ///
    keep(master match) keepusing(downup_ac_pop) nogen

********************************************************************************
* Generate Variables
********************************************************************************

sum relative_year_bin
local rmin = r(min)
gen post_ = relative_year_bin >= 0
gen moderator = 0

local dep_var countk
local rhs "ib0.post_##ib0.treat##ib0.moderator wind_direction av_wind_speed"

* FE specifications
local fe1 "unique_small_grid_id_cohort relative_year_bin"
local fe2 "unique_small_grid_id_cohort relative_year_bin province_cohort#election_year"
local fe3 "unique_small_grid_id_cohort relative_year_bin province_cohort#election_year province_cohort#c.monthyear "

* Statistics
quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1
local ymean = r(mean)
unique ac_uq_id
local numacs = r(unique)

********************************************************************************
* Run Regressions
********************************************************************************

local i = 1

foreach mod in 0 1 {

    if `mod' == 0 {
        replace moderator = 0
    }
    else {
        replace moderator = downup_ac_pop
        replace moderator = . if downup_ac_pop == .
    }
	
	quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1
	local ymean2 = r(mean)

	quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 0
	local ymean3 = r(mean)



    foreach fe of numlist $fe_list {

        reghdfejl `dep_var' `rhs', absorb(`fe`fe'') cluster(ac_area_tr)

        * Store FE indicators
        estadd local gridfe "Y"
		estadd local time "Y"
		estadd local electionfe = cond(`fe' >= 2, "Y", "N")
        estadd local provtrendfe = cond(`fe' == 3, "Y", "N")
		estadd scalar ymean = `ymean'
		estadd scalar ymean2 `ymean2'
		estadd scalar ymean3 = `ymean3'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"

        est store evreg`i'
        local i = `i' + 1
    }
}

********************************************************************************
* Save ster file
********************************************************************************

estwrite evreg* using "${root}/tex/paper/tables/_main_4_protest_5km_fe12_did_downup${sample}_rural${ster_suffix}.ster", replace

display "Ster: ${root}/tex/paper/tables/_main_4_protest_5km_fe12_did_downup${sample}_rural${ster_suffix}.ster"

********************************************************************************


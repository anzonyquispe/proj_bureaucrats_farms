********************************************************************************
* Area-based stacked event study, five pre-treatment periods
********************************************************************************

if "$root" == "" {
    global location "shell"
    global sample ""
    global is_rural_var "is_rural_area"
    global fe_list "1"
    global ster_suffix ""
    do "config.do"
}

quietly do "${code}/tools/estsave_csv.ado"
use "${int_data}/combined_dt.dta", clear

keep if inrange(relative_monthyear, -5, 6)
gen relative_year_bin = relative_monthyear
gen relative_year_bin_aux = relative_year_bin + 6
local base = 5
gen countk = count * 1000

merge m:1 unique_small_grid_id using "${int_data}/ghs_grid_classification_2000.dta", ///
    keepusing(is_rural_area is_rural_farzad)
keep if _merge == 3
drop _merge
keep if ${is_rural_var} == 1

merge m:1 unique_small_grid_id using "${int_data}/grids_with_more_1_ac.dta"
drop if dpl_ac == 1
drop _merge
keep if year < 2022 | (year == 2022 & month <= 8)

local dep_var countk
local fe1 "unique_small_grid_id#cohort ac_uq_id#monthyear#cohort"
local moderators_list moderator rice_prod_aclvl_ahigh
* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
gen moderator = 0

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
        reghdfejl `dep_var' `rhs', absorb(`fe`fe'') ///
            cluster(ac_uq_id#cohort#monthyear unique_small_grid_id#cohort)
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"
        estadd local fespec "Stacked grid-cohort and AC-month-cohort FE"
        estadd local mod "`mod'"
        est store evreg`i'
        local ++i
    }
}

estwrite evreg* using "${tables}/stacked_event_study_5pre${sample}_rural${ster_suffix}.ster", replace
estsave_csv evreg1 evreg2 using "${tables}/stacked_event_study_5pre${sample}_rural${ster_suffix}.csv", replace

********************************************************************************

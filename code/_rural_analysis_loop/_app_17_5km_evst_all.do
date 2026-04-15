*-------------------------------------------------------------------------------
* _app_17_5km_evst_all_rural.do
* Protest Event Study - RURAL GRIDS ONLY
* Loops over 32 fixed-effects specifications (no moderator interaction).
* Output: _app_17_5km_evst_all_rural.ster
*-------------------------------------------------------------------------------

********************************************************************************
* Setup - Only set globals if running standalone (not from master)
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    * Defaults for standalone runs. When launched from an sbatch array these
    * globals are set by the caller and this whole block is skipped.
    * Five parameters are expected to be set by the sbatch array:
    *   location     : "shell" | "dbox"
    *   sample       : ""      | "_sample"
    *   is_rural_var : "is_rural_area" | "is_rural_farzad"
    *   fe_list      : any Stata numlist of FE indices (e.g. "1/32", "12 13 19")
    *   ster_suffix  : suffix appended to the output ster filename (default "")
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural_area"
    global fe_list      "1/32"
    global ster_suffix  ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"

    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }
    * Load custom ado for exporting results
    qui do "${root}/code/_replication_rural/estsave_csv.ado"
}

cd "${root}"

*-------------------------------------------------------------------------------
* Import and Merge Data
*-------------------------------------------------------------------------------

import delimited using "${root}/data_output/intermediate/stacked_data_protest${sample}.csv", clear varnames(1)

* Merge with rice moderators
merge m:1 unique_small_grid_id ac_uq_id using "data_output/intermediate/rice_moderators.dta"
keep if _merge == 3
drop _merge

* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural_area is_rural_farzad)
keep if _merge == 3
drop _merge

* Keep only rural grids (variable chosen via ${is_rural_var})
keep if ${is_rural_var} == 1

display "Observations after rural filter: " _N

*-------------------------------------------------------------------------------
* Generate Variables
*-------------------------------------------------------------------------------

gen provsel = 0
replace provsel = 1 if province == "Punjab_IND" | province == "Haryana"

sum relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin - `rmin' + 1
local base = -1 - `rmin' + 1

*-------------------------------------------------------------------------------
* Regression Setup
*-------------------------------------------------------------------------------

local dep_var countk

* RHS uses the triple-interaction form so adding real moderators later is a
* drop-in change: just extend `moderators_list` below. For this exercise the
* list contains only `moderator` (a stub variable set to 0), which makes the
* triple interaction collapse to the standard event study.

*-------------------------------------
* Define 32 FE specifications
*-------------------------------------
local fe1  "unique_small_grid_id_cohort "
local fe2  "unique_small_grid_id_cohort  monthyearco "
local fe3  "unique_small_grid_id_cohort  province_cohort#c.monthyear "
local fe4  "unique_small_grid_id_cohort  yeargov "
local fe5  "unique_small_grid_id_cohort  province_cohort#election_year "
local fe6  "unique_small_grid_id_cohort  province_cohort#election_year#yeargov "
local fe7  "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear "
local fe8  "unique_small_grid_id_cohort  monthyearco  yeargov "
local fe9  "unique_small_grid_id_cohort  monthyearco  province_cohort#election_year "
local fe10 "unique_small_grid_id_cohort  monthyearco  province_cohort#election_year#yeargov "
local fe11 "unique_small_grid_id_cohort  province_cohort#c.monthyear  yeargov "
local fe12 "unique_small_grid_id_cohort  province_cohort#c.monthyear  province_cohort#election_year "
local fe13 "unique_small_grid_id_cohort  province_cohort#c.monthyear  province_cohort#election_year#yeargov "
local fe14 "unique_small_grid_id_cohort  yeargov  province_cohort#election_year "
local fe15 "unique_small_grid_id_cohort  yeargov  province_cohort#election_year#yeargov "
local fe16 "unique_small_grid_id_cohort  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe17 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  yeargov "
local fe18 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  province_cohort#election_year "
local fe19 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  province_cohort#election_year#yeargov "
local fe20 "unique_small_grid_id_cohort  monthyearco  yeargov  province_cohort#election_year "
local fe21 "unique_small_grid_id_cohort  monthyearco  yeargov  province_cohort#election_year#yeargov "
local fe22 "unique_small_grid_id_cohort  monthyearco  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe23 "unique_small_grid_id_cohort  province_cohort#c.monthyear  yeargov  province_cohort#election_year "
local fe24 "unique_small_grid_id_cohort  province_cohort#c.monthyear  yeargov  province_cohort#election_year#yeargov "
local fe25 "unique_small_grid_id_cohort  province_cohort#c.monthyear  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe26 "unique_small_grid_id_cohort  yeargov  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe27 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  yeargov  province_cohort#election_year "
local fe28 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  yeargov  province_cohort#election_year#yeargov "
local fe29 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe30 "unique_small_grid_id_cohort  monthyearco  yeargov  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe31 "unique_small_grid_id_cohort  province_cohort#c.monthyear  yeargov  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe32 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  yeargov  province_cohort#election_year  province_cohort#election_year#yeargov "

*-------------------------------------
* Filters
*-------------------------------------
local filter1 "1"   // all sample

* Moderators list. Original set kept in a comment for reference; for this run
* the list only contains `moderator` (stub = 0) so the triple interaction
* collapses to a plain event study while preserving the structure.
* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
local moderators_list moderator
gen moderator = 0

*-------------------------------------
* Loop over moderators x filters x FE specifications
*-------------------------------------

local i = 1

foreach mod of local moderators_list {

    replace moderator = `mod'

    local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"

    foreach f of numlist 1/1 {

        * Select filter condition
        local fcond `filter`f''

        * Mean of dep var for treated units, pre-treatment (all)
        quietly summarize `dep_var' if `fcond' & treat == 1 & relative_year_bin <= -1
        local ymean = r(mean)

        * Mean of dep var for treated units, pre-treatment, moderator == 1
        quietly summarize `dep_var' if `fcond' & treat == 1 & relative_year_bin <= -1 & moderator == 1
        local ymean2 = r(mean)

        * Count number of unique ACs in subsample
        unique ac_uq_id if `fcond'
        local numacs = r(unique)

        foreach fe of numlist $fe_list {

            * Select FE spec
            local fespec `fe`fe''

            * Run regression with clustering
            reghdfejl `dep_var' `rhs' if `fcond', absorb(`fespec') vce(cluster ac_area_tr)

            * Accumulate scalars and labels, then store the estimate
            estadd scalar ymean  = `ymean'
            estadd scalar ymean2 = `ymean2'
            estadd scalar acq    = `numacs'
            estadd local  smpl   "Rural"
            estadd local  fespec "fe`fe'"
            estadd local  mod    "`mod'"

            est store evreg`i'

            local i = `i' + 1
            display("`i'")
        }
    }
}

*-------------------------------------------------------------------------------
* Export Results
*-------------------------------------------------------------------------------

estwrite evreg* using "${root}/tex/paper/tables/_app_17_5km_evst_all${sample}_rural${ster_suffix}.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_17_5km_evst_all${sample}_rural${ster_suffix}.ster"

********************************************************************************
* Exploratory protest event study using province-election-switch cohorts.
*
* Cohort key: province x election year x switching month.
* Controls: pooled never-treated and censored not-yet-treated grids.
* FE: FE1-FE5 below, each augmented with event year x cohort_id.
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    * Standalone defaults for the five sbatch-array parameters:
    * location, sample, is_rural_var, fe_list, and ster_suffix.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1/5"
    global ster_suffix  ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
    global code_shell "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
    global code_dbox "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"

    if "$location" == "dbox" {
        global root "$dbox"
        global code "$code_dbox"
    }
    else {
        global root "$shell"
        global code "$code_shell"
    }
    quietly do "${code}/estsave_csv.ado"
}

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"
local output_dir "${tables}/exploratory_analysis/protest_province_election_switch"
capture mkdir "${tables}/exploratory_analysis"
capture mkdir "`output_dir'"

local input ///
    "${int_data}/stacked_data_protest5km_province_election_switch${sample}.csv"
confirm file "`input'"
display as text "Input: `input'"
import delimited using "`input'", clear varnames(1)

* Construction invariants are checked again at estimation time.
confirm variable cohort_id
confirm variable cohort_province
confirm variable cohort_election_year
confirm variable cohort_term_start
confirm variable cohort_term_end
confirm variable control_type
assert province == cohort_province
assert monthyear >= cohort_term_start
assert monthyear < cohort_term_end
assert year < 2022 | (year == 2022 & month <= 8)
assert relative_monthyear == monthyear - cohort
assert relative_year_bin == floor(relative_monthyear / 12)
assert protest5km == (monthyear >= cohort) if treat == 1
assert protest5km == 0 if treat == 0
assert control_type == 0 if treat == 1
assert inlist(control_type, 1, 2) if treat == 0

bysort cohort_id: assert cohort == cohort[1]
bysort cohort_id: assert cohort_province == cohort_province[1]
bysort cohort_id: assert cohort_election_year == cohort_election_year[1]
bysort cohort_id: assert cohort_term_start == cohort_term_start[1]
bysort cohort_id: assert cohort_term_end == cohort_term_end[1]

* Each retained grid-cohort must be an uninterrupted monthly sequence. For a
* not-yet-treated control, that sequence ends immediately before its own switch.
bysort cohort_id unique_small_grid_id (monthyear): ///
    assert monthyear == monthyear[_n-1] + 1 if _n > 1

* Match the reference sample definition and use the authoritative rice flag.
capture drop rice_prod_aclvl_ahigh
merge m:1 unique_small_grid_id ac_uq_id using ///
    "${int_data}/rice_moderators.dta", ///
    keepusing(rice_prod_aclvl_ahigh)
keep if _merge == 3
drop _merge
assert inlist(rice_prod_aclvl_ahigh, 0, 1)

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keepusing(is_rural)
keep if _merge == 3
drop _merge
keep if ${is_rural_var} == 1

* Follow the reference dofile: remove only relative year -5.
drop if relative_year_bin == -5

recast int election_year, force
recast byte yeargov, force

egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
egen monthyearco                 = group(month year cohort_id)
egen province_cohort             = group(cohort_id province)
egen relativeyear_cohort         = group(relative_year_bin cohort_id)
egen ac_elec_yr                  = group(ac_uq_id cohort_election_year cohort_id)

* Rural/rice filtering can remove rows, so enforce pre/post support again.
bysort unique_small_grid_id_cohort: egen byte has_pre  = max(relative_year_bin < 0)
bysort unique_small_grid_id_cohort: egen byte has_post = max(relative_year_bin >= 0)
egen byte unit_tag = tag(unique_small_grid_id_cohort)
quietly count if unit_tag
local units_before = r(N)
quietly count if unit_tag & has_pre == 1 & has_post == 1
local units_balanced = r(N)
display as text "Grid-cohort units with pre and post: `units_balanced' of `units_before'"
keep if has_pre == 1 & has_post == 1
drop unit_tag has_pre has_post

quietly summarize relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin - `rmin' + 1
local base = -1 - `rmin' + 1

capture drop countk
gen countk = count * 1000
local dep_var countk
local filter1 "1"

local fe1 "unique_small_grid_id_cohort"
local fe2 "unique_small_grid_id_cohort monthyearco"
local fe3 "unique_small_grid_id_cohort province_cohort#c.monthyear"
local fe4 "unique_small_grid_id_cohort yeargov"
local fe5 "unique_small_grid_id_cohort province_cohort#election_year"

gen byte moderator = 0
* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
local moderators_list moderator rice_prod_aclvl_ahigh

egen byte tag_ac = tag(ac_uq_id)
quietly count if tag_ac
local numacs = r(N)
drop tag_ac

est clear
local i = 1
local estimate_names ""
foreach fe of numlist $fe_list {
    local fespec `fe`fe''
    display _newline as text "FE`fe': `fespec' + relativeyear_cohort"

    foreach mod of local moderators_list {
        replace moderator = `mod'
        local rhs ///
            "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"

        quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & `filter1'
        local ymean = r(mean)
        quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1 & `filter1'
        local ymean2 = r(mean)

        reghdfejl `dep_var' `rhs' if `filter1', ///
            absorb(`fespec' relativeyear_cohort) ///
            vce(cluster ac_elec_yr)

        estadd scalar ymean  = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq    = `numacs'
        estadd local smpl "Rural"
        estadd local fespec "FE`fe': `fespec' relativeyear_cohort"
        estadd local mod "`mod'"
        estadd local controls "pooled"

        local estname evreg`i'
        local estimate_names "`estimate_names' `estname'"
        local i = `i' + 1
        est store `estname'
    }
}

local outbase "`output_dir'/protest_province_election_switch_event${sample}_rural${ster_suffix}"
estwrite `estimate_names' using "`outbase'.ster", replace
estsave_csv `estimate_names' using "`outbase'.csv", replace
confirm file "`outbase'.ster"
confirm file "`outbase'.csv"
confirm file "`outbase'_scalars.csv"
display as result "Saved exploratory event-study results: `outbase'"

********************************************************************************

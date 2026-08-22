********************************************************************************
* Protest event study (rural stacked sample)
*
* Input: election-term-cleaned stacked_data_protest5km_election_sameterm.
* Output control suffixes follow the politician event-study dofile:
*   _controls_never; _controls_both; _controls_notyet.
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    * Standalone defaults for the five sbatch-array parameters:
    * location, sample, is_rural_var, fe_list, and ster_suffix.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1"
    global ster_suffix  ""
    global control_samples "never both notyet"

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
    global code_shell "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
    global code_dbox  "/Users/anzony.quisperojas/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"

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

if "$downup_var" == "" {
    global downup_var "downup_ac_pop"
}
if "$control_samples" == "" {
    global control_samples "never both notyet"
}

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"

local protest_input ///
    "${int_data}/stacked_data_protest5km_election_sameterm${sample}.csv"
capture confirm file "`protest_input'"
if _rc {
    local protest_input ///
        "${int_data}/cohortes_protest_term/stacked_data_protest5km_election_sameterm${sample}.csv"
}
capture confirm file "`protest_input'"
if _rc {
    local protest_input ///
        "${int_data}/cohorts_protest_term/stacked_data_protest5km_election_sameterm${sample}.csv"
}
confirm file "`protest_input'"
display as text "Final same-term protest input: `protest_input'"
import delimited using "`protest_input'", clear varnames(1)

confirm variable cohort_id
confirm variable cohort_election_year
confirm variable cohort_term_start
confirm variable cohort_analysis_max
assert monthyear >= cohort_term_start
assert monthyear <= cohort_analysis_max
assert cohort_term_start <= cohort
assert inrange(cohort_analysis_max - cohort_term_start, 0, 59)
bysort cohort_id: assert cohort == cohort[1]
bysort cohort_id: assert cohort_election_year == cohort_election_year[1]
bysort cohort_id: assert cohort_term_start == cohort_term_start[1]
bysort cohort_id: assert cohort_analysis_max == cohort_analysis_max[1]

capture confirm variable relative_year_bin
if _rc {
    confirm variable relative_year
    rename relative_year relative_year_bin
}
assert relative_year_bin == floor((monthyear - cohort) / 12)

* Always express the fire-count outcome in thousands.
capture drop countk
gen countk = count * 1000

capture confirm variable rice_area_aclvl_ahigh
if _rc {
    merge m:1 unique_small_grid_id ac_uq_id using ///
        "${int_data}/rice_moderators.dta", ///
        keep(master match) ///
        keepusing(rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh)
    drop _merge
}

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)
* Event time is centered on the protest, while eligible observations remain
* inside its government term. The final protest window is four pre years and
* event years 0 and +1, with -1 used as the reference period.
keep if inrange(relative_year_bin, -4, 1)
display as text "Final protest event-study window: relative_year_bin in [-4, 1]"

confirm variable control_type
assert control_type == 0 if treat == 1
assert inlist(control_type, 1, 2) if treat == 0

egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
egen province_cohort = group(province cohort_id)
egen relativeyear_cohort = group(relative_year_bin cohort_id)
egen ac_elec_yr = group(ac_uq_id cohort_election_year cohort_id)

bysort unique_small_grid_id_cohort: egen byte has_pre = max(relative_year_bin < 0)
bysort unique_small_grid_id_cohort: egen byte has_post = max(relative_year_bin >= 0)
egen byte unit_tag = tag(unique_small_grid_id_cohort)
quietly count if unit_tag
local units_before = r(N)
quietly count if unit_tag & has_pre == 1 & has_post == 1
local units_balanced = r(N)
display as text "Grid-cohort units with pre and post periods: `units_balanced' of `units_before'"
keep if has_pre == 1 & has_post == 1
assert has_pre == 1 & has_post == 1
drop unit_tag has_pre has_post

quietly summarize relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin - `rmin' + 1
local base = -1 - `rmin' + 1

local fe1 "unique_small_grid_id_cohort relativeyear_cohort province_cohort#c.monthyear province_cohort#election_year"
local filter1 "1"
gen moderator = 0

* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
local moderators_list moderator ${downup_var} rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh

tempfile analysis_base
save `analysis_base'

foreach control_sample in $control_samples {
    if !inlist("`control_sample'", "never", "both", "notyet") {
        display as error "Unknown control sample: `control_sample'"
        exit 198
    }
    use `analysis_base', clear

    local control_suffix "_controls_never"
    if "`control_sample'" == "never" {
        keep if treat == 1 | control_type == 1
    }
    else if "`control_sample'" == "both" {
        local control_suffix "_controls_both"
    }
    else if "`control_sample'" == "notyet" {
        keep if treat == 1 | control_type == 2
        local control_suffix "_controls_notyet"
    }

    display as text "Protest event study: controls=`control_sample', downup=${downup_var}, N=" _N

    egen tag_ac = tag(ac_uq_id)
    count if tag_ac == 1
    local numacs = r(N)

    est clear
    local i = 1
    local estimate_names ""
    foreach mod of local moderators_list {
        replace moderator = `mod'
        local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
        local fcond `filter1'

        quietly summarize countk if treat == 1 & relative_year_bin <= -1 & `fcond'
        local ymean = r(mean)
        quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1 & `fcond'
        local ymean2 = r(mean)

        foreach fe of numlist $fe_list {
            local fespec `fe`fe''
            reghdfejl countk `rhs' if `fcond', ///
                absorb(`fespec') vce(cluster ac_elec_yr)

            estadd scalar ymean  = `ymean'
            estadd scalar ymean2 = `ymean2'
            estadd scalar acq    = `numacs'
            estadd local smpl "Rural"
            estadd local fespec "fe`fe'"
            estadd local mod "`mod'"
            estadd local controls "`control_sample'"
            local estname evreg`i'
            local i = `i' + 1
            est store `estname'
            local estimate_names "`estimate_names' `estname'"
        }
    }

    local outbase "${tables}/_app_17_5km_fe12_evst_all${sample}_rural${ster_suffix}`control_suffix'"
    estwrite evreg* using "`outbase'.ster", replace
    estsave_csv `estimate_names' using "`outbase'.csv", replace
    confirm file "`outbase'.ster"
    confirm file "`outbase'.csv"
    confirm file "`outbase'_scalars.csv"
    display as result "Saved: `outbase'.ster and `outbase'.csv"
}

********************************************************************************

********************************************************************************
* Population-weighted stacked event study over relative months -5 through 6,
* restricted to October and November, the rice stubble-burning season.
* Period 0 is the omitted reference category.
*
* Twin of _main_2_stacked_event_study_5pre.do. The only substantive difference
* is the `keep if burning_season == 1` below; everything else -- window, rural
* filter, August 2022 cut, FE list, clustering and common-sample anchor -- is
* held identical so the two sets of estimates are comparable.
*
* READ BEFORE INTERPRETING THE EVENT-TIME PATH. Cohorts here are switch months,
* so within a cohort relative_monthyear maps one-to-one onto a calendar month.
* Restricting to October and November therefore leaves each cohort with exactly
* two surviving event-time bins, and each bin is populated by a different
* subset of roughly a sixth of the cohorts. The coefficients at bin -5 and at
* bin 6 are estimated from disjoint cohorts, so the series is NOT a within-
* cohort trajectory the way the unrestricted event study is: it is a sequence
* of cross-cohort comparisons. The diagnostic listing below prints how many
* cohorts stand behind each bin so the log records the composition.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for location, sample, rural definition, FE list,
    * and output suffix. Sbatch wrappers may override all five.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1"
    global ster_suffix  ""
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

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"

import delimited using "${int_data}/combined_dt_pop${sample}.csv", clear varnames(1)
keep if inrange(relative_monthyear, -5, 6)
gen relative_year_bin = relative_monthyear
gen relative_year_bin_aux = relative_year_bin + 6
local base = 6
assert relative_year_bin == 0 if relative_year_bin_aux == `base'
capture drop countk
gen countk = count * 1000
* October and November, the rice stubble-burning season.
gen byte burning_season = inlist(month, 10, 11)

* The restriction that defines this dofile.
quietly count
local rows_before = r(N)
keep if burning_season == 1
quietly count
local rows_after = r(N)
if `rows_after' == 0 {
    display as error "The October-November restriction removed every row."
    exit 2000
}
assert inlist(month, 10, 11)
display as result "BURNING-SEASON SAMPLE: month in (10, 11)"
display as result "Rows retained: `rows_after' of `rows_before'"

merge m:1 unique_small_grid_id using "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

confirm variable rice_prod_aclvl_ahigh
assert inlist(rice_prod_aclvl_ahigh, 0, 1)

* The base category must survive the restriction, or the event study has no
* reference period and every coefficient is measured against nothing.
quietly count if relative_year_bin == 0
if r(N) == 0 {
    display as error "No observation remains at relative month 0, the omitted period."
    exit 2000
}

* How many cohorts stand behind each event-time bin. In the unrestricted
* dofile every cohort appears in every bin; here they do not, and the spread
* across bins is what qualifies any reading of the series.
preserve
    quietly {
        keep relative_year_bin cohort
        duplicates drop
        contract relative_year_bin
        rename _freq cohorts_in_bin
    }
    display as result "Distinct cohorts contributing to each event-time bin:"
    list relative_year_bin cohorts_in_bin, noobs
restore

local dep_var countk
local fe1 "unique_small_grid_id#cohort ac_uq_id#monthyear#cohort"
* burning_season is constant at 1 here, so it cannot serve as a moderator; the
* unrestricted twin keeps it. Full list for easy reactivation there:
* local moderators_list moderator rice_prod_aclvl_ahigh burning_season
local moderators_list moderator rice_prod_aclvl_ahigh
gen moderator = 0
do "${code}/_apply_analysis_subsample.do"

* Anchor the baseline and rice-moderated event studies to the richest model's
* exact estimation sample.
quietly reghdfejl `dep_var' ///
    ib`base'.relative_year_bin_aux##ib0.treat##ib0.rice_prod_aclvl_ahigh ///
    wind_direction av_wind_speed, absorb(`fe1') ///
    cluster(ac_uq_id#cohort#monthyear unique_small_grid_id#cohort)
gen byte common_sample = e(sample)
keep if common_sample
drop common_sample
local common_n = _N

egen tag_ac = tag(ac_uq_id)
count if tag_ac == 1
local numacs = r(N)

est clear
local i = 1
local estimate_names ""
foreach mod of local moderators_list {
    replace moderator = `mod'
    local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
    * The plotted coefficients describe the omitted moderator group, so the
    * reported Mean DV is the treated pre-period mean with moderator == 0.
    * For the unmoderated estimate the condition binds nothing.
    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 0
    local ymean = r(mean)
    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)
    foreach fe of numlist $fe_list {
        reghdfejl `dep_var' `rhs', absorb(`fe`fe'') ///
            cluster(ac_uq_id#cohort#monthyear unique_small_grid_id#cohort)
        assert e(N) == `common_n'
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural Oct-Nov"
        estadd local fespec "fe`fe'"
        estadd local mod "`mod'"
        local estname evreg`i'
        local i = `i' + 1
        est store `estname'
        local estimate_names "`estimate_names' `estname'"
    }
}

local outbase "${tables}/stacked_event_study_pop_5pre_octnov${sample}_rural${ster_suffix}"
estwrite evreg* using "`outbase'.ster", replace
estsave_csv `estimate_names' using "`outbase'.csv", replace

********************************************************************************

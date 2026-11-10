********************************************************************************
* Figure 3 (fig:main_panel) by whether one party holds at least half of the
* district's ACs (dist_maj_party, _app_dist_maj_party_generation.do).
*
* Replicates _main_2_stacked_event_study_5pre.do (relative months -5 to 6,
* period 0 omitted, grid x cohort and AC x month-year x cohort FE, the same
* two-way clustering) with dist_maj_party as the moderator of the triple
* interaction relative time x treat x dist_maj_party. The indicator is fixed
* at each stack's cohort month (_merge_dist_maj_party.do).
*
* Sample. The district crosswalk follows the DISHA analysis and leaves out the
* ACs spanning several districts, so their rows are dropped and N is below
* Figure 3's. evreg1 re-estimates the plain event study on this sample;
* evreg2 adds the interaction. The coefficients plotted for
* dist_maj_party == 1 are evreg2's triple-interaction terms, as the paper's
* high-rice panels plot those of rice_prod_aclvl_ahigh.
*
* Outputs (tables/):
*   stacked_event_study_pop_5pre_distmaj${sample}_rural${ster_suffix}.ster/.csv
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

merge m:1 unique_small_grid_id using "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

do "${code}/_merge_dist_maj_party.do"

local dep_var countk
local fe1 "unique_small_grid_id#cohort ac_uq_id#monthyear#cohort"
* local moderators_list moderator rice_prod_aclvl_ahigh burning_season
local moderators_list moderator dist_maj_party
gen moderator = 0
do "${code}/_apply_analysis_subsample.do"

* Anchor both event studies to the interacted model's exact estimation sample.
quietly reghdfejl `dep_var' ///
    ib`base'.relative_year_bin_aux##ib0.treat##ib0.dist_maj_party ///
    wind_direction av_wind_speed, absorb(`fe1') ///
    cluster(ac_uq_id#cohort#monthyear unique_small_grid_id#cohort) tolerance(1e-6)
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
    * As in Figure 3, the reported Mean DV is the treated pre-period mean with
    * moderator == 0; for the unmoderated estimate the condition binds nothing.
    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 0
    local ymean = r(mean)
    quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)
    foreach fe of numlist $fe_list {
        reghdfejl `dep_var' `rhs', absorb(`fe`fe'') ///
            cluster(ac_uq_id#cohort#monthyear unique_small_grid_id#cohort) tolerance(1e-6)
        assert e(N) == `common_n'
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural, single-district ACs"
        estadd local fespec "fe`fe'"
        estadd local mod "`mod'"
        local estname evreg`i'
        local i = `i' + 1
        est store `estname'
        local estimate_names "`estimate_names' `estname'"
    }
}

local outbase "${tables}/stacked_event_study_pop_5pre_distmaj${sample}_rural${ster_suffix}"
estwrite evreg* using "`outbase'.ster", replace
estsave_csv `estimate_names' using "`outbase'.csv", replace

********************************************************************************

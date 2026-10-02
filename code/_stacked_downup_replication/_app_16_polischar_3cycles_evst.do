********************************************************************************
* Politician-characteristics event study normalized against T-2
*
* Input: politicians_characteristics_byprov_3cycles${sample}.csv, the three-term
* stack written by build_politicians_characteristics_3cycles.py. It spans T-2
* (the term before the control term, with no restriction on the politician's
* profession), T-1 (the control term) and T0 (the treated term).
*
* This is _app_16_polischar_fe12_evst_all.do with one substantive change: the
* outcome is expressed net of the grid's own level in T-2.
*
* Why the baseline is matched on calendar month, not on position in the term
* -------------------------------------------------------------------------
* Matching month k of T0 against month k of T-2 would need a 121-month
* reach-back: T-1 opens 60 months before the switch and T-2 opens 121 months
* before it. The fire series runs September 2012 to August 2022, 120 months, so
* every post-treatment month's counterpart falls before the panel begins and the
* post period would be empty in all four cohorts. That design is not estimable
* on this sample.
*
* Each observation is therefore netted against its own grid's mean for the same
* CALENDAR month inside T-2. That is estimable over the whole [-5, 4] window, it
* drops nothing, and it keeps October against October: with post-harvest burning
* concentrated in October and November, a one-month misalignment would swamp the
* outcome.
*
* T-2 is observed for 26 consecutive months (Haryana 2019-11) up to 55 (Punjab
* and Uttar Pradesh 2022-04), so every calendar month has at least two baseline
* observations. The dofile asserts that rather than assuming it.
*
* T-2 supplies the baseline only. The estimation window is the canonical
* [-5, 4], which excludes T-2 rows, exactly as in the parent dofile.
*
* Two dependent variables are estimated on one common sample:
*   countk     the raw outcome, so that the change of dataset can be told apart
*              from the change of outcome
*   countk_t2  the normalized outcome
*
* The caller selects downup_ac or downup_ac_pop through $downup_var and uses
* $ster_suffix (normally "" or "_acpop") to keep the two result families apart.
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
    global control_samples "both"

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
    global control_samples "both"
}

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"

import delimited using ///
    "${int_data}/politicians_characteristics_byprov_3cycles${sample}.csv", ///
    clear varnames(1)

* The stack stores relative_year; retain the established analysis name.
capture confirm variable relative_year_bin
if _rc {
    confirm variable relative_year
    rename relative_year relative_year_bin
}

* Always express the fire-count outcome in thousands.
capture drop countk
gen countk = count * 1000

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1

* The three-term columns are what distinguishes this input from the canonical
* one. relative_term is 0 for the treated term, -1 for the control term and -2
* for the prior term that supplies the baseline.
confirm variable relative_term
confirm variable control_term_start
confirm variable prev_term_start
confirm variable prev_term_agricultural
confirm variable row_source
assert !missing(relative_term)
assert inlist(relative_term, -2, -1, 0, 1)
assert !missing(control_term_start, prev_term_start)
assert inlist(prev_term_agricultural, 0, 1)

********************************************************************************
* Baseline: the grid's mean fire count in each calendar month of T-2.
*
* This must run before the [-5, 4] window, which is what removes the T-2 rows.
* cohort_id is part of the grouping because one grid can belong to more than one
* cohort, with a different T-2 in each.
********************************************************************************

egen double t2_countk = mean(cond(relative_term == -2, countk, .)), ///
    by(unique_small_grid_id cohort_id month)
egen int t2_obs = count(cond(relative_term == -2, countk, .)), ///
    by(unique_small_grid_id cohort_id month)

* T-2 spans at least 26 consecutive months, so no calendar month can be left
* without a baseline. If this fires, the panel's coverage of T-2 has changed and
* the normalization needs rethinking rather than patching.
assert t2_obs >= 2
assert !missing(t2_countk)

gen double countk_t2 = countk - t2_countk
label variable countk_t2 ///
    "Fires x 1,000, net of the grid's T-2 mean for the same calendar month"

* By construction the normalized outcome averages exactly zero over T-2.
quietly summarize countk_t2 if relative_term == -2
assert abs(r(mean)) < 1e-6

drop t2_obs

********************************************************************************
* Analysis sample
********************************************************************************

keep if year < 2022 | (year == 2022 & month <= 8)
keep if inrange(relative_year_bin, -5, 4)

* The politician stack carries the only substantive rice moderator used here.
confirm variable rice_prod_aclvl_ahigh
assert inlist(rice_prod_aclvl_ahigh, 0, 1)

confirm variable control_type
confirm variable cohort_id
confirm variable cohort_province
assert control_type == 0 if treat == 1
assert inlist(control_type, 1, 2) if treat == 0
assert cohort_id == floor(cohort_id) & cohort_id > 0

sort cohort_id unique_small_grid_id monthyear
by cohort_id: assert province == province[1]
by cohort_id: assert cohort == cohort[1]
by cohort_id: assert cohort_province == cohort_province[1]
by cohort_id unique_small_grid_id: assert treat == treat[1]
by cohort_id unique_small_grid_id: assert control_type == control_type[1]
by cohort_id unique_small_grid_id: assert prev_term_agricultural == prev_term_agricultural[1]
isid unique_small_grid_id monthyear cohort_id treat

egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
egen province_cohort = group(province cohort_id)
egen ac_elec_yr = group(ac_uq_id election_year cohort_id)

quietly summarize relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin - `rmin' + 1
local base = -1 - `rmin' + 1

* Final FE03 selected by the province-cohort exploratory sweep.
local fe1 "unique_small_grid_id_cohort province_cohort#c.monthyear relative_year_bin_aux#cohort_id"

local filter1 "1"
gen moderator = 0

* Baseline plus the only substantive event-study moderator.
local moderators_list moderator rice_prod_aclvl_ahigh

do "${code}/_apply_analysis_subsample.do"

tempfile analysis_base
save `analysis_base'

********************************************************************************
* Estimation loop
********************************************************************************

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
        display as error ///
            "CAUTION: control_type 2 is the legacy partial-zero-spell group; " ///
            "it is not a pure not-yet-treated sample."
    }

    display as text ///
        "Three-term politician event study: controls=`control_sample', " ///
        "downup=${downup_var}, N=" _N

    * One common sample for both dependent variables, taken from the richest
    * rice-moderated FE03 model on the normalized outcome. Neither outcome has
    * missing values, so the raw arm estimates on exactly the same rows and the
    * two arms differ only in the dependent variable.
    quietly reghdfejl countk_t2 ///
        ib`base'.relative_year_bin_aux##ib0.treat##ib0.rice_prod_aclvl_ahigh ///
        wind_direction av_wind_speed, absorb(`fe1') vce(cluster ac_elec_yr)
    gen byte common_sample = e(sample)
    keep if common_sample
    drop common_sample
    local common_n = _N

    egen tag_ac = tag(ac_uq_id)
    count if tag_ac == 1
    local numacs = r(N)

    * Share of units whose T-2 had an agricultural politician. For those the
    * baseline comes from a period that already carried the treatment, so it is
    * contaminated in the direction of the effect being measured.
    egen byte tag_unit = tag(unique_small_grid_id cohort_id)
    quietly summarize prev_term_agricultural if tag_unit == 1
    local prioragri = r(mean)
    drop tag_unit
    display as text ///
        "Units whose T-2 was agricultural: " %5.3f `prioragri'

    foreach depvar in countk countk_t2 {
        local dvnorm "none"
        if "`depvar'" == "countk_t2" local dvnorm "T-2 calendar-month mean"

        * The moderator loop below opens with `replace moderator = moderator',
        * which is a no-op, so without this reset the second dependent variable
        * would inherit the rice values left behind by the first one and its
        * unmoderated estimate would silently become a second moderated one.
        quietly replace moderator = 0

        est clear
        local i = 1
        foreach mod of local moderators_list {
            replace moderator = `mod'
            local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
            local fcond `filter1'

            * The plotted coefficients describe the omitted moderator group, so
            * the reported Mean DV is the treated pre-period mean with
            * moderator == 0. For the unmoderated estimate the condition binds
            * nothing.
            quietly summarize `depvar' if treat == 1 & relative_year_bin <= -1 & moderator == 0 & `fcond'
            local ymean = r(mean)
            quietly summarize `depvar' if treat == 1 & relative_year_bin <= -1 & moderator == 1 & `fcond'
            local ymean2 = r(mean)

            * The mean of an already-differenced outcome says little on its own,
            * so the raw pre-period mean travels alongside it.
            quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 0 & `fcond'
            local ymean_raw = r(mean)

            foreach fe of numlist $fe_list {
                local fespec `fe`fe''
                reghdfejl `depvar' `rhs' if `fcond', ///
                    absorb(`fespec') vce(cluster ac_elec_yr)
                assert e(N) == `common_n'

                estadd scalar ymean     = `ymean'
                estadd scalar ymean2    = `ymean2'
                estadd scalar ymean_raw = `ymean_raw'
                estadd scalar acq       = `numacs'
                estadd scalar prioragri = `prioragri'
                estadd local smpl "Rural"
                estadd local fespec "fe`fe'"
                estadd local mod "`mod'"
                estadd local controls "`control_sample'"
                estadd local dvar "`depvar'"
                estadd local dvnorm "`dvnorm'"
                local estname evreg`i'
                local i = `i' + 1
                est store `estname'
            }
        }

        local outbase ///
            "${tables}/_app_16_polischar_3cycles_evst${sample}_rural${ster_suffix}`control_suffix'_`depvar'"
        estwrite evreg* using "`outbase'.ster", replace
        confirm file "`outbase'.ster"
        display as result "Saved: `outbase'.ster"
    }
}

********************************************************************************

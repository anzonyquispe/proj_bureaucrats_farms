********************************************************************************
* Politician-characteristics event studies on the two-clean-cycle sample
*
* Input: politicians_characteristics_byprov_2cycles${sample}.csv, which keeps
* only the units whose AC had two consecutive non-agricultural terms before the
* switch, with the pre-period running from the start of that second term.
*
* Two estimations are stored in separate .ster files:
*
*   (1) switch    The canonical event study around the switch to an
*                 agricultural politician: control term T-1 against treated
*                 term T0. Event time is relative_year_bin, window [-5, 4],
*                 exactly as in _app_16_polischar_fe12_evst_all.do. What
*                 changes is the sample, restricted to units with two clean
*                 cycles, so this estimate is the comparable baseline for (2).
*
*   (2) turnover  The placebo, with the same [-5, 4] window shifted back one
*                 cycle: term T-2 against control term T-1, centred on the T-1
*                 election, when a new non-agricultural politician replaced
*                 another one. Event time is measured from control_term_start.
*                 The main event-time coefficients describe the control group,
*                 so they compare the new control politician against the old
*                 one; the treat interaction shows whether future switchers
*                 differ.
*
* The second cycle of the input is therefore not extra pre-period for (1); it
* is the pre-period of (2).
*
* Because the file is a row subset of politicians_characteristics_byprov, every
* cohort identifier and control_type value matches the canonical stack. Only
* the four second-round cohorts survive the two-cycle restriction.
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

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"

import delimited using ///
    "${int_data}/politicians_characteristics_byprov_2cycles${sample}.csv", ///
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
keep if year < 2022 | (year == 2022 & month <= 8)

* The two-cycle columns are what distinguishes this file from the canonical one.
confirm variable relative_term
confirm variable control_term_start
confirm variable prev_term_start
assert relative_term >= -2
assert !missing(control_term_start, prev_term_start)

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
by cohort_id unique_small_grid_id: assert control_term_start == control_term_start[1]
isid unique_small_grid_id monthyear cohort_id treat

egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
egen province_cohort = group(province cohort_id)
egen ac_elec_yr = group(ac_uq_id election_year cohort_id)

* Event time relative to the T-1 election, for the turnover placebo.
capture drop relative_month_prev relative_year_prev
gen relative_month_prev = monthyear - control_term_start
gen relative_year_prev = floor(relative_month_prev / 12)

local filter1 "1"
gen moderator = 0

* Baseline plus the only substantive event-study moderator.
local moderators_list moderator rice_prod_aclvl_ahigh

do "${code}/_apply_analysis_subsample.do"

tempfile analysis_base
save `analysis_base'

********************************************************************************
* Estimation loop
*
* Both estimations share the FE03 structure selected by the province-cohort
* sweep: grid x cohort, province-cohort linear month-year trends, and event
* year x cohort. Only the event-time variable changes.
********************************************************************************

foreach estimation in switch turnover {
    use `analysis_base', clear

    * Both estimations use the same [-5, 4] window: the cycle before the event
    * and the cycle that starts with it. They differ only in which election is
    * the event, so their coefficients are directly comparable. The two-cycle
    * sample is what makes the second one possible, because the placebo needs
    * the term before the control term as its own pre-period.
    if "`estimation'" == "switch" {
        * Control term T-1 against the treated term T0, as in the canonical
        * _app_16_polischar_fe12_evst_all.do.
        keep if inrange(relative_year_bin, -5, 4)
        local event_var "relative_year_bin"
        local event_label "switch to an agricultural politician"
    }
    else {
        * Term T-2 against the control term T-1, centred on the T-1 election.
        keep if relative_term <= -1
        keep if inrange(relative_year_prev, -5, 4)
        local event_var "relative_year_prev"
        local event_label "turnover between two non-agricultural politicians"
    }

    quietly summarize `event_var'
    local rmin = r(min)
    capture drop event_aux
    gen event_aux = `event_var' - `rmin' + 1
    local base = -1 - `rmin' + 1
    assert `event_var' == -1 if event_aux == `base'

    local fe1 "unique_small_grid_id_cohort province_cohort#c.monthyear event_aux#cohort_id"

    display as text ///
        "Two-cycle event study: `estimation' (`event_label'), " ///
        "downup=${downup_var}, N=" _N

    * Anchor the baseline and moderated estimates to the richest model's sample.
    quietly reghdfejl countk ///
        ib`base'.event_aux##ib0.treat##ib0.rice_prod_aclvl_ahigh ///
        wind_direction av_wind_speed, absorb(`fe1') vce(cluster ac_elec_yr)
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
        local rhs "ib`base'.event_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
        local fcond `filter1'

        * The plotted coefficients describe the omitted moderator group, so the
        * reported Mean DV is the treated pre-period mean with moderator == 0.
        * For the unmoderated estimate the condition binds nothing.
        quietly summarize countk if treat == 1 & relative_year_bin <= -1 & ///
            `event_var' <= -1 & moderator == 0 & `fcond'
        local ymean = r(mean)
        quietly summarize countk if treat == 1 & relative_year_bin <= -1 & ///
            `event_var' <= -1 & moderator == 1 & `fcond'
        local ymean2 = r(mean)

        foreach fe of numlist $fe_list {
            local fespec `fe`fe''
            reghdfejl countk `rhs' if `fcond', ///
                absorb(`fespec') vce(cluster ac_elec_yr)
            assert e(N) == `common_n'

            estadd scalar ymean  = `ymean'
            estadd scalar ymean2 = `ymean2'
            estadd scalar acq    = `numacs'
            estadd local smpl "Rural"
            estadd local fespec "fe`fe'"
            estadd local mod "`mod'"
            estadd local estimation "`estimation'"
            estadd local eventvar "`event_var'"
            local estname evreg`i'
            local i = `i' + 1
            est store `estname'
            local estimate_names "`estimate_names' `estname'"
        }
    }

    local outbase ///
        "${tables}/_app_16_polischar_2cycles_evst${sample}_rural${ster_suffix}_`estimation'"
    estwrite evreg* using "`outbase'.ster", replace
    confirm file "`outbase'.ster"
    display as result "Saved: `outbase'.ster"
}

********************************************************************************

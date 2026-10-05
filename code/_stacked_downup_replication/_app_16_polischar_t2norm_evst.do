********************************************************************************
* Politician-characteristics event study normalized against T-2, full sample
*
* Input: the CANONICAL politicians_characteristics_byprov${sample}.csv, with all
* eight cohorts and no restriction, plus two lookup tables written by
* build_polischar_t2_baseline.py:
*
*   politicians_characteristics_byprov_t2_baseline.dta
*       grid x cohort x calendar month -> mean MODIS fire count during T-2
*   politicians_characteristics_byprov_modis_panel.dta
*       grid x year x month -> MODIS-only fire count
*
* Why this exists alongside _app_16_polischar_3cycles_evst.do
* ----------------------------------------------------------
* That dofile reads a stack restricted to units whose T-2 is observed in the
* master. Because the master starts in 2012-09, the restriction kills four of
* the eight cohorts and truncates the post period at event year 2. But T-2 never
* enters the estimation window; it only supplies the baseline. Taking the
* baseline from a lookup table instead of from stacked rows removes the
* restriction entirely, and the sample returns to the canonical one.
*
* Why the baseline is MODIS-only
* ------------------------------
* count is a raw detection count, so it scales with how many instruments are
* observing. MODIS runs from 2000, VIIRS only from 2012. A baseline drawn from
* the combined series would be on a different scale for the old cohorts than for
* the recent ones; a single-instrument baseline is comparable across all eight.
*
* Three dependent variables are estimated on one common sample:
*   countk           MODIS + VIIRS, raw. Separates the effect of the
*                    normalization from the effect of the sample.
*   countk_t2        MODIS + VIIRS minus the MODIS T-2 baseline. The requested
*                    specification.
*   countk_modis_t2  MODIS minus the MODIS T-2 baseline. Outcome and baseline on
*                    one instrument, so the mixed subtraction can be checked.
*
* Subtracting a MODIS baseline from a MODIS+VIIRS level leaves a systematic
* positive residual equal to the VIIRS contribution. It is largely absorbed:
* the baseline is constant within grid x cohort x calendar month, so the grid x
* cohort fixed effect takes its level and the residual enters treated and
* control alike. What visibly changes is the reported mean of the outcome, which
* is why the third arm is here.
*
* Each dependent variable is run across the four-specification fixed-effect
* sweep, so one .ster holds 2 moderators x 4 specifications = 8 estimates.
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
    global fe_list      "1/4"
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
    "${int_data}/politicians_characteristics_byprov${sample}.csv", ///
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

********************************************************************************
* The T-2 baseline and the MODIS level
*
* The baseline covers every unit-cohort of the stack by construction, so an
* unmatched row means the lookup table was built from a different stack and the
* two are not comparable. That must stop the run rather than silently drop rows.
********************************************************************************

merge m:1 unique_small_grid_id cohort_id month using ///
    "${int_data}/politicians_characteristics_byprov_t2_baseline.dta", ///
    keep(master match) keepusing(t2_count_modis)
assert _merge == 3
drop _merge
assert !missing(t2_count_modis)

* A grid-month with no MODIS detection has no row in the panel, so an unmatched
* row is a true zero, exactly as the master treats the combined fire grid.
merge m:1 unique_small_grid_id year month using ///
    "${int_data}/politicians_characteristics_byprov_modis_panel.dta", ///
    keep(master match) keepusing(count_modis)
replace count_modis = 0 if missing(count_modis)
drop _merge

gen double t2_countk = t2_count_modis * 1000
gen double countk_modis = count_modis * 1000

gen double countk_t2 = countk - t2_countk
gen double countk_modis_t2 = countk_modis - t2_countk

label variable countk_t2 ///
    "Fires x 1,000, net of the grid's MODIS T-2 mean for the same calendar month"
label variable countk_modis_t2 ///
    "MODIS fires x 1,000, net of the same MODIS T-2 mean"

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
isid unique_small_grid_id monthyear cohort_id treat

egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
egen province_cohort = group(province cohort_id)
egen ac_elec_yr = group(ac_uq_id election_year cohort_id)

quietly summarize relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin - `rmin' + 1
local base = -1 - `rmin' + 1

********************************************************************************
* Fixed-effect sweep
*
*   fe1  event year x cohort only
*   fe2  plus grid x cohort
*   fe3  plus calendar month-year dummies
*   fe4  calendar time as a province-cohort linear trend instead of dummies
*
* fe3 and fe4 are not nested in each other: both add calendar time to fe2, one
* as a full set of dummies and the other as a per-province-cohort slope. fe4 is
* the production specification.
********************************************************************************

local fe1 "relative_year_bin_aux#cohort_id"
local fe2 "unique_small_grid_id_cohort relative_year_bin_aux#cohort_id"
local fe3 "unique_small_grid_id_cohort monthyear relative_year_bin_aux#cohort_id"
local fe4 "unique_small_grid_id_cohort province_cohort#c.monthyear relative_year_bin_aux#cohort_id"

* The richest specification anchors the common sample, so every cell of the
* sweep is estimated on identical rows and the comparison is about the
* specification alone.
local anchor_fe "`fe4'"

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
        "T-2 normalized politician event study: controls=`control_sample', " ///
        "downup=${downup_var}, N=" _N

    * One common sample for all three dependent variables and all four FE
    * specifications, taken from the richest rice-moderated model. It is the
    * richest one because it drops the most singletons: anchoring on anything
    * coarser would let the finer specifications shrink the sample further and
    * turn the sweep into a comparison of samples.
    quietly reghdfejl countk_t2 ///
        ib`base'.relative_year_bin_aux##ib0.treat##ib0.rice_prod_aclvl_ahigh ///
        wind_direction av_wind_speed, absorb(`anchor_fe') vce(cluster ac_elec_yr)
    gen byte common_sample = e(sample)
    keep if common_sample
    drop common_sample
    local common_n = _N

    egen tag_ac = tag(ac_uq_id)
    count if tag_ac == 1
    local numacs = r(N)

    foreach depvar in countk countk_t2 countk_modis_t2 {
        local dvnorm "none"
        if "`depvar'" != "countk" local dvnorm "MODIS T-2 calendar-month mean"

        * The moderator loop below opens with `replace moderator = moderator',
        * which is a no-op, so without this reset the later dependent variables
        * would inherit the rice values left behind by the first one and their
        * unmoderated estimates would silently become moderated ones.
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
            "${tables}/_app_16_polischar_t2norm_evst${sample}_rural${ster_suffix}`control_suffix'_`depvar'"
        estwrite evreg* using "`outbase'.ster", replace
        confirm file "`outbase'.ster"
        display as result "Saved: `outbase'.ster"
    }
}

********************************************************************************

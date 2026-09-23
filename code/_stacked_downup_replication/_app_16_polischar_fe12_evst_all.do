********************************************************************************
* Politician-characteristics event study (rural stacked sample)
*
* Input: politicians_characteristics_byprov${sample}.csv.
* Final sample: the input's unchanged treated/control composition, as in the
* politician_byprov_fe_sweep exploratory analysis. The canonical output keeps
* the historical _controls_both suffix for downstream plotting compatibility.
* Final FE (selected as FE03): grid x province-election cohort_id,
* province-cohort linear month-year trends, and event year x cohort_id.
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

import delimited using "${int_data}/politicians_characteristics_byprov${sample}.csv", ///
    clear varnames(1)

* The new stack stores relative_year; retain the established analysis name.
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

* Final FE03 selected by the province-cohort exploratory sweep.
local fe1 "unique_small_grid_id_cohort province_cohort#c.monthyear relative_year_bin_aux#cohort_id"

local filter1 "1"
gen moderator = 0

* Baseline plus the only substantive event-study moderator.
local moderators_list moderator rice_prod_aclvl_ahigh

do "${code}/_apply_analysis_subsample.do"

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
        display as error ///
            "CAUTION: control_type 2 is the legacy partial-zero-spell group; " ///
            "it is not a pure not-yet-treated sample."
    }

    display as text "Politician event study: controls=`control_sample', downup=${downup_var}, N=" _N

    * Use the richest rice-moderated FE03 event study to define a common sample
    * for the baseline and moderated estimates.
    quietly reghdfejl countk ///
        ib`base'.relative_year_bin_aux##ib0.treat##ib0.rice_prod_aclvl_ahigh ///
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
            assert e(N) == `common_n'

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

    local outbase "${tables}/_app_16_polischar_fe12_evst_all${sample}_rural${ster_suffix}`control_suffix'"
    estwrite evreg* using "`outbase'.ster", replace
    confirm file "`outbase'.ster"
    display as result "Saved: `outbase'.ster"
}

********************************************************************************

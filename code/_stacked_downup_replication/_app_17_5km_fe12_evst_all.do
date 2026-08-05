********************************************************************************
* Protest event study (rural stacked sample)
*
* Input:  stacked_data_protest5km${sample}.csv
* Output control suffixes follow the politician event-study dofile:
*   <none> = never treated; _controls_both; _controls_notyet.
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    * Standalone defaults for the five sbatch-array parameters:
    * location, sample, is_rural_var, fe_list, and ster_suffix.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural_area"
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
global tables   "${root}/tex/paper/tables"

import delimited using "${int_data}/stacked_data_protest5km${sample}.csv", ///
    clear varnames(1)

capture confirm variable relative_year_bin
if _rc {
    confirm variable relative_year
    rename relative_year relative_year_bin
}

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
    keep(master match) keepusing(is_rural_area is_rural_farzad)
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)
keep if inrange(relative_year_bin, -8, 1)

confirm variable control_type
assert control_type == 0 if treat == 1
assert inlist(control_type, 1, 2) if treat == 0

egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort)
egen province_cohort = group(province cohort)
egen ac_elec_yr = group(ac_uq_id election_year cohort)

quietly summarize relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin - `rmin' + 1
local base = -1 - `rmin' + 1

local fe1 "unique_small_grid_id_cohort province_cohort#c.monthyear province_cohort#election_year"
local filter1 "1"
gen moderator = 0

* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
local moderators_list moderator ${downup_var} rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh

tempfile analysis_base
save `analysis_base'

foreach control_sample in never both notyet {
    use `analysis_base', clear

    local control_suffix ""
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

    est clear
    local i = 1
    foreach mod of local moderators_list {
        replace moderator = `mod'
        local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
        local fcond `filter1'

        quietly summarize countk if treat == 1 & relative_year_bin <= -1 & `fcond'
        local ymean = r(mean)
        quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1 & `fcond'
        local ymean2 = r(mean)

        unique ac_uq_id if `fcond'
        local numacs = r(unique)

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
        }
    }

    local outbase "${tables}/_app_17_5km_fe12_evst_all${sample}_rural${ster_suffix}`control_suffix'"
    estwrite evreg* using "`outbase'.ster", replace
    estsave_csv evreg* using "`outbase'.csv", replace
    display as result "Saved: `outbase'.ster and `outbase'.csv"
}

********************************************************************************

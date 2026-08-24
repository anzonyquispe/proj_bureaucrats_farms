********************************************************************************
* Politician-characteristics DiD: three regular specifications followed by
* the same three specifications interacted with downup_ac_pop.
* Final input and FE follow politician_byprov_fe_sweep.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for the five sbatch-array parameters.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1/3"
    global ster_suffix  "_acpop"
    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }
}
if "$downup_var" == "" {
    global downup_var "downup_ac_pop"
}

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"

import delimited using "${int_data}/politicians_characteristics_byprov${sample}.csv", ///
    clear varnames(1)
capture confirm variable relative_year_bin
if _rc {
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

confirm variable cohort_id
confirm variable cohort_province
confirm variable control_type
assert cohort_id == floor(cohort_id) & cohort_id > 0
assert control_type == 0 if treat == 1
assert inlist(control_type, 1, 2) if treat == 0
sort cohort_id unique_small_grid_id monthyear
by cohort_id: assert province == province[1]
by cohort_id: assert cohort == cohort[1]
by cohort_id: assert cohort_province == cohort_province[1]
by cohort_id unique_small_grid_id: assert treat == treat[1]
by cohort_id unique_small_grid_id: assert control_type == control_type[1]
isid unique_small_grid_id monthyear cohort_id treat

egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
capture drop province_cohort
egen province_cohort = group(province cohort_id)
egen ac_elec_yr = group(ac_uq_id election_year cohort_id)
quietly summarize relative_year_bin
local rmin = r(min)
gen int relative_year_bin_aux = relative_year_bin - `rmin' + 1
gen post_ = relative_year_bin >= 0
gen moderator = 0

local fe1 "unique_small_grid_id_cohort relative_year_bin_aux#cohort_id"
local fe2 "unique_small_grid_id_cohort relative_year_bin_aux#cohort_id province_cohort#election_year"
local fe3 "unique_small_grid_id_cohort relative_year_bin_aux#cohort_id province_cohort#election_year province_cohort#c.monthyear"
local moderators_list moderator ${downup_var}

* Anchor every regular and interacted model to the sample retained by the
* richest FE specification with the full downup interaction.
local common_rhs "ib0.post_##ib0.treat##ib0.${downup_var} wind_direction av_wind_speed"
quietly reghdfejl countk `common_rhs', absorb(`fe3') vce(cluster ac_elec_yr)
gen byte common_sample = e(sample)
quietly count
local candidate_n = r(N)
quietly count if common_sample
local common_n = r(N)
display as text "Common-sample anchor: interacted FE specification 3"
display as text "Common estimation sample: `common_n' of `candidate_n' observations"
keep if common_sample
drop common_sample

egen tag_ac = tag(ac_uq_id)
count if tag_ac == 1
local numacs = r(N)

est clear
local i = 1
foreach mod of local moderators_list {
    replace moderator = `mod'
    local rhs "ib0.post_##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
    quietly summarize countk if treat == 1 & relative_year_bin <= -1
    local ymean = r(mean)
    quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)
    foreach fe of numlist $fe_list {
        reghdfejl countk `rhs', absorb(`fe`fe'') vce(cluster ac_elec_yr)
        if e(N) != `common_n' {
            display as error "FE specification `fe' with moderator `mod' changed the anchored sample."
            exit 459
        }
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"
        estadd local fespec "`fe`fe''"
        estadd local gridfe "Y"
        estadd local time "Y"
        local election_label = cond(`fe' >= 2, "Y", "N")
        local provtrend_label = cond(`fe' == 3, "Y", "N")
        estadd local electionfe "`election_label'"
        estadd local provtrendfe "`provtrend_label'"
        estadd local mod "`mod'"
        local estname evreg`i'
        local i = `i' + 1
        est store `estname'
    }
}

estwrite evreg1 evreg2 evreg3 evreg4 evreg5 evreg6 using ///
    "${tables}/_main_5_polischar_fe12_did_downup_inter${sample}_rural${ster_suffix}.ster", replace

********************************************************************************

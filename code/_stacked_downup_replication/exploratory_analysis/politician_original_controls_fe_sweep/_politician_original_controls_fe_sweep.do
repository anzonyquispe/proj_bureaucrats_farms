********************************************************************************
* Original politician dataset: 32 FE x 3 control-sample sweep
*
* Input:
*   politicians_characteristics.csv
*
* One invocation receives exactly one FE id and one control definition and
* estimates both:
*   1. Baseline event study, years -5,...,4, omitting -1.
*   2. DiD interaction post x treat x downup_ac_pop, following _app_19.
*
* Control definitions reproduce _app_16 exactly:
*   never  = treated + control_type 1
*   both   = treated + control_type 1 or 2
*   notyet = treated + control_type 2 (legacy partial-zero-spell group)
********************************************************************************

version 17
set processors 1

args fe_arg control_arg
local fe_env : environment POL_ORIGINAL_FE_ID
local control_env : environment POL_ORIGINAL_CONTROL_SAMPLE

if "$root" == "" {
    clear all
    set more off

    * Standalone defaults for the five standard parameters.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1"
    global ster_suffix  "_acpop"

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
    global code_shell "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
    global code_dbox  "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"

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

if "`fe_arg'" != "" {
    global fe_list "`fe_arg'"
}
else if "`fe_env'" != "" {
    global fe_list "`fe_env'"
}
local n_fe : word count $fe_list
if `n_fe' != 1 {
    display as error "Exactly one FE id is required; received: $fe_list"
    exit 198
}
local selected_fe : word 1 of $fe_list
if !inrange(real("`selected_fe'"), 1, 32) | ///
        real("`selected_fe'") != floor(real("`selected_fe'")) {
    display as error "FE id must be an integer from 1 through 32."
    exit 198
}

local control_sample "`control_arg'"
if "`control_sample'" == "" local control_sample "`control_env'"
if "`control_sample'" == "" local control_sample "never"
if !inlist("`control_sample'", "never", "both", "notyet") {
    display as error "Control sample must be never, both, or notyet."
    exit 198
}

global int_data "${root}/data_output/intermediate"
global tables_root "${code}/../../tables"
global tables "${tables_root}/exploratory_analysis/politician_original_controls_fe_sweep"
global figures_root "${code}/../../figures"
global figures "${figures_root}/exploratory_analysis/politician_original_controls_fe_sweep"
capture mkdir "${tables_root}/exploratory_analysis"
capture mkdir "${tables}"
capture mkdir "${figures_root}/exploratory_analysis"
capture mkdir "${figures}"

local input_file "${int_data}/politicians_characteristics${sample}.csv"
confirm file "`input_file'"
display as text "Input: `input_file'"
display as text "FE: `selected_fe' | controls: `control_sample'"
import delimited using "`input_file'", clear varnames(1)

capture confirm variable relative_year_bin
if _rc {
    confirm variable relative_year
    rename relative_year relative_year_bin
}

local required ///
    unique_small_grid_id province ac_uq_id count month year monthyear ///
    downup_ac_pop av_wind_speed wind_direction election_year yeargov ///
    treat cohort relative_year_bin control_type
foreach variable of local required {
    capture confirm variable `variable'
    if _rc {
        display as error "Required variable absent from original politician dataset: `variable'"
        exit 111
    }
}

assert control_type == 0 if treat == 1
assert inlist(control_type, 1, 2) if treat == 0

capture drop countk
gen double countk = count * 1000

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
count if _merge == 1
display as text "Rows without rural classification: " r(N)
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

if "`control_sample'" == "never" {
    keep if treat == 1 | control_type == 1
}
else if "`control_sample'" == "notyet" {
    keep if treat == 1 | control_type == 2
    display as error ///
        "CAUTION: control_type 2 is the legacy partial-zero-spell group; " ///
        "it is not a pure not-yet-treated sample."
}

* Use one complete-case sample for both analyses and all 32 FE definitions.
gen byte fe_complete = 1
local complete_vars ///
    unique_small_grid_id province ac_uq_id month year monthyear election_year ///
    yeargov cohort countk downup_ac_pop av_wind_speed wind_direction treat ///
    relative_year_bin control_type
foreach variable of local complete_vars {
    replace fe_complete = 0 if missing(`variable')
}
count if fe_complete == 0
display as text "Rows removed by common complete-case restriction: " r(N)
drop if fe_complete == 0
drop fe_complete

egen long unique_small_grid_id_cohort = group(unique_small_grid_id cohort)
egen long province_cohort = group(province cohort)
egen long monthyearco = group(month year cohort)
egen long ac_elec_yr = group(ac_uq_id election_year cohort)

local fe1  "unique_small_grid_id_cohort"
local fe2  "unique_small_grid_id_cohort monthyearco"
local fe3  "unique_small_grid_id_cohort province_cohort#c.monthyear"
local fe4  "unique_small_grid_id_cohort yeargov"
local fe5  "unique_small_grid_id_cohort province_cohort#election_year"
local fe6  "unique_small_grid_id_cohort province_cohort#election_year#yeargov"
local fe7  "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear"
local fe8  "unique_small_grid_id_cohort monthyearco yeargov"
local fe9  "unique_small_grid_id_cohort monthyearco province_cohort#election_year"
local fe10 "unique_small_grid_id_cohort monthyearco province_cohort#election_year#yeargov"
local fe11 "unique_small_grid_id_cohort province_cohort#c.monthyear yeargov"
local fe12 "unique_small_grid_id_cohort province_cohort#c.monthyear province_cohort#election_year"
local fe13 "unique_small_grid_id_cohort province_cohort#c.monthyear province_cohort#election_year#yeargov"
local fe14 "unique_small_grid_id_cohort yeargov province_cohort#election_year"
local fe15 "unique_small_grid_id_cohort yeargov province_cohort#election_year#yeargov"
local fe16 "unique_small_grid_id_cohort province_cohort#election_year province_cohort#election_year#yeargov"
local fe17 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear yeargov"
local fe18 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear province_cohort#election_year"
local fe19 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear province_cohort#election_year#yeargov"
local fe20 "unique_small_grid_id_cohort monthyearco yeargov province_cohort#election_year"
local fe21 "unique_small_grid_id_cohort monthyearco yeargov province_cohort#election_year#yeargov"
local fe22 "unique_small_grid_id_cohort monthyearco province_cohort#election_year province_cohort#election_year#yeargov"
local fe23 "unique_small_grid_id_cohort province_cohort#c.monthyear yeargov province_cohort#election_year"
local fe24 "unique_small_grid_id_cohort province_cohort#c.monthyear yeargov province_cohort#election_year#yeargov"
local fe25 "unique_small_grid_id_cohort province_cohort#c.monthyear province_cohort#election_year province_cohort#election_year#yeargov"
local fe26 "unique_small_grid_id_cohort yeargov province_cohort#election_year province_cohort#election_year#yeargov"
local fe27 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear yeargov province_cohort#election_year"
local fe28 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear yeargov province_cohort#election_year#yeargov"
local fe29 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear province_cohort#election_year province_cohort#election_year#yeargov"
local fe30 "unique_small_grid_id_cohort monthyearco yeargov province_cohort#election_year province_cohort#election_year#yeargov"
local fe31 "unique_small_grid_id_cohort province_cohort#c.monthyear yeargov province_cohort#election_year province_cohort#election_year#yeargov"
local fe32 "unique_small_grid_id_cohort monthyearco province_cohort#c.monthyear yeargov province_cohort#election_year province_cohort#election_year#yeargov"

local fespec "`fe`selected_fe''"
local fe_tag : display %02.0f `selected_fe'
local fe_tag = strtrim("`fe_tag'")
local output_prefix "politician_original_fe`fe_tag'_controls_`control_sample'"
display as result "FE `selected_fe': `fespec'"

tempfile full_analysis_sample
save `full_analysis_sample'

********************************************************************************
* 1. Baseline event study.
********************************************************************************

use `full_analysis_sample', clear
keep if inrange(relative_year_bin, -5, 4)
quietly summarize relative_year_bin
local rmin = r(min)
local rmax = r(max)
assert `rmin' == -5
assert `rmax' == 4
gen int relative_year_bin_aux = relative_year_bin - `rmin' + 1
local base = -1 - `rmin' + 1
gen byte moderator = 0
* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
local moderators_list moderator

count if treat == 1
local event_n_treated = r(N)
count if treat == 0
local event_n_control = r(N)
egen byte event_tag_ac = tag(ac_uq_id)
count if event_tag_ac == 1
local event_numacs = r(N)
drop event_tag_ac

quietly summarize countk if treat == 1 & relative_year_bin <= -1
local event_ymean = r(mean)
quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
local event_ymean2 = r(mean)

est clear
local event_i = 1
foreach mod of local moderators_list {
    replace moderator = `mod'
    local event_rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"

    reghdfejl countk `event_rhs', absorb(`fespec') vce(cluster ac_elec_yr)
    estadd scalar ymean = `event_ymean'
    estadd scalar ymean2 = `event_ymean2'
    estadd scalar acq = `event_numacs'
    estadd scalar fe_id = `selected_fe'
    estadd scalar n_treated = `event_n_treated'
    estadd scalar n_control = `event_n_control'
    estadd local smpl "Rural"
    estadd local fespec "`fespec'"
    estadd local mod "`mod'"
    estadd local controls "`control_sample'"
    est store evreg`event_i'
    local event_i = `event_i' + 1
}

local event_outbase "${tables}/`output_prefix'_event_rural_acpop_all"
estwrite evreg1 using "`event_outbase'.ster", replace
estsave_csv evreg1 using "`event_outbase'.csv", replace
confirm file "`event_outbase'.ster"
confirm file "`event_outbase'.csv"
confirm file "`event_outbase'_scalars.csv"
display as result "Saved event study: `event_outbase'"

********************************************************************************
* 2. DiD interaction following _app_19.
********************************************************************************

use `full_analysis_sample', clear
gen byte post_ = relative_year_bin >= 0
gen byte moderator = downup_ac_pop

count if treat == 1
local did_n_treated = r(N)
count if treat == 0
local did_n_control = r(N)
egen byte did_tag_ac = tag(ac_uq_id)
count if did_tag_ac == 1
local did_numacs = r(N)
drop did_tag_ac

quietly summarize countk if treat == 1 & relative_year_bin <= -1
local did_ymean = r(mean)
quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
local did_ymean2 = r(mean)
local did_rhs "ib0.post_##ib0.treat##ib0.downup_ac_pop wind_direction av_wind_speed"

est clear
reghdfejl countk `did_rhs', absorb(`fespec') vce(cluster ac_elec_yr)
estadd scalar ymean = `did_ymean'
estadd scalar ymean2 = `did_ymean2'
estadd scalar acq = `did_numacs'
estadd scalar fe_id = `selected_fe'
estadd scalar n_treated = `did_n_treated'
estadd scalar n_control = `did_n_control'
estadd local smpl "Rural"
estadd local fespec "`fespec'"
estadd local mod "downup_ac_pop"
estadd local controls "`control_sample'"
est store evreg1

local did_outbase "${tables}/`output_prefix'_did_interaction_rural_acpop_all"
estwrite evreg1 using "`did_outbase'.ster", replace
estsave_csv evreg1 using "`did_outbase'.csv", replace
confirm file "`did_outbase'.ster"
confirm file "`did_outbase'.csv"
confirm file "`did_outbase'_scalars.csv"
display as result "Saved DiD interaction: `did_outbase'"

display as result ///
    "COMPLETED original politician FE `selected_fe', controls=`control_sample'"

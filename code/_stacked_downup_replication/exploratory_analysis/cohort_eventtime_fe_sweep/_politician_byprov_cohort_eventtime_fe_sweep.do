********************************************************************************
* Politician-by-province FE sweep with cohort-specific relative-year fixed effects.
*
* Input: politicians_characteristics_byprov.csv
* Sample: unchanged treated/control composition; rural; through August 2022;
*         relative years -5,...,4.
* One import and one prepared sample are used for both the event-study and DiD
* interaction loops. No preserve/restore or analysis-data reload is used.
********************************************************************************
version 17
clear all
set more off
set processors 1

args fe_arg
local fe_env : environment POL_CTIME_FE_LIST
local sample_env : environment ANALYSIS_SAMPLE_SUFFIX

* Standalone defaults for the five standard sbatch parameters.
global location     "shell"
global sample       "`sample_env'"
global is_rural_var "is_rural"
global fe_list      "1/32"
global ster_suffix  "_acpop"
global root "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
global code "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
if "`fe_arg'" != "" global fe_list "`fe_arg'"
else if "`fe_env'" != "" global fe_list "`fe_env'"

foreach selected_fe of numlist $fe_list {
    if !inrange(`selected_fe', 1, 32) {
        display as error "Every FE id must be from 1 through 32."
        exit 198
    }
}

global int_data "${root}/data_output/intermediate"
global tables "${code}/../../tables/exploratory_analysis/cohort_eventtime_fe_sweep"
capture mkdir "${code}/../../tables/exploratory_analysis"
capture mkdir "${tables}"

local input_file "${int_data}/politicians_characteristics_byprov${sample}.csv"
confirm file "`input_file'"
display as text "Input: `input_file' | FE list: $fe_list"
import delimited using "`input_file'", clear varnames(1)

capture confirm variable relative_year_bin
if _rc {
    confirm variable relative_year
    rename relative_year relative_year_bin
}
local required unique_small_grid_id province ac_uq_id count month year ///
    monthyear downup_ac_pop av_wind_speed wind_direction election_year ///
    yeargov treat control_type cohort cohort_id cohort_province relative_year_bin
foreach variable of local required {
    capture confirm variable `variable'
    if _rc {
        display as error "Required variable absent: `variable'"
        exit 111
    }
}

assert cohort_id == floor(cohort_id) & cohort_id > 0
assert inlist(treat, 0, 1)
assert control_type == 0 if treat == 1
assert inlist(control_type, 1, 2) if treat == 0

gen double countk = count * 1000
merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
count if _merge == 1
display as text "Rows without rural classification: " r(N)
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)
keep if inrange(relative_year_bin, -5, 4)

gen byte fe_complete = 1
local complete_vars unique_small_grid_id province ac_uq_id month year ///
    monthyear election_year yeargov cohort cohort_id cohort_province countk ///
    downup_ac_pop av_wind_speed wind_direction treat control_type relative_year_bin
foreach variable of local complete_vars {
    replace fe_complete = 0 if missing(`variable')
}
count if fe_complete == 0
display as text "Rows removed by common complete-case restriction: " r(N)
drop if fe_complete == 0
drop fe_complete

sort cohort_id unique_small_grid_id monthyear
by cohort_id: assert province == province[1]
by cohort_id: assert cohort == cohort[1]
by cohort_id: assert cohort_province == cohort_province[1]
by cohort_id unique_small_grid_id: assert treat == treat[1]
by cohort_id unique_small_grid_id: assert control_type == control_type[1]
isid unique_small_grid_id monthyear cohort_id treat

quietly summarize relative_year_bin
assert r(min) == -5
assert r(max) == 4
gen int relative_year_bin_aux = relative_year_bin + 6
local base = 5

egen long unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
egen long province_cohort = group(province cohort_id)
egen long monthyearco = group(monthyear cohort_id)
egen long ac_elec_yr = group(ac_uq_id election_year cohort_id)

egen byte cohort_tag = tag(cohort_id)
count if cohort_tag
local number_cohorts = r(N)
drop cohort_tag
display as result "Validated province-election cohorts: `number_cohorts'"

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

* Common statistics. moderator=0 preserves the required event-study structure.
gen byte moderator = 0
* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
local moderators_list moderator
quietly summarize countk if treat == 1 & relative_year_bin <= -1
local ymean = r(mean)
quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
local ymean2 = r(mean)
egen byte tag_ac = tag(ac_uq_id)
count if tag_ac
local numacs = r(N)
drop tag_ac
count if treat == 1
local n_treated = r(N)
count if treat == 0
local n_control = r(N)

********************************************************************************
* Event studies: all requested FEs, same loaded and filtered data.
********************************************************************************
foreach mod of local moderators_list {
    replace moderator = `mod'
    local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
    foreach selected_fe of numlist $fe_list {
        local original_fespec "`fe`selected_fe''"
        local fespec "`original_fespec' relative_year_bin_aux#cohort_id"
        local tag : display %02.0f `selected_fe'
        local tag = strtrim("`tag'")
        display as result "POLITICIAN EVENT FE `selected_fe': `fespec'"
        est clear
        reghdfejl countk `rhs', absorb(`fespec') vce(cluster ac_elec_yr)
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd scalar fe_id = `selected_fe'
        estadd scalar n_treated = `n_treated'
        estadd scalar n_control = `n_control'
        estadd scalar n_cohorts = `number_cohorts'
        estadd local smpl "Rural"
        estadd local fespec "`fespec'"
        estadd local mod "`mod'"
        estadd local controls "unchanged full control composition"
        estadd local cohortvar "cohort_id"
        est store evreg1
        local out "${tables}/politician_byprov_cohorttime_fe`tag'_event_rural${ster_suffix}_all"
        estwrite evreg1 using "`out'.ster", replace
        confirm file "`out'.ster"
    }
}

********************************************************************************
* DiD interactions: same rows and same data in memory; no preserve/restore.
********************************************************************************
gen byte post_ = relative_year_bin >= 0
quietly summarize countk if treat == 1 & relative_year_bin <= -1 & downup_ac_pop == 1
local ymean2 = r(mean)
local rhs "ib0.post_##ib0.treat##ib0.downup_ac_pop wind_direction av_wind_speed"
foreach selected_fe of numlist $fe_list {
    local original_fespec "`fe`selected_fe''"
    local fespec "`original_fespec' relative_year_bin_aux#cohort_id"
    local tag : display %02.0f `selected_fe'
    local tag = strtrim("`tag'")
    display as result "POLITICIAN DID FE `selected_fe': `fespec'"
    est clear
    reghdfejl countk `rhs', absorb(`fespec') vce(cluster ac_elec_yr)
    estadd scalar ymean = `ymean'
    estadd scalar ymean2 = `ymean2'
    estadd scalar acq = `numacs'
    estadd scalar fe_id = `selected_fe'
    estadd scalar n_treated = `n_treated'
    estadd scalar n_control = `n_control'
    estadd scalar n_cohorts = `number_cohorts'
    estadd local smpl "Rural"
    estadd local fespec "`fespec'"
    estadd local mod "downup_ac_pop"
    estadd local controls "unchanged full control composition"
    estadd local cohortvar "cohort_id"
    est store evreg1
    local out "${tables}/politician_byprov_cohorttime_fe`tag'_did_interaction_rural${ster_suffix}_all"
    estwrite evreg1 using "`out'.ster", replace
    confirm file "`out'.ster"
}

display as result "COMPLETED politician cohort-event-time FE sweep: $fe_list"


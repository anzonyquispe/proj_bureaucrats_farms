********************************************************************************
* Stacked protest sample: 32 FE x 3 control definitions.
*
* One invocation receives an FE numlist (normally 1/15 or 16/32) and one
* control definition. For every FE it estimates:
*   1. Event study, relative years -8,...,1, omitting -1.
*   2. DiD interaction post x treat x downup_ac_pop.
********************************************************************************

version 17
set processors 5
args fe_arg control_arg

local fe_env : environment PROTEST_FE_LIST
local control_env : environment PROTEST_CONTROL_SAMPLE

if "$root" == "" {
    clear all
    set more off
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1/15"
    global ster_suffix  "_acpop"
    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
    global code_shell "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
    global code_dbox "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"
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

if "`fe_arg'" != "" global fe_list "`fe_arg'"
else if "`fe_env'" != "" global fe_list "`fe_env'"

local control_sample "`control_arg'"
if "`control_sample'" == "" local control_sample "`control_env'"
if "`control_sample'" == "" local control_sample "never"
if !inlist("`control_sample'", "never", "both", "notyet") {
    display as error "Control sample must be never, both, or notyet."
    exit 198
}
foreach selected_fe of numlist $fe_list {
    if !inrange(`selected_fe', 1, 32) {
        display as error "Every FE id must be from 1 through 32."
        exit 198
    }
}

global int_data "${root}/data_output/intermediate"
global tables_root "${code}/../../tables"
global tables "${tables_root}/exploratory_analysis/protest_original_controls_fe_sweep"
global figures_root "${code}/../../figures"
global figures "${figures_root}/exploratory_analysis/protest_original_controls_fe_sweep"
capture mkdir "${tables_root}/exploratory_analysis"
capture mkdir "${tables}"
capture mkdir "${figures_root}/exploratory_analysis"
capture mkdir "${figures}"

local input_file "${int_data}/stacked_data_protest5km${sample}.csv"
confirm file "`input_file'"
import delimited using "`input_file'", clear varnames(1)

capture confirm variable relative_year_bin
if _rc {
    confirm variable relative_year
    rename relative_year relative_year_bin
}
local required unique_small_grid_id province ac_uq_id count month year ///
    monthyear downup_ac_pop av_wind_speed wind_direction election_year ///
    yeargov treat cohort relative_year_bin control_type
foreach variable of local required {
    confirm variable `variable'
}
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

if "`control_sample'" == "never" {
    keep if treat == 1 | control_type == 1
}
else if "`control_sample'" == "notyet" {
    keep if treat == 1 | control_type == 2
    display as error "CAUTION: control_type 2 is the legacy partial-zero-spell group."
}

gen byte fe_complete = 1
local complete_vars unique_small_grid_id province ac_uq_id month year ///
    monthyear election_year yeargov cohort countk downup_ac_pop ///
    av_wind_speed wind_direction treat relative_year_bin control_type
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

tempfile full_analysis_sample
save `full_analysis_sample'

foreach selected_fe of numlist $fe_list {
    local fespec "`fe`selected_fe''"
    local fe_tag : display %02.0f `selected_fe'
    local fe_tag = strtrim("`fe_tag'")
    local prefix "protest_original_fe`fe_tag'_controls_`control_sample'"
    display as result "FE `selected_fe': `fespec'"

    * Baseline event study.
    use `full_analysis_sample', clear
    keep if inrange(relative_year_bin, -8, 1)
    quietly summarize relative_year_bin
    assert r(min) == -8
    assert r(max) == 1
    gen int relative_year_bin_aux = relative_year_bin + 9
    local base = 8
    gen byte moderator = 0
    * local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
    local moderators_list moderator
    count if treat == 1
    local event_n_treated = r(N)
    count if treat == 0
    local event_n_control = r(N)
    egen byte event_tag_ac = tag(ac_uq_id)
    count if event_tag_ac
    local event_numacs = r(N)
    quietly summarize countk if treat == 1 & relative_year_bin <= -1
    local event_ymean = r(mean)
    quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local event_ymean2 = r(mean)
    est clear
    foreach mod of local moderators_list {
        replace moderator = `mod'
        local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
        reghdfejl countk `rhs', absorb(`fespec') vce(cluster ac_elec_yr)
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
        est store evreg1
    }
    local event_out "${tables}/`prefix'_event_rural_acpop_all"
    estwrite evreg1 using "`event_out'.ster", replace
    estsave_csv evreg1 using "`event_out'.csv", replace
    confirm file "`event_out'_scalars.csv"

    * DiD interaction with downup_ac_pop.
    use `full_analysis_sample', clear
    gen byte post_ = relative_year_bin >= 0
    gen byte moderator = downup_ac_pop
    local moderators_list downup_ac_pop
    count if treat == 1
    local did_n_treated = r(N)
    count if treat == 0
    local did_n_control = r(N)
    egen byte did_tag_ac = tag(ac_uq_id)
    count if did_tag_ac
    local did_numacs = r(N)
    quietly summarize countk if treat == 1 & relative_year_bin <= -1
    local did_ymean = r(mean)
    quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local did_ymean2 = r(mean)
    est clear
    foreach mod of local moderators_list {
        local rhs "ib0.post_##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
        reghdfejl countk `rhs', absorb(`fespec') vce(cluster ac_elec_yr)
        estadd scalar ymean = `did_ymean'
        estadd scalar ymean2 = `did_ymean2'
        estadd scalar acq = `did_numacs'
        estadd scalar fe_id = `selected_fe'
        estadd scalar n_treated = `did_n_treated'
        estadd scalar n_control = `did_n_control'
        estadd local smpl "Rural"
        estadd local fespec "`fespec'"
        estadd local mod "`mod'"
        estadd local controls "`control_sample'"
        est store evreg1
    }
    local did_out "${tables}/`prefix'_did_interaction_rural_acpop_all"
    estwrite evreg1 using "`did_out'.ster", replace
    estsave_csv evreg1 using "`did_out'.csv", replace
    quietly do "${code}/interaction_graph.ado"
    interaction_graph using "`did_out'.ster", estimates(1) ///
        output("${figures}/`prefix'_did_interaction_rural_acpop_all") ///
        type(protest) modvar(downup_ac_pop)
    confirm file "${figures}/`prefix'_did_interaction_rural_acpop_all_1.png"
    display as result "COMPLETED protest FE `selected_fe', controls=`control_sample'"
}

********************************************************************************
* Exploratory politician event-study fixed-effect sweep
*
* Input (cluster only):
*   politicians_characteristics_byprov.csv
*
* One invocation estimates exactly one FE specification on the input dataset's
* unchanged control composition and for two moderators:
*   moderator     = baseline event study
*   downup_ac_pop = interaction event study
*
* The first command-line argument selects FE 1,...,32. If absent, $fe_list is
* used; standalone runs default to FE 1.
********************************************************************************

version 17

args fe_arg
local fe_env : environment POL_BYPROV_FE_ID

if "$root" == "" {
    clear all
    set more off

    * Standalone defaults for the five sbatch-array parameters:
    * location, sample, is_rural_var, fe_list, and ster_suffix.
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
    display as error "This exploratory job must receive exactly one FE id; received: $fe_list"
    exit 198
}
local selected_fe : word 1 of $fe_list
if !inrange(real("`selected_fe'"), 1, 32) | real("`selected_fe'") != floor(real("`selected_fe'")) {
    display as error "FE id must be an integer from 1 through 32; received: `selected_fe'"
    exit 198
}

global int_data "${root}/data_output/intermediate"
global tables_root "${code}/../../tables"
global tables "${tables_root}/exploratory_analysis/politician_byprov_fe_sweep"
capture mkdir "${tables_root}/exploratory_analysis"
capture mkdir "${tables}"

local input_file "${int_data}/politicians_characteristics_byprov${sample}.csv"
confirm file "`input_file'"
display as text "Input: `input_file'"
display as text "Selected FE: `selected_fe'"
import delimited using "`input_file'", clear varnames(1)

* The stack may retain the source name relative_year.
capture confirm variable relative_year_bin
if _rc {
    confirm variable relative_year
    rename relative_year relative_year_bin
}

local required ///
    unique_small_grid_id province ac_uq_id count month year monthyear ///
    downup_ac_pop av_wind_speed wind_direction election_year yeargov ///
    treat cohort relative_year_bin
foreach variable of local required {
    capture confirm variable `variable'
    if _rc {
        display as error "Required variable absent from politicians_characteristics_byprov.csv: `variable'"
        exit 111
    }
}

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
keep if inrange(relative_year_bin, -5, 4)

* Enforce a common complete-case sample before the FE sweep. This makes all 32
* specifications directly comparable rather than allowing FE-specific samples.
gen byte fe_complete = 1
local complete_vars ///
    unique_small_grid_id province ac_uq_id month year monthyear election_year ///
    yeargov cohort countk downup_ac_pop av_wind_speed wind_direction treat ///
    relative_year_bin
foreach variable of local complete_vars {
    replace fe_complete = 0 if missing(`variable')
}
count if fe_complete == 0
display as text "Rows removed by common FE complete-case restriction: " r(N)
drop if fe_complete == 0
drop fe_complete

egen long unique_small_grid_id_cohort = group(unique_small_grid_id cohort)
egen long province_cohort = group(province cohort)
egen long monthyearco = group(month year cohort)
egen long ac_elec_yr = group(ac_uq_id election_year cohort)

quietly summarize relative_year_bin
local rmin = r(min)
local rmax = r(max)
assert `rmin' == -5
assert `rmax' == 4
gen int relative_year_bin_aux = relative_year_bin - `rmin' + 1
local base = -1 - `rmin' + 1

* Exact exploratory FE grid supplied for this analysis.
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
display as result "FE `selected_fe': `fespec'"

gen byte moderator = 0
* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
local moderators_list moderator downup_ac_pop

count if treat == 1
local n_treated = r(N)
count if treat == 0
local n_control = r(N)
egen byte tag_ac = tag(ac_uq_id)
count if tag_ac == 1
local numacs = r(N)
drop tag_ac
display as result "FE=`selected_fe' full unchanged sample N=" _N ///
    " treated=" `n_treated' " controls=" `n_control' " ACs=" `numacs'

est clear
local i = 1
local estimate_names ""
foreach mod of local moderators_list {
    replace moderator = `mod'
    local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"

    quietly summarize countk if treat == 1 & relative_year_bin <= -1
    local ymean = r(mean)
    quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)

    reghdfejl countk `rhs', absorb(`fespec') vce(cluster ac_elec_yr)

    estadd scalar ymean = `ymean'
    estadd scalar ymean2 = `ymean2'
    estadd scalar acq = `numacs'
    estadd scalar fe_id = `selected_fe'
    estadd scalar n_treated = `n_treated'
    estadd scalar n_control = `n_control'
    estadd local smpl "Rural"
    estadd local fespec "`fespec'"
    estadd local mod "`mod'"
    estadd local controls "unchanged full sample"
    local estname evreg`i'
    local estimate_names "`estimate_names' `estname'"
    local i = `i' + 1
    est store `estname'
}

local fe_tag : display %02.0f `selected_fe'
local fe_tag = strtrim("`fe_tag'")
local outbase "${tables}/politician_byprov_fe`fe_tag'${sample}_rural${ster_suffix}_all"
estwrite `estimate_names' using "`outbase'.ster", replace
estsave_csv `estimate_names' using "`outbase'.csv", replace
confirm file "`outbase'.ster"
confirm file "`outbase'.csv"
confirm file "`outbase'_scalars.csv"
display as result "Saved: `outbase'.ster, .csv, and _scalars.csv"

display as result "COMPLETED politician by-province FE `selected_fe'"

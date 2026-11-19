* Population placebo within 13 km (Table B.6).
*
* The sample is anchored on the placebo stack with the main specification
* (Table B.3, column 4). On that common sample the three placebo columns and
* the four Table B.3 specifications are estimated and saved in separate sters.

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for the five sbatch-array parameters.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1"
    global ster_suffix  ""
    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }
}

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"

* Same filters as the main DiD (_main_1_did.do), applied to the placebo stack.
import delimited using "${int_data}/stacked_downup_13kmpl${sample}.csv", ///
    clear varnames(1)
keep if inrange(relative_monthyear, -5, 6)
display as text "Production window: relative_monthyear in [-5, 6]"

rename downup_13kmpl downup_pop_13km
assert inlist(downup_pop_13km, 0, 1)
capture drop countk
gen countk = count * 1000

capture confirm variable relative_year_bin
if _rc {
    gen relative_year_bin = relative_monthyear
}

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keepusing(is_rural) keep(3) nogen
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

capture drop moderator
gen byte moderator = 0

capture confirm numeric variable unique_small_grid_id
if _rc {
    encode unique_small_grid_id, gen(grid_id)
}
else {
    gen grid_id = unique_small_grid_id
}

capture confirm numeric variable ac_uq_id
if _rc {
    encode ac_uq_id, gen(ac_id)
}
else {
    gen ac_id = ac_uq_id
}

local controls wind_direction av_wind_speed
local cluster ac_uq_id#cohort#monthyear unique_small_grid_id#cohort

do "${code}/_apply_analysis_subsample.do"

* Common sample: Table B.3 column 4 (main specification) on the placebo stack.
quietly reghdfejl countk downup_ac_pop `controls', ///
    absorb(grid_id#cohort ac_id#monthyear#cohort) cluster(`cluster') tolerance(1e-6)
gen byte common_sample = e(sample)
quietly count
local candidate_n = r(N)
quietly count if common_sample
local common_n = r(N)
display as text "Common estimation sample: `common_n' of `candidate_n' observations"
keep if common_sample
drop common_sample

* Table B.6: placebo regressor, full sample and split by downup_ac_pop

local if1 ""
local if2 "if downup_ac_pop == 1"
local if3 "if downup_ac_pop == 0"
local fe1 "grid_id#cohort ac_id#monthyear#cohort"

est clear
forvalues i = 1/3 {
    foreach fe of numlist $fe_list {
        if `fe' != 1 {
            display as error "The placebo table defines FE specification 1 only."
            exit 198
        }
        reghdfejl countk downup_pop_13km `controls' `if`i'', ///
            absorb(`fe`fe'') cluster(`cluster') tolerance(1e-6)
        if `i' == 1 & e(N) != `common_n' {
            display as error "Warning: column 1 has " e(N) ///
                " observations, not the common `common_n'."
        }
        capture drop placebo_sample tag_ac
        gen byte placebo_sample = e(sample)
        egen byte tag_ac = tag(ac_id) if placebo_sample == 1
        quietly count if tag_ac == 1
        local numacs`i' = r(N)
        * Placebo-treated grids before the placebo switch, in this column.
        quietly summarize countk if treat == 1 & relative_year_bin <= -1 & ///
            placebo_sample == 1
        local ymean`i' = r(mean)
        quietly summarize countk if treat == 1 & relative_year_bin <= -1 & ///
            moderator == 1 & placebo_sample == 1
        local ymean2`i' = r(mean)
        estadd scalar ymean = `ymean`i''
        estadd scalar ymean2 = `ymean2`i''
        estadd scalar acq = `numacs`i''
        estadd local smpl "Rural"
        estadd local gridfe "Y"
        estadd local acmonthfe "Y"
        est store eq`i'
    }
}

estwrite eq* using ///
    "${tables}/_app_11_placebo_pop_13km${sample}_rural${ster_suffix}.ster", replace

* Table B.3 specifications (downup_ac_pop) on the same placebo common sample

quietly summarize countk if treat == 1 & relative_year_bin <= -1
local ymean = r(mean)
quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
local ymean2 = r(mean)
quietly levelsof ac_id, local(ac_levels)
local numacs : word count `ac_levels'

gen byte nofe = 1
local main_fe1 "nofe"
local main_fe2 "monthyear#cohort"
local main_fe3 "grid_id#cohort monthyear#cohort"
local main_fe4 "grid_id#cohort ac_id#monthyear#cohort"
local fespec1 "No fixed effects"
local fespec2 "Month-year x cohort"
local fespec3 "Grid x cohort and month-year x cohort"
local fespec4 "Grid x cohort and AC x month-year x cohort"
local monthyearfe1 "N"
local monthyearfe2 "Y"
local monthyearfe3 "Y"
local monthyearfe4 "N"
local gridfe1 "N"
local gridfe2 "N"
local gridfe3 "Y"
local gridfe4 "Y"
local acmonthfe1 "N"
local acmonthfe2 "N"
local acmonthfe3 "N"
local acmonthfe4 "Y"

est clear
forvalues s = 1/4 {
    reghdfejl countk downup_ac_pop `controls', ///
        absorb(`main_fe`s'') cluster(`cluster') tolerance(1e-6)
    if e(N) != `common_n' {
        display as error "Warning: B.3 specification `s' has " e(N) ///
            " observations, not the common `common_n'."
    }
    estadd scalar ymean = `ymean'
    estadd scalar ymean2 = `ymean2'
    estadd scalar acq = `numacs'
    estadd local smpl "Rural"
    estadd local fespec "`fespec`s''"
    estadd local monthyearfe "`monthyearfe`s''"
    estadd local acfe "N"
    estadd local acmonthfe "`acmonthfe`s''"
    estadd local gridfe "`gridfe`s''"
    est store main`s'
}

estwrite main* using ///
    "${tables}/_app_11_placebo_pop_13km_mainspec${sample}_rural${ster_suffix}.ster", replace


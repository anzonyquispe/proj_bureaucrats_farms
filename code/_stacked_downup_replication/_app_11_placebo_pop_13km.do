********************************************************************************
* Population placebo within 13 km, using the generated stacked placebo panel
********************************************************************************

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

import delimited using "${int_data}/stacked_downup_13kmpl${sample}.csv", ///
    clear varnames(1)

rename downup_13kmpl downup_pop_13km
capture drop countk
gen countk = count * 1000
gen relative_year_bin = relative_monthyear
gen moderator = 0

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

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

egen cluster_acmonth = group(ac_id monthyear)
egen tag_ac = tag(ac_id)
count if tag_ac == 1
local numacs = r(N)

quietly summarize countk if treat == 1 & relative_year_bin <= -1
local ymean = r(mean)
quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
local ymean2 = r(mean)

local if1 ""
local if2 "if downup_ac == 1"
local if3 "if downup_ac == 0"
local fe1 "grid_id ac_id#monthyear#cohort"

est clear
forvalues i = 1/3 {
    foreach fe of numlist $fe_list {
        if `fe' != 1 {
            display as error "The placebo table defines FE specification 1 only."
            exit 198
        }
        reghdfejl countk downup_pop_13km av_wind_speed wind_direction `if`i'', ///
            absorb(`fe`fe'') cluster(grid_id cluster_acmonth)
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        estadd local smpl "Rural"
        estadd local gridfe "Y"
        estadd local acmonthfe "Y"
        est store eq`i'
    }
}

estwrite eq* using ///
    "${tables}/_app_11_placebo_pop_13km${sample}_rural${ster_suffix}.ster", replace

********************************************************************************

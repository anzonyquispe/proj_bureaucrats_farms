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
keep if inrange(relative_monthyear, -5, 6)
display as text "Final event-study sample: relative_monthyear in [-5, 6]"

* Restrict the placebo stack to the exact observation keys retained by
* specification 4 of the main population DiD.
merge m:1 unique_small_grid_id monthyear cohort using ///
    "${int_data}/main_downup_ac_pop_esample_keys${sample}.dta"
quietly count if _merge == 2
assert r(N) == 0
keep if _merge == 3
drop _merge
display as text "Placebo rows in canonical main sample: " _N

rename downup_13kmpl downup_pop_13km
capture drop countk
gen countk = count * 1000
gen moderator = 0

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
bysort unique_small_grid_id: egen byte ever_downup_pop_13km = max(downup_pop_13km)

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
        reghdfejl countk downup_pop_13km av_wind_speed wind_direction `if`i'', ///
            absorb(`fe`fe'') cluster(grid_id cluster_acmonth)
        capture drop placebo_sample tag_ac
        gen byte placebo_sample = e(sample)
        egen byte tag_ac = tag(ac_id) if placebo_sample == 1
        quietly count if tag_ac == 1
        local numacs`i' = r(N)
        quietly summarize countk if ever_downup_pop_13km == 1 & ///
            downup_pop_13km == 0 & placebo_sample == 1
        local ymean`i' = r(mean)
        quietly summarize countk if ever_downup_pop_13km == 1 & ///
            downup_pop_13km == 0 & moderator == 1 & placebo_sample == 1
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

********************************************************************************

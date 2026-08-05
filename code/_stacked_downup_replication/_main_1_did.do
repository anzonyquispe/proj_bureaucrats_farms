********************************************************************************
* Main stacked DiD: assembly-constituency treatment
*
* The master runs this file twice:
*   combined_dt.csv      / downup_ac      (area-weighted treatment)
*   combined_dt_pop.csv  / downup_ac_pop  (population-weighted treatment)
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    * Five sbatch-array parameters; defaults apply only to standalone runs.
    global location "shell"
    global sample ""
    global is_rural_var "is_rural_area"
    global fe_list "1/4"
    global ster_suffix "_stacked"

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }
}

* Extra switches set by the master; the defaults reproduce the area treatment.
if "$stacked_file" == "" {
    global stacked_file "combined_dt"
}
if "$downup_var" == "" {
    global downup_var "downup_ac"
}
if "$did_output" == "" {
    global did_output "main_did_downup_area_ac"
}

global int_data "${root}/data_output/intermediate"
global tables "${root}/tex/paper/tables"

import delimited "${int_data}/${stacked_file}${sample}.csv", clear varnames(1)

* Always express the fire-count outcome in thousands.
capture drop countk
gen double countk = count * 1000

capture confirm variable relative_year_bin
if _rc {
    capture confirm variable relative_year
    if !_rc {
        gen relative_year_bin = relative_year
    }
    else {
        gen relative_year_bin = floor(relative_monthyear / 12)
    }
}

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keepusing(is_rural_area is_rural_farzad) keep(3) nogen
keep if ${is_rural_var} == 1

* Do not drop grids that intersect more than one assembly constituency.
* capture confirm variable grids_with_more_1_ac
* if _rc {
*     merge m:1 unique_small_grid_id using ///
*         "${int_data}/grids_with_more_1_ac.dta", keep(master match) nogen
*     capture confirm variable dpl_ac
*     if !_rc {
*         drop if dpl_ac == 1
*     }
* }
keep if year < 2022 | (year == 2022 & month <= 8)

capture confirm variable treat
if _rc {
    bysort unique_small_grid_id: egen byte treat = max(${downup_var})
}
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

quietly summarize countk if treat == 1 & relative_year_bin <= -1
local ymean = r(mean)
quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
local ymean2 = r(mean)
quietly levelsof ac_id, local(ac_levels)
local numacs : word count `ac_levels'

local controls wind_direction av_wind_speed
local cluster ac_uq_id#cohort#monthyear unique_small_grid_id#cohort
local fespec1 "No fixed effects"
local fespec2 "AC and month-year"
local fespec3 "AC x month-year"
local fespec4 "Grid and AC x month-year"
local estimates ""

foreach fe of numlist $fe_list {
    if `fe' == 1 {
        reg countk ${downup_var} `controls', vce(cluster grid_id)
    }
    else if `fe' == 2 {
        reghdfejl countk ${downup_var} `controls', ///
            absorb(ac_id#cohort monthyear#cohort) cluster(`cluster')
    }
    else if `fe' == 3 {
        reghdfejl countk ${downup_var} `controls', ///
            absorb(ac_id#monthyear#cohort) cluster(`cluster')
    }
    else if `fe' == 4 {
        reghdfejl countk ${downup_var} `controls', ///
            absorb(grid_id#cohort ac_id#monthyear#cohort) cluster(`cluster')
    }
    else {
        display as error "Unsupported FE specification `fe'; use 1/4."
        exit 198
    }

    estadd scalar ymean = `ymean'
    estadd scalar ymean2 = `ymean2'
    estadd scalar acq = `numacs'
    estadd local smpl "Rural"
    estadd local fespec "`fespec`fe''"
    local estimates `estimates' eq`fe'
    est store eq`fe'
}

estwrite `estimates' using ///
    "${tables}/${did_output}${sample}_rural${ster_suffix}.ster", replace

display "Saved ${tables}/${did_output}${sample}_rural${ster_suffix}.ster"

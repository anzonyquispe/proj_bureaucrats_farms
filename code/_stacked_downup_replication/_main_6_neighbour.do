********************************************************************************
* Neighbour-border analysis for figures/neighbor_output.pdf
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
}

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"

import delimited "${int_data}/stacked_downup_neigh${sample}.csv", clear varnames(1)
capture confirm variable relative_monthyear
if _rc {
    gen relative_monthyear = monthyear - cohort
}
keep if inrange(relative_monthyear, -5, 6)
display as text "Final event-study sample: relative_monthyear in [-5, 6]"
merge m:1 unique_small_grid_id using "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

capture drop countk
gen countk = count * 1000
capture confirm variable treat
if _rc {
    gen byte treat = downwind_neighbours
}
capture confirm variable relative_year_bin
if _rc {
    capture confirm variable relative_monthyear
    if !_rc {
        gen relative_year_bin = floor(relative_monthyear / 12)
    }
    else {
        gen relative_year_bin = floor((monthyear - cohort) / 12)
    }
}
gen moderator = 0

do "${code}/exploratory_analysis/rice_high_subsample/_apply_rice_high_subsample.do"

quietly summarize countk if treat == 1 & relative_year_bin <= -1
local ymean = r(mean)
quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
local ymean2 = r(mean)
egen tag_ac = tag(ac_uq_id)
count if tag_ac == 1
local numacs = r(N)

local fe1 "ac_uq_id#ac_uq_id_neighbor#month#year#cohort unique_small_grid_id#cohort"
foreach fe of numlist $fe_list {
    if `fe' != 1 {
        display as error "The neighbour figure defines FE specification 1 only."
        exit 198
    }
    reghdfejl countk b5.dist_q##b0.downwind_neighbours, ///
        absorb(`fe`fe'') ///
        cluster(ac_uq_id#month#year unique_small_grid_id)
    estadd scalar ymean = `ymean'
    estadd scalar ymean2 = `ymean2'
    estadd scalar acq = `numacs'
    estadd local smpl "Rural"
    estadd local fespec "fe`fe'"
    est store reg`fe'
}

estwrite reg1 using ///
    "${tables}/main_figure4_neighbour${sample}_rural${ster_suffix}.ster", replace

********************************************************************************

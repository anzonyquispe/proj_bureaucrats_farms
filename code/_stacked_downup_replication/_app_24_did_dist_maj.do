********************************************************************************
* Table B.3 (tab:main_DID) by whether one party holds at least half of the
* district's ACs (dist_maj_party, _app_dist_maj_party_generation.do).
*
* Replicates the population-weighted DiD of _main_1_did.do (combined_dt_pop,
* Down>Up = downup_ac_pop, relative months -5 to 6, the four FE columns, the
* same two-way clustering) and adds the interaction
*     countk = b1 Down>Up + b2 Down>Up x Majority + b3 Majority + controls + FE,
* with Majority = dist_maj_party fixed at each stack's cohort month
* (_merge_dist_maj_party.do). Within a stack it is constant for a grid, so b3
* is absorbed in columns 3 and 4 (grid x cohort FE) and left blank there,
* while b2 stays identified. As the team asked, the table only adds the
* interaction to B.3.
*
* Sample. As in _app_23, the rows of ACs spanning several districts are
* dropped, so N is below B.3's. The richest column fixes the common sample.
*
* Outputs (tables/):
*   main_did_downup_pop_ac_distmaj${sample}_rural${ster_suffix}.ster
*   main_did_downup_ac_distmaj${sample}_rural_acpop${ster_suffix}.tex
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    * Five sbatch-array parameters; defaults apply only to standalone runs.
    global location "shell"
    global sample ""
    global is_rural_var "is_rural"
    global fe_list "1/4"
    global ster_suffix ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
    global code_shell "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
    global code_dbox "/Users/anzony.quisperojas/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"
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
global tables "${code}/../../tables"

import delimited "${int_data}/combined_dt_pop${sample}.csv", clear varnames(1)

capture drop countk
gen countk = count * 1000
keep if inrange(relative_monthyear, -5, 6)
gen relative_year_bin = relative_monthyear

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keepusing(is_rural) keep(3) nogen
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

capture confirm variable treat
if _rc {
    bysort unique_small_grid_id: egen byte treat = max(downup_ac_pop)
}

do "${code}/_merge_dist_maj_party.do"
gen byte moderator = dist_maj_party

capture confirm numeric variable unique_small_grid_id
if _rc {
    encode unique_small_grid_id, gen(grid_id)
}
else {
    gen grid_id = unique_small_grid_id
}
gen ac_id = ac_uq_id

local rhs c.downup_ac_pop##c.dist_maj_party wind_direction av_wind_speed
local cluster ac_uq_id#cohort#monthyear unique_small_grid_id#cohort
local fespec1 "No fixed effects"
local fespec2 "Month-year x cohort"
local fespec3 "Grid x cohort and month-year x cohort"
local fespec4 "Grid x cohort and AC x month-year x cohort"
local estimates ""

do "${code}/_apply_analysis_subsample.do"

* Common sample: the richest displayed specification.
quietly reghdfejl countk `rhs', ///
    absorb(grid_id#cohort ac_id#monthyear#cohort) cluster(`cluster') tolerance(1e-6)
gen byte common_sample = e(sample)
quietly count
local candidate_n = r(N)
quietly count if common_sample
local common_n = r(N)
display as text "Common estimation sample: `common_n' of `candidate_n' observations"
keep if common_sample
drop common_sample

quietly summarize countk if treat == 1 & relative_year_bin <= -1
local ymean = r(mean)
quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
local ymean2 = r(mean)
quietly levelsof ac_id, local(ac_levels)
local numacs : word count `ac_levels'

gen byte nofe = 1

foreach fe of numlist $fe_list {
    if `fe' == 1 {
        reghdfejl countk `rhs', ///
            absorb(nofe) cluster(`cluster') tolerance(1e-6)
        local monthyearfe "N"
        local acmonthfe "N"
        local gridfe "N"
    }
    else if `fe' == 2 {
        reghdfejl countk `rhs', ///
            absorb(monthyear#cohort) cluster(`cluster') tolerance(1e-6)
        local monthyearfe "Y"
        local acmonthfe "N"
        local gridfe "N"
    }
    else if `fe' == 3 {
        reghdfejl countk `rhs', ///
            absorb(grid_id#cohort monthyear#cohort) cluster(`cluster') tolerance(1e-6)
        local monthyearfe "Y"
        local acmonthfe "N"
        local gridfe "Y"
    }
    else if `fe' == 4 {
        reghdfejl countk `rhs', ///
            absorb(grid_id#cohort ac_id#monthyear#cohort) cluster(`cluster') tolerance(1e-6)
        local monthyearfe "N"
        local acmonthfe "Y"
        local gridfe "Y"
    }
    else {
        display as error "Unsupported FE specification `fe'; use 1/4."
        exit 198
    }

    if e(N) != `common_n' {
        display as error "FE specification `fe' changed the anchored estimation sample."
        exit 459
    }

    estadd scalar ymean = `ymean'
    estadd scalar ymean2 = `ymean2'
    estadd scalar acq = `numacs'
    estadd local smpl "Rural, single-district ACs"
    estadd local fespec "`fespec`fe''"
    estadd local mod "dist_maj_party"
    estadd local monthyearfe "`monthyearfe'"
    estadd local acmonthfe "`acmonthfe'"
    estadd local gridfe "`gridfe'"
    local estimates `estimates' eq`fe'
    est store eq`fe'
}

estwrite `estimates' using ///
    "${tables}/main_did_downup_pop_ac_distmaj${sample}_rural${ster_suffix}.ster", replace

local ncols : word count `estimates'
local header ""
forvalues j = 1/`ncols' {
    local header "`header' &\multicolumn{1}{c}{(`j')}"
}

* Layout of B.3 (_generate_all_tables.do) with the interaction rows.
esttab `estimates' using ///
    "${tables}/main_did_downup_ac_distmaj${sample}_rural_acpop${ster_suffix}.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac_pop c.downup_ac_pop#c.dist_maj_party dist_maj_party) ///
    order(downup_ac_pop c.downup_ac_pop#c.dist_maj_party dist_maj_party) ///
    varlabels(downup_ac_pop "Down \$>\$ Up" ///
              c.downup_ac_pop#c.dist_maj_party "Down \$>\$ Up \$\times\$ Majority Party" ///
              dist_maj_party "Majority Party") ///
    stats(N acq monthyearfe gridfe acmonthfe ymean, ///
          fmt(%12.0fc %12.0fc %s %s %s %9.3f) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "Month-Year \$\times\$ Cohort FE" ///
                 "Grid \$\times\$ Cohort FE" ///
                 "AC \$\times\$ Month-Year \$\times\$ Cohort FE" ///
                 "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels noomitted ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{`ncols'}{c}}" ///
            "\hline" ///
            "           `header' \\" ///
            "            & \multicolumn{`ncols'}{c}{Number of Fires (in 1,000 units)} \\ \hline") ///
    posthead("") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Saved ${tables}/main_did_downup_ac_distmaj${sample}_rural_acpop${ster_suffix}.tex"

********************************************************************************

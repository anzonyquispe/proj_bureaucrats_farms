********************************************************************************
* Figure 3 (fig:main_panel) with coarser standard-error clustering.
*
* Replicates _main_2_stacked_event_study_5pre.do (same sample, fixed effects,
* controls and moderators) and changes only the AC dimension of the two-way
* clustering. The paper clusters on AC x cohort x month-year and grid x cohort;
* this file re-estimates with
*   cl_acmy:   AC x month-year (all stacked copies of an AC-month together)
*   cl_distmy: district x month-year
* keeping grid x cohort as the second dimension. Point estimates must equal
* Figure 3; only the standard errors change.
*
* Outputs (tables/):
*   stacked_event_study_pop_5pre_cl_acmy${sample}_rural${ster_suffix}.ster/.csv
*   stacked_event_study_pop_5pre_cl_distmy${sample}_rural${ster_suffix}.ster/.csv
*   main_event_study_cluster${sample}_rural${ster_suffix}.tex: the baseline
*     event study (tab:main_event_study) under the paper's and both new
*     clusterings, side by side.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for location, sample, rural definition, FE list,
    * and output suffix. Sbatch wrappers may override all five.
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
    quietly do "${code}/estsave_csv.ado"
}

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"

* The paper's baseline estimate, loaded first so it can sit next to the new
* clusterings in the comparison table.
est clear
local paper_ster "${tables}/stacked_event_study_pop_5pre${sample}_rural${ster_suffix}.ster"
local has_paper = 0
capture confirm file "`paper_ster'"
if !_rc {
    capture noisily estread using "`paper_ster'"
    if !_rc {
        est restore evreg1
        est store tab_paper
        est drop evreg*
        local has_paper = 1
    }
}
if !`has_paper' {
    display as error "Paper estimate not found: `paper_ster'"
    display as error "The comparison table will only show the new clusterings."
}

import delimited using "${int_data}/combined_dt_pop${sample}.csv", clear varnames(1)
keep if inrange(relative_monthyear, -5, 6)
gen relative_year_bin = relative_monthyear
gen relative_year_bin_aux = relative_year_bin + 6
local base = 6
assert relative_year_bin == 0 if relative_year_bin_aux == `base'
capture drop countk
gen countk = count * 1000
* October and November, the rice stubble-burning season.
gen byte burning_season = inlist(month, 10, 11)

merge m:1 unique_small_grid_id using "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

confirm variable rice_prod_aclvl_ahigh
assert inlist(rice_prod_aclvl_ahigh, 0, 1)
confirm numeric variable distr_id

local dep_var countk
local fe1 "unique_small_grid_id#cohort ac_uq_id#monthyear#cohort"
* local moderators_list moderator rice_prod_aclvl_ahigh burning_season
local moderators_list moderator rice_prod_aclvl_ahigh
gen moderator = 0
do "${code}/_apply_analysis_subsample.do"

* Anchor every model to the exact estimation sample of Figure 3.
quietly reghdfejl `dep_var' ///
    ib`base'.relative_year_bin_aux##ib0.treat##ib0.rice_prod_aclvl_ahigh ///
    wind_direction av_wind_speed, absorb(`fe1') ///
    cluster(ac_uq_id#cohort#monthyear unique_small_grid_id#cohort) tolerance(1e-6)
gen byte common_sample = e(sample)
keep if common_sample
drop common_sample
local common_n = _N

* A row without distr_id would drop out of the district-clustered model and
* change its sample, so it gets its own AC-level cluster instead.
count if missing(distr_id)
local nodistrict = r(N)
display as result "Rows without distr_id (clustered by AC instead): `nodistrict' of `common_n'"
egen long ac_cl = group(ac_uq_id)
gen long distr_cl = distr_id
replace distr_cl = -ac_cl if missing(distr_cl)
egen tag_distr = tag(distr_cl)
count if tag_distr == 1
display as result "District clusters: " r(N)

egen tag_ac = tag(ac_uq_id)
count if tag_ac == 1
local numacs = r(N)

foreach cl in cl_acmy cl_distmy {
    if "`cl'" == "cl_acmy" {
        local cluster_variables "ac_uq_id#monthyear unique_small_grid_id#cohort"
        local cluster_tag "AC x month-year; grid x cohort"
    }
    else {
        local cluster_variables "distr_cl#monthyear unique_small_grid_id#cohort"
        local cluster_tag "District x month-year; grid x cohort"
    }
    * The previous clustering left the last moderator in this stub.
    replace moderator = 0

    local i = 1
    local estimate_names ""
    foreach mod of local moderators_list {
        replace moderator = `mod'
        local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"
        * Same Mean DV as Figure 3: the treated pre-period mean of the omitted
        * moderator group, which binds nothing for the unmoderated estimate.
        quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 0
        local ymean = r(mean)
        quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1
        local ymean2 = r(mean)
        foreach fe of numlist $fe_list {
            reghdfejl `dep_var' `rhs', absorb(`fe`fe'') ///
                cluster(`cluster_variables') tolerance(1e-6)
            assert e(N) == `common_n'
            estadd scalar ymean = `ymean'
            estadd scalar ymean2 = `ymean2'
            estadd scalar acq = `numacs'
            estadd scalar nodistrict = `nodistrict'
            estadd local smpl "Rural"
            estadd local fespec "fe`fe'"
            estadd local mod "`mod'"
            estadd local clusterspec "`cluster_tag'"
            local estname evreg`i'
            local i = `i' + 1
            est store `estname'
            local estimate_names "`estimate_names' `estname'"
        }
    }

    local outbase "${tables}/stacked_event_study_pop_5pre_`cl'${sample}_rural${ster_suffix}"
    estwrite evreg* using "`outbase'.ster", replace
    * estsave_csv replaces the data in memory, which the next clustering needs.
    preserve
    estsave_csv `estimate_names' using "`outbase'.csv", replace
    restore

    est restore evreg1
    est store tab_`cl'
    est drop evreg*
}

********************************************************************************
* Comparison table: tab:main_event_study under each clustering.
********************************************************************************

local columns "tab_cl_acmy tab_cl_distmy"
if `has_paper' local columns "tab_paper `columns'"
foreach c of local columns {
    est restore `c'
    if "`c'" == "tab_paper"     local first_dim "AC \$\times\$ cohort \$\times\$ month-year"
    if "`c'" == "tab_cl_acmy"   local first_dim "AC \$\times\$ month-year"
    if "`c'" == "tab_cl_distmy" local first_dim "District \$\times\$ month-year"
    estadd local first_dim "`first_dim'", replace
    estadd local gridfe "Y", replace
    estadd local acmonthfe "Y", replace
    est store `c'
}

local ncols : word count `columns'
local header ""
forvalues j = 1/`ncols' {
    local header "`header' & \multicolumn{1}{c}{(`j')}"
}

esttab `columns' using "${tables}/main_event_study_cluster${sample}_rural${ster_suffix}.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    order(*relative*) ///
    keep(*aux#1.treat wind_direction av_wind_speed) ///
    varlabels(1.relative_year_bin_aux#1.treat "Relative Period = -5 \$\times\$ Down\$>\$Up" 2.relative_year_bin_aux#1.treat "Relative Period = -4 \$\times\$ Down\$>\$Up" 3.relative_year_bin_aux#1.treat "Relative Period = -3 \$\times\$ Down\$>\$Up" 4.relative_year_bin_aux#1.treat "Relative Period = -2 \$\times\$ Down\$>\$Up" 5.relative_year_bin_aux#1.treat "Relative Period = -1 \$\times\$ Down\$>\$Up" 7.relative_year_bin_aux#1.treat "Relative Period = 1 \$\times\$ Down\$>\$Up" 8.relative_year_bin_aux#1.treat "Relative Period = 2 \$\times\$ Down\$>\$Up" 9.relative_year_bin_aux#1.treat "Relative Period = 3 \$\times\$ Down\$>\$Up"  10.relative_year_bin_aux#1.treat "Relative Period = 4 \$\times\$ Down\$>\$Up" 11.relative_year_bin_aux#1.treat "Relative Period = 5 \$\times\$ Down\$>\$Up" 12.relative_year_bin_aux#1.treat "Relative Period = 6 \$\times\$ Down\$>\$Up" wind_direction "Wind Direction" av_wind_speed "Av. Wind Speed" ) ///
    stats(N acq gridfe acmonthfe first_dim N_clust1 N_clust2 ymean, ///
          fmt(%12.0fc %12.0fc %s %s %s %12.0fc %12.0fc %9.3f) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "Grid \$\times\$ Cohort FE" ///
                 "AC \$\times\$ Month-Year \$\times\$ Cohort FE" ///
                 "Cluster: first dimension" ///
                 "N clusters, first dimension" ///
                 "N clusters, grid \$\times\$ cohort" ///
                 "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{`ncols'}{c}}" ///
            "\hline" ///
            "           `header' \\" ///
            "            & \multicolumn{`ncols'}{c}{Number of Fires (in 1,000 units)} \\ \hline") ///
    posthead("") ///
    postfoot("\hline" "\end{tabular}" "}")

display as result "Saved main_event_study_cluster${sample}_rural${ster_suffix}.tex"

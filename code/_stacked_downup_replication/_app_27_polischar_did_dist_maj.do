********************************************************************************
* Table D.3 (tab:agri_profession_downwind) x dist_maj_party.
* Same spec as _main_5, with ##dist_maj_party added to the interaction.
* Indicator from the term the election opens. Drops ACs spanning several
* districts. No Panel B.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for the five sbatch-array parameters.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "0/3"
    global ster_suffix  "_acpop"
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
if "$downup_var" == "" {
    global downup_var "downup_ac_pop"
}

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"

import delimited using "${int_data}/politicians_characteristics_byprov${sample}.csv", ///
    clear varnames(1)
capture confirm variable relative_year_bin
if _rc {
    rename relative_year relative_year_bin
}
* Always express the fire-count outcome in thousands.
capture drop countk
gen countk = count * 1000

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural)
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)
keep if inrange(relative_year_bin, -5, 4)

confirm variable cohort_id
sort cohort_id unique_small_grid_id monthyear
by cohort_id: assert cohort == cohort[1]
by cohort_id unique_small_grid_id: assert treat == treat[1]

do "${code}/_merge_dist_maj_party.do"
* Cohort = month the new assembly took office.
assert year_el == floor((cohort - 1) / 12)

egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
capture drop province_cohort
egen province_cohort = group(province cohort_id)
egen ac_elec_yr = group(ac_uq_id election_year cohort_id)
egen relativeyear_cohort = group(relative_year_bin cohort_id)
gen post_ = relative_year_bin >= 0
gen moderator = 0
gen byte nofe = 1

* FE progression of D.3:
*   (0) no FE (constant-only absorbed category)
*   (1) grid x cohort
*   (2) grid x cohort + relative year x cohort
*   (3) grid x cohort + relative year x cohort + province x cohort trend
local fe0 "nofe"
local fe1 "unique_small_grid_id_cohort"
local fe2 "unique_small_grid_id_cohort relativeyear_cohort"
local fe3 "unique_small_grid_id_cohort relativeyear_cohort province_cohort#c.monthyear"
local moderators_list moderator ${downup_var}

* Common sample: interacted FE3 model.
local common_rhs "ib0.post_##ib0.treat##ib0.${downup_var}##ib0.dist_maj_party wind_direction av_wind_speed"
do "${code}/_apply_analysis_subsample.do"

quietly reghdfejl countk `common_rhs', absorb(`fe3') vce(cluster ac_elec_yr) tolerance(1e-6)
gen byte common_sample = e(sample)
quietly count
local candidate_n = r(N)
quietly count if common_sample
local common_n = r(N)
display as text "Common estimation sample: `common_n' of `candidate_n' observations"
keep if common_sample
drop common_sample

egen tag_ac = tag(ac_uq_id)
count if tag_ac == 1
local numacs = r(N)

est clear
local i = 1
local estimates ""
foreach mod of local moderators_list {
    replace moderator = `mod'
    local rhs "ib0.post_##ib0.treat##ib0.`mod'##ib0.dist_maj_party wind_direction av_wind_speed"
    quietly summarize countk if treat == 1 & relative_year_bin <= -1
    local ymean = r(mean)
    quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
    local ymean2 = r(mean)
    foreach fe of numlist $fe_list {
        reghdfejl countk `rhs', absorb(`fe`fe'') vce(cluster ac_elec_yr) tolerance(1e-6)
        if e(N) != `common_n' {
            display as error "FE specification `fe' with moderator `mod' changed the anchored sample."
            exit 459
        }
        estadd scalar ymean = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar acq = `numacs'
        * Mean DV as D.3 prints it (blank when missing).
        foreach s in ymean ymean2 {
            local raw = strtrim(string(``s'', "%9.3f"))
            local cleaned = regexr(regexr("`raw'", "0+$", ""), "\.$", "")
            estadd local `s'_clean "`cleaned'"
        }
        estadd local smpl "Rural, single-district ACs"
        estadd local fespec "`fe`fe''"
        local grid_label = cond(`fe' == 0, "N", "Y")
        estadd local gridfe "`grid_label'"
        local time_label = cond(`fe' >= 2, "Y", "N")
        local provtrend_label = cond(`fe' == 3, "Y", "N")
        estadd local time "`time_label'"
        estadd local electionfe "N"
        estadd local provtrendfe "`provtrend_label'"
        estadd local mod "`mod'"
        local estname evreg`i'
        local i = `i' + 1
        local estimates "`estimates' `estname'"
        est store `estname'
    }
}

local outbase "${tables}/_main_5_polischar_fe12_did_downup_inter_distmaj${sample}_rural${ster_suffix}"
estwrite `estimates' using "`outbase'.ster", replace

local du ${downup_var}
local rows ///
    1.post_#1.treat 1.post_#1.treat#1.dist_maj_party ///
    1.`du' 1.`du'#1.dist_maj_party ///
    1.post_#1.`du' 1.post_#1.`du'#1.dist_maj_party ///
    1.treat#1.`du' 1.treat#1.`du'#1.dist_maj_party ///
    1.post_#1.treat#1.`du' 1.post_#1.treat#1.`du'#1.dist_maj_party ///
    1.dist_maj_party

* D.3 layout plus the interaction rows.
esttab `estimates' using "`outbase'.tex", ///
    replace fragment ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(`rows') order(`rows') ///
    varlabels(1.post_#1.treat "Post \$\times\$ Switch Agric" ///
              1.post_#1.treat#1.dist_maj_party "Post \$\times\$ Switch Agric \$\times\$ Majority Party" ///
              1.`du' "Down \$>\$ Up" ///
              1.`du'#1.dist_maj_party "Down \$>\$ Up \$\times\$ Majority Party" ///
              1.post_#1.`du' "Post \$\times\$ Down \$>\$ Up" ///
              1.post_#1.`du'#1.dist_maj_party "Post \$\times\$ Down \$>\$ Up \$\times\$ Majority Party" ///
              1.treat#1.`du' "Switch Agric \$\times\$ Down \$>\$ Up" ///
              1.treat#1.`du'#1.dist_maj_party "Switch Agric \$\times\$ Down \$>\$ Up \$\times\$ Majority Party" ///
              1.post_#1.treat#1.`du' "Post \$\times\$ Switch Agric \$\times\$ Down \$>\$ Up" ///
              1.post_#1.treat#1.`du'#1.dist_maj_party "Post \$\times\$ Switch Agric \$\times\$ Down \$>\$ Up \$\times\$ Majority Party" ///
              1.dist_maj_party "Majority Party") ///
    stats(N acq gridfe time provtrendfe ymean_clean ymean2_clean, ///
          fmt(%12.0fc %12.0fc %s %s %s %s %s) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "Grid \$\times\$ Cohort FE" "Relative Time \$\times\$ Cohort FE" ///
                 "Province Trend \$\times\$ Cohort FE" ///
                 "Mean DV" "Mean DV2 (Down\$>\$Up=1)")) ///
    nomtitles nonumbers collabels(none) nobaselevels noomitted ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{8}{c}}" ///
            "\hline" ///
            " & (1) & (2) & (3) & (4) & (5) & (6) & (7) & (8) \\" ///
            "            & \multicolumn{8}{c}{Number of Fires (per 1,000 units)} \\" ///
            "           \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Saved `outbase'.ster and .tex"

********************************************************************************

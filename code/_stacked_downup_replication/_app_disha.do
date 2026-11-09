********************************************************************************
* DISHA tables at assembly constituency x month-year: the paper's main table
* (tab:mechanism, tables/action_final_prev_year_count.tex), meeting-document
* topics against downwind rural exposure, and a table of fires on exposure.
*
* Input: action_final.dta, written by _app_disha_generation.do.
*
* This is not an event study: there is no treat indicator and no relative event
* time, so the ymean / moderators_list template the other analysis dofiles
* follow does not apply. What does carry over is the post-estimation wiring --
* numeric quantities go in with estadd scalar, string tags with estadd local,
* and the sample tag is smpl rather than the reserved name sample.
*
* zscore and unique were user-written commands; both have been replaced with
* base Stata so the chain runs on a bare install.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for the five sbatch-array parameters. The DISHA
    * tables are a single specification, so fe_list and ster_suffix are inert
    * here; they stay for consistency with the other analysis dofiles.
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

use "${int_data}/action_final${sample}.dta", clear

rename total_pop_ac_nosmall tot_population

********************************************************************************
* Exposure measures
********************************************************************************

gen pop_share1 = count_downwind_rural_prev_year / tot_population
gen pop_share2 = any_downwind_rural_prev_year / tot_population

* Standardised over the estimation sample, so the coefficient reads per
* standard deviation of exposure among the districts DISHA actually covers.
* Formerly: zscore pop_share`i' if ..., stub(std_)
forvalues i = 1/2 {
    egen std_pop_share`i' = std(pop_share`i') if disha_sample & is_rural != 0
}

********************************************************************************
* Outcomes
********************************************************************************

gen y_agri = (topic_primary_agriculture > 0 & topic_primary_agriculture != .) * 100
gen y_environment = (environment_pollution > 0 & environment_pollution != .) * 100
gen y_development = (topic_primary_development > 0 & topic_primary_development != .) * 100
gen y_election = (topic_primary_election_campaign > 0 & topic_primary_election_campaign != .) * 100
gen y_governance = (topic_primary_governance > 0 & topic_primary_governance != .) * 100
gen y_welfare = (topic_primary_welfare > 0 & topic_primary_welfare != .) * 100

gen n_others = number_docs - environment_pollution - topic_primary_agriculture ///
    - topic_primary_development - topic_primary_election_campaign ///
    - topic_primary_governance - topic_primary_welfare
gen y_others = (n_others > 0 & n_others != .) * 100

* Documents are sparse month to month, so each outcome is also carried at the
* quarter: one document anywhere in the quarter marks the whole quarter.
foreach y of varlist environment_pollution n_others {
    bysort ac_uq_id qtr: egen `y'_qtr = max(`y')
}
foreach y of varlist y_environment y_agri y_development y_election ///
        y_governance y_welfare y_others {
    bysort ac_uq_id qtr: egen `y'_qtr = max(`y')
}

* Environment relative to the average of the other topics: positive means the
* quarter leaned toward environment at their expense.
capture drop substitution_qtr
gen substitution_qtr = y_environment_qtr - ///
    (y_agri_qtr + y_development_qtr + y_election_qtr + y_governance_qtr + ///
     y_welfare_qtr + y_others_qtr) / 6
replace substitution_qtr = 0 if substitution_qtr == .

gen countk = count * 1000
replace count_prev_year = count_prev_year * 1000

local fcond "disha_sample == 1 & is_rural != 0"

capture drop tag_ac
egen byte tag_ac = tag(ac_uq_id) if `fcond'
quietly count if tag_ac == 1
local numacs = r(N)

********************************************************************************
* Fires on exposure (disha_final_fires.tex; not the paper's
* action_final_prev_year_count_fire.tex)
********************************************************************************

est clear

quietly summarize countk if `fcond'
local ymean = r(mean)

reghdfe countk std_pop_share2 if `fcond', ///
    absorb(ac_uq_id monthyear) cluster(ac_uq_id)
estadd scalar ymean = `ymean'
estadd scalar acq = `numacs'
estadd local acfe "Y"
estadd local acmonthfe "Y"
estadd local smpl "Rural, DISHA"
est store fires1

reghdfe countk std_pop_share2 count_prev_year if `fcond', ///
    absorb(ac_uq_id monthyear) cluster(ac_uq_id)
estadd scalar ymean = `ymean'
estadd scalar acq = `numacs'
estadd local acfe "Y"
estadd local acmonthfe "Y"
estadd local smpl "Rural, DISHA"
est store fires2

esttab fires1 fires2 ///
    using "${tables}/disha_final_fires${sample}.tex", replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    nocons nobaselevels ///
    varlabels(std_pop_share2 "Exposure" ///
              count_prev_year "Number of Fires\$_{t-12}\$") ///
    stats(N acq acfe acmonthfe ymean, ///
          fmt(%12.0fc %12.0fc %s %s %9.3f) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "AC FE" "Month-Year FE" "Mean DV")) ///
    mtitles("No Controls" "Controlling for Fires\$_{t-12}\$") ///
    collabels(none) booktabs

********************************************************************************
* Main table (tab:mechanism): meeting-document topics
********************************************************************************

est clear

* Exposure is the fire-count measure std_pop_share1 and every outcome is
* quarterly, in the paper's column order. The court-case column was dropped.
local outcomes substitution_qtr y_environment_qtr y_agri_qtr y_development_qtr ///
    y_election_qtr y_governance_qtr y_welfare_qtr y_others_qtr
local names ""

local i = 1
foreach var of local outcomes {

    quietly summarize `var' if `fcond'
    local ymean = r(mean)

    reghdfe `var' std_pop_share1 if `fcond', ///
        absorb(ac_uq_id monthyear) cluster(ac_uq_id)
    estadd scalar ymean = `ymean'
    estadd scalar acq = `numacs'
    estadd local acfe "Y"
    estadd local acmonthfe "Y"
    estadd local smpl "Rural, DISHA"
    est store topic`i'
    local names "`names' topic`i'"

    local i = `i' + 1
}

* Rows and headers follow the paper's table; a3 keeps the three significant
* digits it reports.
esttab `names' ///
    using "${tables}/action_final_prev_year_count${sample}.tex", replace ///
    cells(b(fmt(a3) star) se(par fmt(a3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(std_pop_share1) nocons nobaselevels ///
    varlabels(std_pop_share1 "Exposure") ///
    stats(N acfe acmonthfe ymean, ///
          fmt(%12.0fc %s %s %9.3f) ///
          labels("Observations" "AC FE" "Month-Year FE" "Mean DV")) ///
    mtitles("\makecell{\textbf{Substitution} \\ \textbf{toward environment}}" ///
            "\textbf{Environment}" "\textbf{Agriculture}" "\textbf{Development}" ///
            "\textbf{Election}" "\textbf{Governance}" "\textbf{Welfare}" ///
            "\textbf{Other Topics}") ///
    mgroups("\textbf{DISHA documents on:}", pattern(1 0 0 0 0 0 0 0) ///
            prefix(\multicolumn{@span}{c}{) suffix(}) ///
            span erepeat(\cmidrule(lr){@span})) ///
    collabels(none) booktabs nonotes

display as result "Generated: ${tables}/disha_final_fires${sample}.tex"
display as result "Generated: ${tables}/action_final_prev_year_count${sample}.tex"

********************************************************************************

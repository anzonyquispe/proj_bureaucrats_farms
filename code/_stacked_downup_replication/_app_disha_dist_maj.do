********************************************************************************
* Heterogeneity of Table B.10 (tab:app_mechanism, tables/action_final_prev_year)
* by whether one party holds at least half of the district's ACs.
*
* Input: action_final.dta, written by _app_disha_generation.do, and
* dist_maj_party.dta, written by _app_dist_maj_party_generation.do.
*
* B.10 regresses the quarterly DISHA outcomes of the paper's main table on
* Exposure std_pop_share2 (whether any fire was recorded downwind in the same
* month a year earlier), with AC and month-year FE, clustered by AC. Its column
* 9 (court cases) was dropped, as everywhere else. Here, for each outcome Y:
*     Y = b1 Exposure + b2 Exposure x Majority + b3 Majority
*         + AC FE + month-year FE,
* where Majority = dist_maj_party in the term in force that month. It changes
* within an AC at elections, so b3 survives the AC fixed effect. As the team
* asked, the table only adds the interaction to B.10.
*
* Output (tables/): action_final_prev_year_dist_maj${sample}.tex. The paper's
* B.10 is not rewritten; the log prints it as a check.
*
* Like _app_disha.do this is not an event study: there is no treat indicator
* and no relative event time, so the ymean / moderators_list template does not
* apply. Numeric quantities go in with estadd scalar, string tags with estadd
* local, and the sample tag is smpl rather than the reserved name sample.
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
* Exposure and outcomes, built exactly as in _app_disha.do
********************************************************************************

gen pop_share2 = any_downwind_rural_prev_year / tot_population
* Formerly: zscore pop_share2 if ..., stub(std_)
egen std_pop_share2 = std(pop_share2) if disha_sample & is_rural != 0

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

* One document anywhere in the quarter marks the whole quarter.
foreach y of varlist y_environment y_agri y_development y_election ///
        y_governance y_welfare y_others {
    bysort ac_uq_id qtr: egen `y'_qtr = max(`y')
}

capture drop substitution_qtr
gen substitution_qtr = y_environment_qtr - ///
    (y_agri_qtr + y_development_qtr + y_election_qtr + y_governance_qtr + ///
     y_welfare_qtr + y_others_qtr) / 6
replace substitution_qtr = 0 if substitution_qtr == .

********************************************************************************
* District majority in the term in force
********************************************************************************

do "${code}/_app_disha_election_calendar.do"

merge m:1 ac_uq_id year_el using "${int_data}/dist_maj_party${sample}.dta", ///
    keepusing(dist_maj_party n_acs top_share) keep(master match)

local fcond "disha_sample == 1 & is_rural != 0"

* Every AC of action_final.dta is in the crosswalk, so no estimation row may
* be left without the indicator.
quietly count if `fcond' & _merge != 3
if r(N) > 0 {
    display as error "Estimation-sample AC-months without dist_maj_party: " r(N)
    exit 459
}
drop _merge

display as text _n "dist_maj_party in the estimation sample (AC-months):"
tab dist_maj_party if `fcond'

capture drop tag_ac
egen byte tag_ac = tag(ac_uq_id) if `fcond'
quietly count if tag_ac == 1
local numacs = r(N)

* The quarterly outcomes of the paper's table, in its column order.
local outcomes substitution_qtr y_environment_qtr y_agri_qtr y_development_qtr ///
    y_election_qtr y_governance_qtr y_welfare_qtr y_others_qtr

local titles `""\shortstack{Substitution toward\\environment}" "Environment" "Agriculture" "Development" "Election" "Governance" "Welfare" "Other Topics""'

********************************************************************************
* Check: without the interaction, columns 1-8 of tab:app_mechanism
********************************************************************************

est clear
local names ""
local i = 1
foreach var of local outcomes {
    quietly reghdfe `var' std_pop_share2 if `fcond', ///
        absorb(ac_uq_id monthyear) cluster(ac_uq_id)
    est store base`i'
    local names "`names' base`i'"
    local i = `i' + 1
}

display as text _n "Without interaction; the paper's tab:app_mechanism reports " ///
    "0.123* (0.0660) and 0.110* (0.0596) in columns 1 and 2."
esttab `names', keep(std_pop_share2) b(4) se(4) ///
    star(* 0.10 ** 0.05 *** 0.01) stats(N) mtitles(`titles') nonotes

********************************************************************************
* Exposure x district majority
********************************************************************************

est clear

local names ""
local i = 1
foreach var of local outcomes {

    quietly summarize `var' if `fcond'
    local ymean = r(mean)

    reghdfe `var' c.std_pop_share2##c.dist_maj_party if `fcond', ///
        absorb(ac_uq_id monthyear) cluster(ac_uq_id)

    estadd scalar ymean = `ymean'
    estadd scalar acq = `numacs'
    estadd local acfe "Y"
    estadd local acmonthfe "Y"
    estadd local smpl "Rural, DISHA"
    estadd local mod "dist_maj_party"
    est store distmaj`i'
    local names "`names' distmaj`i'"

    local i = `i' + 1
}

esttab `names' ///
    using "${tables}/action_final_prev_year_dist_maj${sample}.tex", replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(std_pop_share2 c.std_pop_share2#c.dist_maj_party dist_maj_party) ///
    order(std_pop_share2 c.std_pop_share2#c.dist_maj_party dist_maj_party) ///
    varlabels(std_pop_share2 "Exposure" ///
              c.std_pop_share2#c.dist_maj_party "Exposure \$\times\$ Majority Party" ///
              dist_maj_party "Majority Party") ///
    stats(N acq acfe acmonthfe ymean, ///
          fmt(%12.0fc %12.0fc %s %s %9.3f) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "AC FE" "Month-Year FE" "Mean DV")) ///
    mtitles(`titles') ///
    mgroups("DISHA documents on:", pattern(1 0 0 0 0 0 0 0) ///
            prefix(\multicolumn{@span}{c}{) suffix(}) ///
            span erepeat(\cmidrule(lr){@span})) ///
    nocons nobaselevels collabels(none) booktabs

display as text _n "Exposure x dist_maj_party:"
esttab `names', keep(std_pop_share2 c.std_pop_share2#c.dist_maj_party dist_maj_party) ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N acq) mtitles(`titles') nonotes

display as result "Generated: ${tables}/action_final_prev_year_dist_maj${sample}.tex"

********************************************************************************

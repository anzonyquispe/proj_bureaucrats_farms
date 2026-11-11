********************************************************************************
* Main DISHA table (tab:mechanism) with standard errors clustered by AC (as in
* the paper), AC x month-year and district x month-year. Sample, Exposure,
* outcomes and FE are those of _app_disha.do, so only the standard errors
* change.
*
* Input:  action_final.dta (_app_disha_generation.do).
* Output: tables/action_final_prev_year_count_cluster${sample}.tex, one panel
*         per clustering.
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

gen pop_share1 = count_downwind_rural_prev_year / tot_population
* Formerly: zscore pop_share1 if ..., stub(std_)
egen std_pop_share1 = std(pop_share1) if disha_sample & is_rural != 0

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

local fcond "disha_sample == 1 & is_rural != 0"

* A row without a district would leave the district clustering with a smaller
* sample than the paper's.
assert !missing(distr_id) if `fcond'

capture drop tag_ac
egen byte tag_ac = tag(ac_uq_id) if `fcond'
quietly count if tag_ac == 1
local numacs = r(N)

* The quarterly outcomes of the paper's table, in its column order.
local outcomes substitution_qtr y_environment_qtr y_agri_qtr y_development_qtr ///
    y_election_qtr y_governance_qtr y_welfare_qtr y_others_qtr

********************************************************************************
* tab:mechanism under each clustering
********************************************************************************

est clear

local cl_ac     "ac_uq_id"
local cl_acmy   "ac_uq_id#monthyear"
local cl_distmy "distr_id#monthyear"

foreach cl in ac acmy distmy {
    local names_`cl' ""
    local i = 1
    foreach var of local outcomes {

        quietly summarize `var' if `fcond'
        local ymean = r(mean)

        reghdfe `var' std_pop_share1 if `fcond', ///
            absorb(ac_uq_id monthyear) cluster(`cl_`cl'')
        estadd scalar ymean = `ymean'
        estadd scalar acq = `numacs'
        estadd local acfe "Y"
        estadd local acmonthfe "Y"
        estadd local smpl "Rural, DISHA"
        estadd local clusterspec "`cl'"
        est store `cl'`i'
        local names_`cl' "`names_`cl'' `cl'`i'"

        local i = `i' + 1
    }
}

display as text _n "Paper's clustering; tab:mechanism reports 0.0713* (0.0416) " ///
    "and 0.0718** (0.0314) in columns 1 and 2."
esttab `names_ac', keep(std_pop_share1) b(4) se(4) ///
    star(* 0.10 ** 0.05 *** 0.01) stats(N N_clust) nonotes

********************************************************************************
* Table: one panel per clustering, then the paper's bottom rows
********************************************************************************

local out "${tables}/action_final_prev_year_count_cluster${sample}.tex"
local ncols = 9

local panel_ac     "Panel A: clustered by constituency, as in the paper"
local panel_acmy   "Panel B: clustered by constituency \$\times\$ month-year"
local panel_distmy "Panel C: clustered by district \$\times\$ month-year"

* Header and Panel A, with the paper's column titles.
esttab `names_ac' using "`out'", replace ///
    cells(b(fmt(a3) star) se(par fmt(a3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(std_pop_share1) nocons nobaselevels ///
    varlabels(std_pop_share1 "Exposure") ///
    stats(N_clust, fmt(%12.0fc) labels("Clusters")) ///
    mtitles("\makecell{\textbf{Substitution} \\ \textbf{toward environment}}" ///
            "\textbf{Environment}" "\textbf{Agriculture}" "\textbf{Development}" ///
            "\textbf{Election}" "\textbf{Governance}" "\textbf{Welfare}" ///
            "\textbf{Other Topics}") ///
    mgroups("\textbf{DISHA documents on:}", pattern(1 0 0 0 0 0 0 0) ///
            prefix(\multicolumn{@span}{c}{) suffix(}) ///
            span erepeat(\cmidrule(lr){@span})) ///
    posthead("\midrule" "\multicolumn{`ncols'}{l}{\textit{`panel_ac'}} \\") ///
    prefoot("") postfoot("\midrule") ///
    collabels(none) booktabs nonotes

foreach cl in acmy distmy {
    esttab `names_`cl'' using "`out'", append ///
        cells(b(fmt(a3) star) se(par fmt(a3))) ///
        star(* 0.10 ** 0.05 *** 0.01) ///
        keep(std_pop_share1) nocons nobaselevels ///
        varlabels(std_pop_share1 "Exposure") ///
        stats(N_clust, fmt(%12.0fc) labels("Clusters")) ///
        nomtitles nonumbers ///
        prehead("") ///
        posthead("\multicolumn{`ncols'}{l}{\textit{`panel_`cl''}} \\") ///
        prefoot("") postfoot("\midrule") ///
        collabels(none) booktabs nonotes
}

* The paper's bottom rows, common to the three panels.
esttab `names_ac' using "`out'", append ///
    cells(none) ///
    stats(N acfe acmonthfe ymean, ///
          fmt(%12.0fc %s %s %9.3f) ///
          labels("Observations" "AC FE" "Month-Year FE" "Mean DV")) ///
    nomtitles nonumbers ///
    prehead("") posthead("") prefoot("") ///
    collabels(none) booktabs nonotes

display as result "Generated: `out'"

********************************************************************************

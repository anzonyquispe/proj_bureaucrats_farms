********************************************************************************
* DISHA main table (tab:mechanism, columns 1-8) with Exposure interacted with
* the share of the district's other MLAs who share this AC's MLA's party or
* alliance.
*
* Input: action_final.dta, written by _app_disha_generation.do, and the
* candidate file read by _app_disha_party_share.do.
*
* For each DISHA outcome Y and each share S:
*     Y = b1 Exposure + b2 Exposure x S + b3 S + AC FE + month-year FE,
* clustered by AC. Exposure is std_pop_share1, the count-weighted measure of
* the paper's main table. S changes within an AC at each election, so its own
* term survives the AC fixed effect. b1 is the effect of Exposure when no
* other MLA of the district shares the party; b1 + b2 when all of them do.
*
* Four shares, one table each: party or alliance, counted over all ACs of the
* district or over the rural ones only (see _app_disha_party_share.do).
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

********************************************************************************
* Sitting MLA's party and the co-partisan shares
********************************************************************************

do "${code}/_app_disha_election_calendar.do"
do "${code}/_app_disha_party_share.do"

local fcond "disha_sample == 1 & is_rural != 0"

* The quarterly outcomes of the paper's main table, in its column order.
local outcomes substitution_qtr y_environment_qtr y_agri_qtr y_development_qtr ///
    y_election_qtr y_governance_qtr y_welfare_qtr y_others_qtr

local titles `""\shortstack{Substitution toward\\environment}" "Environment" "Agriculture" "Development" "Election" "Governance" "Welfare" "Other Topics""'

********************************************************************************
* Check: without the interaction, columns 1-8 of tab:mechanism
********************************************************************************

est clear
local names ""
local i = 1
foreach var of local outcomes {
    quietly reghdfe `var' std_pop_share1 if `fcond', ///
        absorb(ac_uq_id monthyear) cluster(ac_uq_id)
    est store base`i'
    local names "`names' base`i'"
    local i = `i' + 1
}

display as text _n "Without interaction; the paper's tab:mechanism reports " ///
    "0.0713 (0.0416) and 0.0718 (0.0314) in columns 1 and 2."
esttab `names', keep(std_pop_share1) b(4) se(4) ///
    star(* 0.10 ** 0.05 *** 0.01) stats(N) mtitles(`titles') nonotes

********************************************************************************
* Exposure x co-partisan share
********************************************************************************

local shares copart_party_all copart_party_rural ///
    copart_alliance_all copart_alliance_rural

foreach s of local shares {

    est clear

    local mcond "`fcond' & !missing(`s')"

    capture drop tag_ac
    egen byte tag_ac = tag(ac_uq_id) if `mcond'
    quietly count if tag_ac == 1
    local numacs = r(N)

    quietly summarize `s' if `mcond'
    local smean = r(mean)

    local names ""
    local i = 1
    foreach var of local outcomes {

        quietly summarize `var' if `mcond'
        local ymean = r(mean)

        reghdfe `var' c.std_pop_share1##c.`s' if `mcond', ///
            absorb(ac_uq_id monthyear) cluster(ac_uq_id)

        * Effect of Exposure when every other MLA of the district shares it.
        lincom _b[std_pop_share1] + _b[c.std_pop_share1#c.`s']
        local b_full = r(estimate)
        local se_full = r(se)
        local p_full = r(p)
        local stars = cond(`p_full' < 0.01, "***", ///
            cond(`p_full' < 0.05, "**", cond(`p_full' < 0.10, "*", "")))
        local b_full_str : display %9.3f `b_full'
        local se_full_str : display %9.3f `se_full'
        local b_full_str = strtrim("`b_full_str'")
        local se_full_str = strtrim("`se_full_str'")

        estadd scalar b_full = `b_full'
        estadd scalar se_full = `se_full'
        estadd scalar p_full = `p_full'
        estadd local b_full_str "`b_full_str'`stars'"
        estadd local se_full_str "(`se_full_str')"

        estadd scalar ymean = `ymean'
        estadd scalar smean = `smean'
        estadd scalar acq = `numacs'
        estadd local acfe "Y"
        estadd local acmonthfe "Y"
        estadd local smpl "Rural, DISHA"
        estadd local mod "`s'"
        est store copart`i'
        local names "`names' copart`i'"

        local i = `i' + 1
    }

    esttab `names' ///
        using "${tables}/disha_`s'${sample}.tex", replace ///
        cells(b(fmt(3) star) se(par fmt(3))) ///
        star(* 0.10 ** 0.05 *** 0.01) ///
        keep(std_pop_share1 c.std_pop_share1#c.`s' `s') ///
        order(std_pop_share1 c.std_pop_share1#c.`s' `s') ///
        varlabels(std_pop_share1 "Exposure" ///
                  c.std_pop_share1#c.`s' "Exposure \$\times\$ Share" ///
                  `s' "Share") ///
        stats(b_full_str se_full_str N acq acfe acmonthfe ymean smean, ///
              fmt(%s %s %12.0fc %12.0fc %s %s %9.3f %9.3f) ///
              labels("Exposure + Exposure \$\times\$ Share" " " ///
                     "Observations" "N Assembly Constituencies" ///
                     "AC FE" "Month-Year FE" "Mean DV" "Mean Share")) ///
        mtitles(`titles') ///
        mgroups("DISHA documents on:", pattern(1 0 0 0 0 0 0 0) ///
                prefix(\multicolumn{@span}{c}{) suffix(}) ///
                span erepeat(\cmidrule(lr){@span})) ///
        nocons nobaselevels collabels(none) booktabs

    display as text _n "Share: `s'"
    esttab `names', keep(std_pop_share1 c.std_pop_share1#c.`s' `s') ///
        b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
        stats(b_full_str se_full_str N acq smean) mtitles(`titles') nonotes

    display as result "Generated: ${tables}/disha_`s'${sample}.tex"
}

********************************************************************************

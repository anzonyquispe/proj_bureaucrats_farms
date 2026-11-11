********************************************************************************
* DISHA main table (tab:mechanism) with Exposure interacted with each measure
* of _disha_fragmentation.do: Y = b1 Exposure + b2 Exposure x M + b3 M,
* AC and month-year FE, clustered by AC.
*
* Measures (u = all|rural):
*   enp1_<party|alliance>_<u>    b1 at ENP = 1, b1 + b2 at ENP = 2.
*   ruling_<u>, ruling_ext_<u>   b1 when the government holds no AC, b1 + b2
*                                when it holds all.
*
* Output (tables/): disha_enp_*, disha_ruling_* and disha_ruling_ext_*.tex.
* Not an event study, so the ymean / moderators template does not apply.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults; fe_list and ster_suffix are unused here.
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

********************************************************************************
* Sitting MLA's party and the fragmentation measures
********************************************************************************

do "${code}/_app_disha_election_calendar.do"
do "${code}/_app_disha_party_share.do"
do "${code}/_disha_fragmentation.do"

* The quarterly outcomes of the paper's main table, in its column order.
local outcomes substitution_qtr y_environment_qtr y_agri_qtr y_development_qtr ///
    y_election_qtr y_governance_qtr y_welfare_qtr y_others_qtr

local titles `""\shortstack{Substitution toward\\environment}" "Environment" "Agriculture" "Development" "Election" "Governance" "Welfare" "Other Topics""'

********************************************************************************
* Exposure x fragmentation measure
********************************************************************************

* b1 + b2 (Exposure at ENP = 2 or at share = 1) as table strings.
capture program drop disha_full_effect
program define disha_full_effect
    args s
    quietly lincom _b[std_pop_share1] + _b[c.std_pop_share1#c.`s']
    local p = r(p)
    local stars = cond(`p' < 0.01, "***", cond(`p' < 0.05, "**", ///
        cond(`p' < 0.10, "*", "")))
    local b_full_str : display %9.3f r(estimate)
    local se_full_str : display %9.3f r(se)
    local b_full_str = strtrim("`b_full_str'")
    local se_full_str = strtrim("`se_full_str'")
    estadd local b_full_str "`b_full_str'`stars'"
    estadd local se_full_str "(`se_full_str')"
end

foreach s in enp1_party_all enp1_party_rural enp1_alliance_all ///
        enp1_alliance_rural ruling_all ruling_rural ruling_ext_all ///
        ruling_ext_rural {

    * Labels, mean variable and file name.
    if substr("`s'", 1, 4) == "enp1" {
        local lab "(ENP \$-\$ 1)"
        local mainlab "ENP \$-\$ 1"
        local mvar = "enp" + substr("`s'", 5, .)
        local meanlab "Mean ENP"
        local fullab "Exposure at ENP = 2"
        local file = "disha_enp" + substr("`s'", 5, .)
    }
    else {
        local lab = cond(strpos("`s'", "ext"), ///
            "Ruling share with outside support", "Ruling-coalition share")
        local mainlab "`lab'"
        local mvar "`s'"
        local meanlab "Mean share"
        local fullab "Exposure + Exposure \$\times\$ Share"
        local file "disha_`s'"
    }

    est clear

    local mcond "`fcond' & !missing(`s')"

    capture drop tag_ac
    egen byte tag_ac = tag(ac_uq_id) if `mcond'
    quietly count if tag_ac == 1
    local numacs = r(N)

    quietly summarize `mvar' if `mcond'
    local smean = r(mean)

    local names ""
    local i = 1
    foreach var of local outcomes {

        quietly summarize `var' if `mcond'
        local ymean = r(mean)

        reghdfe `var' c.std_pop_share1##c.`s' if `mcond', ///
            absorb(ac_uq_id monthyear) cluster(ac_uq_id)
        disha_full_effect `s'

        estadd scalar ymean = `ymean'
        estadd scalar smean = `smean'
        estadd scalar acq = `numacs'
        estadd local acfe "Y"
        estadd local acmonthfe "Y"
        estadd local smpl "Rural, DISHA"
        estadd local mod "`s'"
        est store frag`i'
        local names "`names' frag`i'"

        local i = `i' + 1
    }

    esttab `names' using "${tables}/`file'${sample}.tex", replace ///
        cells(b(fmt(3) star) se(par fmt(3))) ///
        star(* 0.10 ** 0.05 *** 0.01) ///
        keep(std_pop_share1 c.std_pop_share1#c.`s' `s') ///
        order(std_pop_share1 c.std_pop_share1#c.`s' `s') ///
        varlabels(std_pop_share1 "Exposure" ///
                  c.std_pop_share1#c.`s' "Exposure \$\times\$ `lab'" ///
                  `s' "`mainlab'") ///
        stats(b_full_str se_full_str N acq acfe acmonthfe ymean smean, ///
              fmt(%s %s %12.0fc %12.0fc %s %s %9.3f %9.3f) ///
              labels("`fullab'" " " ///
                     "Observations" "N Assembly Constituencies" ///
                     "AC FE" "Month-Year FE" "Mean DV" "`meanlab'")) ///
        mtitles(`titles') ///
        mgroups("DISHA documents on:", pattern(1 0 0 0 0 0 0 0) ///
                prefix(\multicolumn{@span}{c}{) suffix(}) ///
                span erepeat(\cmidrule(lr){@span})) ///
        nocons nobaselevels collabels(none) booktabs

    display as text _n "Measure: `s'"
    esttab `names', keep(std_pop_share1 c.std_pop_share1#c.`s' `s') ///
        b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
        stats(b_full_str se_full_str N acq smean) mtitles(`titles') nonotes

    display as result "Generated: ${tables}/`file'${sample}.tex"
}

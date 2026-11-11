********************************************************************************
* DISHA main table (tab:mechanism), alone and interacted with ENP, the ruling
* share and the co-partisan share, with SEs clustered by AC (paper), AC x
* month-year and district x month-year. Same sample and FE as _app_disha.do.
*
* Output (tables/), one panel per clustering:
*   action_final_prev_year_count_cluster.tex       tab:mechanism
*   action_final_prev_year_count_<m>_cluster.tex   m = enp, ruling, ruling_ext,
*                                                  copart
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

* District clustering needs a district on every row.
assert !missing(distr_id) if `fcond'

do "${code}/_app_disha_election_calendar.do"
do "${code}/_app_disha_party_share.do"
do "${code}/_disha_fragmentation.do"

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
* Interactions with ENP, the ruling-coalition share and the co-partisan share
* under each clustering
********************************************************************************

* b1 + b2 (Exposure at ENP = 2 or at share = 1) as table strings, with three
* significant digits like the a3 cells.
capture program drop disha_full_effect
program define disha_full_effect
    args s
    quietly lincom _b[std_pop_share1] + _b[c.std_pop_share1#c.`s']
    local p = r(p)
    local stars = cond(`p' < 0.01, "***", cond(`p' < 0.05, "**", ///
        cond(`p' < 0.10, "*", "")))
    foreach k in estimate se {
        local x = r(`k')
        local d = max(3, 2 - floor(log10(abs(`x'))))
        local str_`k' : display %20.`d'f `x'
        local str_`k' = strtrim("`str_`k''")
    }
    if "`stars'" != "" local str_estimate "`str_estimate'\sym{`stars'}"
    estadd local b_full_str "`str_estimate'"
    estadd local se_full_str "(`str_se')"
end

local label_enp1_party_all "(ENP \$-\$ 1)"
local label_ruling_all     "Ruling-coalition share"
local label_copart_party_all "Co-partisan share"
local label_ruling_ext_all "Ruling share with outside support"
local mainlab_enp1_party_all "ENP \$-\$ 1"
local mainlab_ruling_all     "Ruling-coalition share"
local mainlab_copart_party_all "Co-partisan share"
local mainlab_ruling_ext_all "Ruling share with outside support"
local mean_enp1_party_all  "enp_party_all"
local mean_ruling_all      "ruling_all"
local mean_copart_party_all "copart_party_all"
local mean_ruling_ext_all  "ruling_ext_all"
local meanlab_enp1_party_all "Mean ENP"
local meanlab_ruling_all     "Mean ruling-coalition share"
local meanlab_copart_party_all "Mean co-partisan share"
local meanlab_ruling_ext_all "Mean ruling share with outside support"
local file_enp1_party_all  "enp"
local file_ruling_all      "ruling"
local file_copart_party_all "copart"
local file_ruling_ext_all  "ruling_ext"

foreach s in enp1_party_all ruling_all ruling_ext_all copart_party_all {

    est clear

    local mcond "`fcond' & !missing(`s')"
    local lab "`label_`s''"
    local mainlab "`mainlab_`s''"

    capture drop tag_ac
    egen byte tag_ac = tag(ac_uq_id) if `mcond'
    quietly count if tag_ac == 1
    local numacs_s = r(N)

    quietly summarize `mean_`s'' if `mcond'
    local smean = r(mean)

    foreach cl in ac acmy distmy {
        local names_`cl' ""
        local i = 1
        foreach var of local outcomes {

            quietly summarize `var' if `mcond'
            local ymean = r(mean)

            reghdfe `var' c.std_pop_share1##c.`s' if `mcond', ///
                absorb(ac_uq_id monthyear) cluster(`cl_`cl'')
            disha_full_effect `s'
            estadd scalar ymean = `ymean'
            estadd scalar smean = `smean'
            estadd scalar acq = `numacs_s'
            estadd local acfe "Y"
            estadd local acmonthfe "Y"
            estadd local smpl "Rural, DISHA"
            estadd local mod "`s'"
            estadd local clusterspec "`cl'"
            est store `cl'`i'
            local names_`cl' "`names_`cl'' `cl'`i'"

            local i = `i' + 1
        }
    }

    display as text _n "Exposure x `s', clustered by AC:"
    esttab `names_ac', keep(std_pop_share1 c.std_pop_share1#c.`s' `s') ///
        b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
        stats(b_full_str se_full_str N N_clust) nonotes

    local out "${tables}/action_final_prev_year_count_`file_`s''_cluster${sample}.tex"

    * Header and Panel A, with the paper's column titles.
    esttab `names_ac' using "`out'", replace ///
        cells(b(fmt(a3) star) se(par fmt(a3))) ///
        star(* 0.10 ** 0.05 *** 0.01) ///
        keep(std_pop_share1 c.std_pop_share1#c.`s' `s') ///
        order(std_pop_share1 c.std_pop_share1#c.`s' `s') ///
        nocons nobaselevels ///
        varlabels(std_pop_share1 "Exposure" ///
                  c.std_pop_share1#c.`s' "Exposure \$\times\$ `lab'" ///
                  `s' "`mainlab'") ///
        stats(b_full_str se_full_str N_clust, fmt(%s %s %12.0fc) ///
              labels("Exposure + Exposure \$\times\$ `lab'" " " "Clusters")) ///
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
            keep(std_pop_share1 c.std_pop_share1#c.`s' `s') ///
            order(std_pop_share1 c.std_pop_share1#c.`s' `s') ///
            nocons nobaselevels ///
            varlabels(std_pop_share1 "Exposure" ///
                      c.std_pop_share1#c.`s' "Exposure \$\times\$ `lab'" ///
                      `s' "`mainlab'") ///
            stats(b_full_str se_full_str N_clust, fmt(%s %s %12.0fc) ///
                  labels("Exposure + Exposure \$\times\$ `lab'" " " "Clusters")) ///
            nomtitles nonumbers ///
            prehead("") ///
            posthead("\multicolumn{`ncols'}{l}{\textit{`panel_`cl''}} \\") ///
            prefoot("") postfoot("\midrule") ///
            collabels(none) booktabs nonotes
    }

    * Bottom rows, common to the panels.
    esttab `names_ac' using "`out'", append ///
        cells(none) ///
        stats(N acfe acmonthfe ymean smean, ///
              fmt(%12.0fc %s %s %9.3f %9.3f) ///
              labels("Observations" "AC FE" "Month-Year FE" "Mean DV" ///
                     "`meanlab_`s''")) ///
        nomtitles nonumbers ///
        prehead("") posthead("") prefoot("") ///
        collabels(none) booktabs nonotes

    display as result "Generated: `out'"
}

********************************************************************************

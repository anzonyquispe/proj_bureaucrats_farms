********************************************************************************
* Districts, the ACs inside each one, how many of them each party holds, and
* whether one party holds at least half of them (dist_maj_party). Input of
* the district-majority heterogeneity exercise on Figure 3 (_app_23), Table
* B.3 (_app_24) and Table B.10 (_app_disha_dist_maj.do).
*
* Districts and ACs follow the DISHA analysis: an AC belongs to the district
* it lies in, and ACs spanning several districts are left out, because
* action_final.dta keeps split == 1 only (see _app_disha_generation.do). Every
* remaining AC of the district counts, urban ones included.
*
* The party of an AC in a term is its MLA's: the winner (position 1) of that
* election, with the labels cleaned in _app_disha_party_share.do. Each
* independent is a party of one.
*
* dist_maj_party = 1 when one party holds at least half of the district's ACs
* in that term, ties at exactly 50% included, and 0 otherwise. A district with
* one or two ACs is therefore always 1. top_share keeps the largest party's
* share, so a stricter threshold can be applied later.
*
* Outputs (data_output/intermediate):
*   dist_maj_party${sample}.dta/.csv: one row per AC x term (ac_uq_id,
*       year_el), with the district, the MLA's party, the counts and
*       dist_maj_party; the fire and DISHA panels merge it on ac_uq_id year_el.
*   district_party_acs${sample}.csv: one row per district x term x party,
*       with that party's number and share of the district's ACs.
*
* Runs where action_final.dta lives (the team's Dropbox); the cluster jobs
* only need the .dta copied into its data_output/intermediate.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for the five sbatch-array parameters. This is a data
    * build, so is_rural_var, fe_list and ster_suffix are inert here; they stay
    * for consistency with the other dofiles.
    global location     "dbox"
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

use "${int_data}/action_final${sample}.dta", clear

********************************************************************************
* 1. AC x term crosswalk with the MLA's party
********************************************************************************

do "${code}/_app_disha_election_calendar.do"
do "${code}/_app_disha_party_share.do"

keep if !missing(year_el) & !missing(distr_id)
collapse (firstnm) mla_party district, by(ac_uq_id distr_id province year_el)
isid ac_uq_id year_el

quietly count if mla_party == ""
if r(N) > 0 {
    display as error "AC-terms without a matched MLA: " r(N)
    exit 459
}

* Each independent is a party of one.
egen long _ac = group(ac_uq_id)
gen party_grp = mla_party
replace party_grp = "IND_" + string(_ac) if mla_party == "IND"
drop _ac

********************************************************************************
* 2. ACs per party in each district and term, and the majority indicator
********************************************************************************

bysort distr_id year_el: gen int n_acs = _N
bysort distr_id year_el party_grp: gen int n_acs_party = _N
bysort distr_id year_el: egen int n_acs_top = max(n_acs_party)
gen double top_share = n_acs_top / n_acs
gen byte dist_maj_party = (top_share >= 0.5)

label variable n_acs          "ACs of the district in the term"
label variable n_acs_party    "ACs of the district held by this AC's MLA's party"
label variable n_acs_top      "ACs of the district held by its largest party"
label variable top_share      "Largest party's share of the district's ACs"
label variable dist_maj_party "One party holds at least half of the district's ACs"

egen byte _tag = tag(distr_id year_el)
display as text _n "Districts by province and term (one row per district-term):"
tab province year_el if _tag
display as text _n "Share of district-terms with dist_maj_party == 1:"
tabulate province year_el if _tag, summarize(dist_maj_party) means
quietly count if _tag & top_share == 0.5
display as text "District-terms with a tie at exactly 50%: " r(N)
quietly count if _tag & n_acs <= 2
display as text "District-terms with one or two ACs (always 1): " r(N)
display as text _n "Overall, district-terms:"
tab dist_maj_party if _tag
display as text _n "Overall, AC-terms:"
tab dist_maj_party

* District x term x party counts, for the team to inspect.
preserve
    collapse (first) mla_party district n_acs n_acs_party dist_maj_party, ///
        by(province year_el distr_id party_grp)
    gen double share_acs = n_acs_party / n_acs
    rename mla_party party
    order province year_el distr_id district party party_grp ///
        n_acs_party n_acs share_acs dist_maj_party
    gsort province year_el distr_id -n_acs_party party_grp
    export delimited using "${int_data}/district_party_acs${sample}.csv", replace
restore

drop _tag party_grp
order ac_uq_id year_el province distr_id district mla_party ///
    n_acs n_acs_party n_acs_top top_share dist_maj_party
sort ac_uq_id year_el
compress
save "${int_data}/dist_maj_party${sample}.dta", replace
export delimited using "${int_data}/dist_maj_party${sample}.csv", replace

display as result "Generated: ${int_data}/dist_maj_party${sample}.dta"
display as result "Generated: ${int_data}/district_party_acs${sample}.csv"

********************************************************************************

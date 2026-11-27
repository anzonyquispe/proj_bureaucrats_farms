********************************************************************************
* _app_mech_merge.do
* Adds Air Act court cases, electoral variables and AC protests to the DISHA
* AC-month panel (action_final.dta, written by _app_disha_generation.do). Writes
* one file per protest definition, with the same variable names:
*   action_final_merged_protest2.dta  Gemini-classified protests (Figure 4)
*   action_final_merged_kw.dta        keyword-rule protests ("farm...")
* action_final_merged_kw.dta is the input of _app_mech_tables.do.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone default: data root (shell = cluster, dbox = Dropbox).
    global location "shell"
    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
    if "$location" == "dbox" global root "$dbox"
    else global root "$shell"
}
local int "${root}/data_output/intermediate"
if "$outdir" == "" global outdir "`int'"
* protest2 grid file (Gemini classification), kept in data_output/intermediate.
if "$pr2_file" == "" global pr2_file "`int'/8_grids_ac_pr2_5km.csv"

* action_final.dta stores monthyear as year*12 + month.
local ym_court_end = 2018*12 + 12

* 1. Court cases (SHRUG eCourts, Air Act), district x month, 2012m9-2018m12
* fir_nature.dta sums fir over the district's grid cells (gen_court_cases.do
* collapses with rawsum after an m:1 merge), so fir = cases x grid cells.
use district month year fir FIR tot_grids_distr using "`int'/fir_nature.dta", clear
gen court_cases = fir / tot_grids_distr
gen byte court_any = FIR
keep district month year court_cases court_any
tempfile court
save `court'

* 2. Electoral variables of the sitting MLA, AC x term
* (State, constituency number) -> ac_uq_id, from the IndiaVotes candidate file.
import delimited using "`int'/IV_AC_candidates_ac_identifier.csv", clear varnames(1)
replace state = "Uttar Pradesh" if state == "Uttar_Pradesh"
preserve
    keep state ac_id ac_uq_id
    duplicates drop
    isid state ac_id
    tempfile acmap
    save `acmap'
restore

* Rerunning needs every candidate of the next election, which only the
* IndiaVotes file has, without a person id. Names are matched on a skeleton
* that drops titles, parentage notes and the usual transliteration variants
* (Niraj/Neeraj, Hazari/Hajari, Naveen/Nabin).
capture program drop nameskel
program define nameskel
    args v out
    gen `out' = " " + ustrupper(`v') + " "
    foreach cut in "FATHER" " S/O" " D/O" " W/O" "@" " ALIAS " "(" {
        replace `out' = usubstr(`out', 1, ustrpos(`out', "`cut'") - 1) ///
            if ustrpos(`out', "`cut'") > 1
    }
    replace `out' = ustrregexra(`out', "\bKR\b", "KUMAR")
    replace `out' = ustrregexra(`out', "\b(DR|DOCTOR|SHRI|SMT|ADV|PROF|LATE)\b", " ")
    replace `out' = ustrregexra(`out', "[^A-Z]", "")
    foreach p in "PH F" "SH S" "BH V" "DH D" "TH T" "KH K" "GH G" "CH C" ///
            "JH J" "Z J" "W V" "B V" "Q K" {
        local a : word 1 of `p'
        local b : word 2 of `p'
        replace `out' = subinstr(`out', "`a'", "`b'", .)
    }
    replace `out' = usubstr(`out', 1, 1) + ///
        ustrregexra(usubstr(`out', 2, .), "[AEIOUYH]", "")
    replace `out' = ustrregexra(`out', "(.)\1+", "\$1")
end

nameskel name sk
keep state ac_uq_id election_year position sk
* Next election in the file, by state (Haryana has 2024; the others stop at
* their last election, so the last term has no next election).
gen int next_year = .
replace next_year = election_year + 5 if state == "Bihar" & election_year < 2020
replace next_year = election_year + 5 if state == "Haryana" & election_year < 2024
replace next_year = election_year + 5 if inlist(state, "Punjab", "Uttar Pradesh") & election_year < 2022
preserve
    keep ac_uq_id election_year sk position
    rename (election_year sk position) (next_year sk_next position_next)
    tempfile cands
    save `cands'
restore
keep if position == 1
duplicates drop ac_uq_id election_year, force
joinby ac_uq_id next_year using `cands', unmatched(master)
* Same skeleton, or one is the start of the other (a dropped surname).
gen byte same = sk == sk_next | ///
    (min(ustrlen(sk), ustrlen(sk_next)) >= 4 & ///
     (ustrpos(sk, sk_next) == 1 | ustrpos(sk_next, sk) == 1))
gen byte rerun_name = same if next_year != .
gen byte reelected_name = same & position_next == 1 if next_year != .
collapse (max) rerun_name reelected_name, by(ac_uq_id election_year)
tempfile forward
save `forward'

* Winner of each post-2008 election (TCPD, one row per AC and election).
import delimited using "`int'/election_data_protest.csv", clear varnames(1)
keep if delimid == 4 & poll_no == 0 & position == 1
gen state = subinstr(state_name, "_", " ", .)
rename constituency_no ac_id
merge m:1 state ac_id using `acmap', keep(match) nogen
rename year election_year
merge 1:1 ac_uq_id election_year using `forward', keep(master match) nogen

* Re-election: the next winner of the same AC is the same person, by TCPD's
* person id or by name. Each source misses some re-elections the other finds
* (TCPD splits Sukhjinder Singh Randhawa into two ids). Haryana 2024 is not in
* TCPD, so its 2019 term relies on the names.
bysort ac_uq_id (election_year): gen byte reelected_pid = pid == pid[_n + 1] ///
    if _n < _N
gen byte reelected_next = max(reelected_pid, reelected_name) ///
    if reelected_pid < . | reelected_name < .
gen byte rerun_next = rerun_name
replace rerun_next = 1 if reelected_next == 1
* Manual review of the 85 elections where TCPD ids and names disagree
* (reelection_review.csv): 82 are the same person, these 3 are not.
replace reelected_next = 0 if ac_uq_id == 219 & election_year == 2010  // Sitamarhi: Pintu lost to Sunil Kumar (RJD)
replace reelected_next = 0 if ac_uq_id == 438 & election_year == 2017  // Chamkaur Sahib: Channi lost to Charanjit Singh (AAP)
replace reelected_next = 0 if ac_uq_id == 826 & election_year == 2017  // Sitapur: 2022 winner is another Rakesh Rathore
replace rerun_next = 0 if ac_uq_id == 826 & election_year == 2017      // the 2017 Rakesh Rathore did not run in 2022
* Manual review of the 31 reruns with under 5% of the vote (rerun_review.csv):
* in these 6 the only name match is a namesake; the MLA did not run.
replace rerun_next = 0 if ac_uq_id == 769 & election_year == 2017      // Barkhera: Kishan Lal Rajpoot
replace rerun_next = 0 if ac_uq_id == 375 & election_year == 2012      // Qadian: Charanjit Kaur Bajwa
replace rerun_next = 0 if ac_uq_id == 355 & election_year == 2017      // Jaitu: Baldev Singh
replace rerun_next = 0 if ac_uq_id == 27  & election_year == 2015      // Kahalgaon: Sadanand Singh (his son ran)
replace rerun_next = 0 if ac_uq_id == 28  & election_year == 2015      // Nathnagar: Ajay Kumar Mandal (MP by 2020)
replace rerun_next = 0 if ac_uq_id == 409 & election_year == 2017      // Raikot: Jagga Hissowal ran in Jagraon
rename (party votes vote_share_percentage margin margin_percentage n_cand ///
        turnout_percentage enop no_terms) ///
       (el_party el_votes el_vote_share el_margin el_margin_pct el_n_cand ///
        el_turnout el_enop el_n_terms)
gen byte el_incumbent = incumbent == "True"
gen byte el_turncoat = turncoat == "True"
keep ac_uq_id election_year el_* rerun_next reelected_next
rename election_year year_el
tempfile electoral
save `electoral'

* 3. AC protests from the main analysis's grid treatment
* A grid cell is treated from the month of the first protest within 5 km
* (Section 4.1). An AC is treated from the first month any of its cells is.
use unique_small_grid_id ac_uq_id using "`int'/iv_tmp.dta", clear
duplicates drop
bysort ac_uq_id: gen n_grids_ac = _N
tempfile grid_ac
save `grid_ac'

local file_kw       "`int'/8_grids_ac_pr_5km.csv"
local file_protest2 "$pr2_file"
foreach p in kw protest2 {
    import delimited using "`file_`p''", clear varnames(1)
    rename unq_s__ unique_small_grid_id
    gen monthyear = yr_pr_5km*12 + mt_pr_5km
    keep unique_small_grid_id monthyear
    merge 1:m unique_small_grid_id using `grid_ac', keep(match) nogen
    * Grid cells newly treated in each AC-month.
    collapse (count) new_grids = unique_small_grid_id (first) n_grids_ac, ///
        by(ac_uq_id monthyear)
    tempfile pr_`p'
    save `pr_`p''
}

* 4. Merge onto action_final.dta and save one file per protest definition
foreach p in protest2 kw {
    use "`int'/action_final.dta", clear

    * Court cases: missing after 2018m12, where the court data end.
    merge m:1 district month year using `court', keep(master match) nogen
    replace court_cases = . if monthyear > `ym_court_end'
    replace court_any = . if monthyear > `ym_court_end'

    * Electoral term of each AC-month, same cutoffs as the repo's
    * _app_disha_election_calendar.do (month the assembly took office).
    gen int year_el = .
    foreach y in 2010 2015 2020 {
        replace year_el = `y' if province == "Bihar" & ///
            inrange(monthyear, `y'*12 + 12, (`y' + 5)*12 + 11)
    }
    foreach y in 2009 2014 2019 {
        replace year_el = `y' if province == "Haryana" & ///
            inrange(monthyear, `y'*12 + 11, (`y' + 5)*12 + 10)
    }
    foreach y in 2012 2017 2022 {
        replace year_el = `y' if inlist(province, "Punjab", "Punjab_IND", "Uttar Pradesh") & ///
            inrange(monthyear, `y'*12 + 4, (`y' + 5)*12 + 3)
    }
    merge m:1 ac_uq_id year_el using `electoral', keep(master match) nogen

    * Protest: treated from the first month any grid cell of the AC is treated;
    * protest_share is the share of its cells treated by that month.
    merge 1:1 ac_uq_id monthyear using `pr_`p'', keep(master match) nogen
    replace new_grids = 0 if new_grids == .
    bysort ac_uq_id (monthyear): gen protest_share = sum(new_grids)
    bysort ac_uq_id (n_grids_ac): replace n_grids_ac = n_grids_ac[1]
    replace protest_share = protest_share / n_grids_ac
    replace protest_share = 0 if protest_share == .
    gen byte protest = protest_share > 0
    drop new_grids n_grids_ac

    label variable court_cases    "Air Act court cases in the district-month (missing after 2018m12)"
    label variable court_any      "Any Air Act court case in the district-month"
    label variable year_el        "Election year of the sitting MLA's term"
    label variable el_party       "MLA party (TCPD)"
    label variable el_votes       "MLA votes"
    label variable el_vote_share  "MLA vote share (%)"
    label variable el_margin      "Victory margin (votes)"
    label variable el_margin_pct  "Victory margin (% points)"
    label variable el_n_cand      "Number of candidates"
    label variable el_turnout     "Turnout (%)"
    label variable el_enop        "Effective number of parties (votes)"
    label variable el_n_terms     "MLA's number of terms"
    label variable el_incumbent   "MLA was a sitting MLA when elected (TCPD)"
    label variable el_turncoat    "MLA changed party since the previous election"
    label variable rerun_next     "MLA ran again in this AC at the next election"
    label variable reelected_next "MLA won this AC again at the next election"
    label variable protest        "Farmer protest within 5 km of any AC grid cell, from its first month (`p')"
    label variable protest_share  "Share of AC grid cells with a protest within 5 km so far (`p')"
    label variable self_profession "MLA is an agriculturalist"

    save "$outdir/action_final_merged_`p'.dta", replace
}

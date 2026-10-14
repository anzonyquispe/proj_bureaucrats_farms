********************************************************************************
* Attach the incumbent's vote share and whether their party held the seat.
*
* Creates: incumbent_vote_share, party_won, votes, election_merge.
*
* _app_disha.do and app_disha_desc.do each carried an identical copy of this
* block; it lives here so the two cannot drift apart. The logic is unchanged
* from the original, only the hard-coded path was replaced by ${int_data}.
*
* The winner of election t becomes the incumbent facing election t+1, which is
* why year_el is reassigned to the following election before merging back onto
* the candidate list.
*
* Expects: ac_uq_id, year_el, province in memory, and the election calendar
* already applied.
********************************************************************************

confirm variable ac_uq_id year_el province

preserve
    import delimited using "${int_data}/IV_AC_candidates_ac_identifier.csv", clear

    split election, parse(" ")
    rename election1 province
    rename election2 year_el
    * "Uttar Pradesh 2017" splits into three pieces; the year is the last one.
    replace year_el = election3 if election3 != ""
    drop election3
    replace province = "Uttar Pradesh" if province == "Uttar"
    replace province = "Punjab_IND" if province == "Punjab"
    destring year_el, replace
    rename v4 share
    collapse (rawsum) votes share (firstnm) party, ///
        by(ac_uq_id year_el province name election)

    bysort ac_uq_id election: egen max_vote = max(votes)
    gen byte elected = (votes == max_vote)

    tempfile candidates
    save `candidates'

    * The winner of each election, carried forward as the incumbent at the next.
    keep if elected == 1
    gen incumbent = name
    gen incumbent_party = party
    drop year_el
    gen int year_el = .
    replace year_el = 2015 if election == "Bihar 2010"
    replace year_el = 2020 if election == "Bihar 2015"
    replace year_el = 2014 if election == "Haryana 2009"
    replace year_el = 2019 if election == "Haryana 2014"
    replace year_el = 2017 if election == "Punjab 2012"
    replace year_el = 2022 if election == "Punjab 2017"
    replace year_el = 2017 if election == "Uttar Pradesh 2012"
    replace year_el = 2022 if election == "Uttar Pradesh 2017"
    * The last term of each province has no following election in the data.
    drop if year_el == .

    keep year_el incumbent ac_uq_id province incumbent_party

    merge 1:m year_el ac_uq_id province using `candidates'
    drop _merge

    gen incumbent_vote_share = share if incumbent == name
    gen byte party_won = (incumbent_party == party)

    keep incumbent_vote_share votes ac_uq_id year_el province party_won
    keep if incumbent_vote_share != .

    quietly count
    display as text "Incumbent records matched to a following election: " r(N)

    tempfile incumbents
    save `incumbents'
restore

merge m:1 ac_uq_id year_el province using `incumbents'
* _merge == 2 are the split ACs already dropped from the fire panel.
drop if _merge == 2
gen byte election_merge = (_merge == 3)
drop _merge

********************************************************************************

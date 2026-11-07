********************************************************************************
* Attach the sitting MLA's party and alliance, and how many of the district's
* other MLAs share them.
*
* Creates: mla_party, mla_alliance and, for g in {party, alliance} and
*          u in {all, rural},
*              copart_<g>_<u> = (n - 1) / (N - 1)
*          where N counts the ACs of the district in universe u whose MLA is
*          known and n those whose MLA is in this AC's party (or alliance).
*
* The measure is at the AC level and leaves the AC itself out, as agreed with
* the team: with four ACs split two and two between parties, every AC gets
* 1/3. Averaged over a district it equals the share of MLA pairs from the
* same party.
*
* Universe. action_final.dta already excludes ACs spanning several districts,
* so they are never counted. "all" counts every remaining AC of the district,
* urban ones included; "rural" counts only ACs with a rural grid, the ones
* that enter the estimation sample (is_rural != 0).
*
* Independents never share a party or an alliance, not even with each other.
* A district with a single AC in the universe leaves the measure missing.
*
* Alliances are the pre-poll alliances of each election, fixed for the whole
* term. Realignments during a term are not modelled: JD(U) left the Bihar
* Mahagathbandhan for the NDA in July 2017, SAD left the NDA in September
* 2020, SBSP left the UP NDA in 2019, and the 2019 BJP-JJP coalition in
* Haryana formed after the vote.
*
* Expects: ac_uq_id, distr_id, province, year_el and is_rural in memory, and
* the election calendar already applied.
********************************************************************************

confirm variable ac_uq_id distr_id province year_el is_rural

********************************************************************************
* 1. Winner of each AC-election and their party
********************************************************************************

preserve
    import delimited using "${int_data}/IV_AC_candidates_ac_identifier.csv", clear
    confirm variable ac_uq_id election party votes name

    capture confirm string variable party
    if _rc {
        tostring party, replace
        replace party = "" if party == "."
    }
    replace party = strtrim(party)

    split election, parse(" ")
    rename election1 province
    rename election2 year_el
    * "Uttar Pradesh 2017" splits into three pieces; the year is the last one.
    replace year_el = election3 if election3 != ""
    drop election3
    replace province = "Uttar Pradesh" if province == "Uttar"
    replace province = "Punjab_IND" if province == "Punjab"
    destring year_el, replace

    * A candidate listed twice under different labels makes firstnm arbitrary.
    bysort ac_uq_id election name (party): gen byte _conflict = party[1] != party[_N]
    quietly count if _conflict
    display as text "Candidate rows with conflicting party labels: " r(N)
    drop _conflict

    * Same winner rule as _app_disha_incumbents.do.
    collapse (rawsum) votes (firstnm) party, ///
        by(ac_uq_id year_el province name election)
    bysort ac_uq_id election: egen max_vote = max(votes)
    keep if votes == max_vote

    bysort ac_uq_id province year_el: gen int _winners = _N
    quietly count if _winners > 1
    display as text "Winner rows in tied AC-elections: " r(N)
    * A tie between two parties leaves the seat without a party.
    bysort ac_uq_id province year_el (party): ///
        replace party = "" if party[1] != party[_N]
    bysort ac_uq_id province year_el: keep if _n == 1
    drop _winners

    * Party key: upper case without punctuation or spaces, so JD(U), JD (U)
    * and JDU coincide; then full names and variants map to one abbreviation.
    gen mla_party = ustrupper(ustrregexra(party, "[^A-Za-z0-9]", ""))
    replace mla_party = "IND"    if mla_party == "INDEPENDENT"
    replace mla_party = "BJP"    if mla_party == "BHARATIYAJANATAPARTY"
    replace mla_party = "INC"    if inlist(mla_party, "INDIANNATIONALCONGRESS", "CONGRESS")
    replace mla_party = "SAD"    if mla_party == "SHIROMANIAKALIDAL"
    replace mla_party = "BSP"    if mla_party == "BAHUJANSAMAJPARTY"
    replace mla_party = "SP"     if mla_party == "SAMAJWADIPARTY"
    replace mla_party = "RJD"    if mla_party == "RASHTRIYAJANATADAL"
    replace mla_party = "JDU"    if mla_party == "JANATADALUNITED"
    replace mla_party = "INLD"   if mla_party == "INDIANNATIONALLOKDAL"
    replace mla_party = "AAP"    if mla_party == "AAMAADMIPARTY"
    replace mla_party = "LJP"    if mla_party == "LOKJANSHAKTIPARTY"
    replace mla_party = "JJP"    if mla_party == "JANNAYAKJANATAPARTY"
    replace mla_party = "HJCBL"  if inlist(mla_party, "HJC", "HARYANAJANHITCONGRESSBL")
    replace mla_party = "RLD"    if mla_party == "RASHTRIYALOKDAL"
    replace mla_party = "ADS"    if inlist(mla_party, "ADALS", "APNADALS", "APNADALSONEYLAL")
    replace mla_party = "SBSP"   if mla_party == "SUHELDEVBHARATIYASAMAJPARTY"
    replace mla_party = "NISHAD" if inlist(mla_party, "NISHADPARTY", "NIRBALINDIANSHOSHITHAMARAAAMDAL")
    replace mla_party = "HAMS"   if inlist(mla_party, "HAM", "HINDUSTANIAWAMMORCHASECULAR")
    replace mla_party = "VIP"    if inlist(mla_party, "VSIP", "VIKASSHEELINSAANPARTY")
    replace mla_party = "RLSP"   if mla_party == "RASHTRIYALOKSAMTAPARTY"
    replace mla_party = "LIP"    if mla_party == "LOKINSAAFPARTY"
    replace mla_party = "PLC"    if mla_party == "PUNJABLOKCONGRESS"
    replace mla_party = "CPM"    if inlist(mla_party, "CPIM", "COMMUNISTPARTYOFINDIAMARXIST")
    replace mla_party = "CPIMLL" if inlist(mla_party, "CPIML", "CPIMLLIBERATION")
    replace mla_party = "CPI"    if mla_party == "COMMUNISTPARTYOFINDIA"
    replace mla_party = "AIMIM"  if mla_party == "ALLINDIAMAJLISEITTEHADULMUSLIMEEN"

    * Pre-poll alliances by election; a party not listed runs on its own.
    gen mla_alliance = mla_party
    replace mla_alliance = "SAD-BJP" if province == "Punjab_IND" & ///
        inlist(year_el, 2012, 2017) & inlist(mla_party, "SAD", "BJP")
    replace mla_alliance = "AAP-LIP" if province == "Punjab_IND" & ///
        year_el == 2017 & inlist(mla_party, "AAP", "LIP")
    replace mla_alliance = "SAD-BSP" if province == "Punjab_IND" & ///
        year_el == 2022 & inlist(mla_party, "SAD", "BSP")
    replace mla_alliance = "BJP-PLC" if province == "Punjab_IND" & ///
        year_el == 2022 & inlist(mla_party, "BJP", "PLC", "SADS")
    replace mla_alliance = "INLD-SAD" if province == "Haryana" & ///
        inlist(year_el, 2009, 2014) & inlist(mla_party, "INLD", "SAD")
    replace mla_alliance = "INC-RLD" if province == "Uttar Pradesh" & ///
        year_el == 2012 & inlist(mla_party, "INC", "RLD")
    replace mla_alliance = "NDA" if province == "Uttar Pradesh" & ///
        year_el == 2017 & inlist(mla_party, "BJP", "ADS", "SBSP")
    replace mla_alliance = "SP-INC" if province == "Uttar Pradesh" & ///
        year_el == 2017 & inlist(mla_party, "SP", "INC")
    replace mla_alliance = "NDA" if province == "Uttar Pradesh" & ///
        year_el == 2022 & inlist(mla_party, "BJP", "ADS", "NISHAD")
    replace mla_alliance = "SP-RLD-SBSP" if province == "Uttar Pradesh" & ///
        year_el == 2022 & inlist(mla_party, "SP", "RLD", "SBSP")
    replace mla_alliance = "NDA" if province == "Bihar" & ///
        year_el == 2010 & inlist(mla_party, "JDU", "BJP")
    replace mla_alliance = "RJD-LJP" if province == "Bihar" & ///
        year_el == 2010 & inlist(mla_party, "RJD", "LJP")
    replace mla_alliance = "MGB" if province == "Bihar" & ///
        year_el == 2015 & inlist(mla_party, "JDU", "RJD", "INC")
    replace mla_alliance = "NDA" if province == "Bihar" & ///
        year_el == 2015 & inlist(mla_party, "BJP", "LJP", "RLSP", "HAMS")
    replace mla_alliance = "NDA" if province == "Bihar" & ///
        year_el == 2020 & inlist(mla_party, "BJP", "JDU", "VIP", "HAMS")
    replace mla_alliance = "MGB" if province == "Bihar" & ///
        year_el == 2020 & inlist(mla_party, "RJD", "INC", "CPIMLL", "CPI", "CPM")
    replace mla_alliance = "GDSF" if province == "Bihar" & ///
        year_el == 2020 & inlist(mla_party, "RLSP", "BSP", "AIMIM")

    display as text _n "Raw party labels of winners that the cleaning changed:"
    gen _pair = party + "  ->  " + mla_party
    tab _pair if party != mla_party
    drop _pair

    display as text _n "Winners by party, province and election year:"
    bysort province: tab mla_party year_el, missing

    display as text _n "Winners in alliances, by province and election year:"
    bysort province: tab mla_alliance year_el if mla_alliance != mla_party

    keep ac_uq_id province year_el party mla_party mla_alliance
    rename party mla_party_raw
    * For the team's review of the cleaning; a write failure only loses this file.
    capture noisily export delimited using ///
        "${int_data}/disha_mla_party${sample}.csv", replace
    drop mla_party_raw

    tempfile mla
    save `mla'
restore

merge m:1 ac_uq_id province year_el using `mla'

display as text _n "AC-elections in the candidate file but not in the panel " ///
    "(ACs spanning several districts, terms outside the panel):"
tab province year_el if _merge == 2
drop if _merge == 2

display as text _n "Estimation-sample AC-months without a matched MLA:"
tab province year_el if _merge == 1 & disha_sample == 1 & is_rural != 0, missing
drop _merge

********************************************************************************
* 2. Co-partisan share among the district's other ACs
********************************************************************************

preserve
    keep if !missing(year_el) & !missing(distr_id)

    * An AC is rural if it has a rural grid in any month of the term.
    gen byte _rural_month = (is_rural != 0 & !missing(is_rural))
    bysort ac_uq_id: egen byte _rural_min = min(_rural_month)
    bysort ac_uq_id: egen byte _rural_max = max(_rural_month)
    quietly count if _rural_min != _rural_max
    display as text _n "AC-months of ACs whose rural status changes over time: " r(N)

    collapse (max) rural = _rural_month ///
        (firstnm) mla_party mla_alliance, ///
        by(ac_uq_id distr_id province year_el)
    isid ac_uq_id year_el

    egen long _ac = group(ac_uq_id)
    gen byte _u_all = 1
    gen byte _u_rural = rural

    foreach g in party alliance {
        * Each independent is a group of one.
        gen _grp = mla_`g'
        replace _grp = "IND" + string(_ac) if mla_party == "IND"

        foreach u in all rural {
            gen byte _in = _u_`u' & _grp != ""
            bysort distr_id year_el: egen _total = total(_in)
            bysort distr_id year_el _grp: egen _same = total(_in)
            gen copart_`g'_`u' = (_same - 1) / (_total - 1) if _in & _total > 1
            label variable copart_`g'_`u' ///
                "Share of other `u' ACs in the district whose MLA shares the `g'"

            if "`g'" == "party" {
                gen n_acs_`u' = _total if _in
                label variable n_acs_`u' "ACs of the district in universe `u' with a known MLA"
            }

            quietly count if _in & _total == 1
            display as text "AC-terms alone in their district (`g', `u'): " r(N)
            drop _in _total _same
        }
        drop _grp
    }

    display as text _n "ACs per district, AC-term level (all, rural):"
    tab n_acs_all
    tab n_acs_rural

    keep ac_uq_id year_el copart_* n_acs_*
    tempfile copart
    save `copart'
restore

merge m:1 ac_uq_id year_el using `copart', nogen keep(master match)

display as text _n "Co-partisan shares in the estimation sample:"
summarize copart_* if disha_sample == 1 & is_rural != 0

********************************************************************************

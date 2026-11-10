********************************************************************************
* Winner of each AC-election in the candidate file, with their party and
* pre-poll alliance.
*
* Leaves in memory one row per AC-election: ac_uq_id, province (Punjab spelled
* Punjab_IND, as in the election calendar), year_el, mla_party and
* mla_alliance. It covers every AC of the four states, including the ACs
* spanning several districts that action_final.dta leaves out.
*
* _app_disha_party_share.do and _app_coalition_generation.do both read it, so
* the party labels are cleaned in one place.
*
* Alliances are the pre-poll alliances of each election, fixed for the whole
* term. Realignments during a term are not modelled: JD(U) left the Bihar
* Mahagathbandhan for the NDA in July 2017, SAD left the NDA in September
* 2020, SBSP left the UP NDA in 2019, and the 2019 BJP-JJP coalition in
* Haryana formed after the vote.
*
* Replaces the data in memory; callers wrap it in preserve/restore.
********************************************************************************

import delimited using "${int_data}/IV_AC_candidates_ac_identifier.csv", clear
confirm variable ac_uq_id election party position

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

* The winner is the candidate in position 1. Summing votes by name, as
* _app_disha_incumbents.do does, merges namesake candidates (82 pairs in
* the file, e.g. an independent with the winner's name) and makes the
* party depend on the sort order; it also changes the winner in Fatehabad,
* Uttar Pradesh 2012.
keep if position == 1
isid ac_uq_id province year_el

* Party key: upper case without punctuation or spaces, then each label the
* winners carry in the file maps to one abbreviation. The file spells BJP
* "Bharatiya Janta Party" and SBSP both "Bharatiya" (2022) and "Bhartiya"
* (2017).
gen mla_party = ustrupper(ustrregexra(party, "[^A-Za-z0-9]", ""))
replace mla_party = "IND"    if mla_party == "INDEPENDENT"
replace mla_party = "BJP"    if inlist(mla_party, "BHARATIYAJANTAPARTY", "BHARATIYAJANATAPARTY")
replace mla_party = "INC"    if mla_party == "INDIANNATIONALCONGRESS"
replace mla_party = "SP"     if mla_party == "SAMAJWADIPARTY"
replace mla_party = "BSP"    if mla_party == "BAHUJANSAMAJPARTY"
replace mla_party = "JDU"    if mla_party == "JANATADALUNITED"
replace mla_party = "RJD"    if mla_party == "RASHTRIYAJANATADAL"
replace mla_party = "AAP"    if mla_party == "AAMAADMIPARTY"
replace mla_party = "SAD"    if mla_party == "SHIROMANIAKALIDAL"
replace mla_party = "INLD"   if mla_party == "INDIANNATIONALLOKDAL"
replace mla_party = "ADS"    if mla_party == "APNADALSONEYLAL"
replace mla_party = "AD"     if mla_party == "APNADAL"
replace mla_party = "RLD"    if mla_party == "RASHTRIYALOKDAL"
replace mla_party = "CPIMLL" if mla_party == "COMMUNISTPARTYOFINDIAMARXISTLENINISTLIBERATION"
replace mla_party = "CPM"    if mla_party == "COMMUNISTPARTYOFINDIAMARXIST"
replace mla_party = "CPI"    if mla_party == "COMMUNISTPARTYOFINDIA"
replace mla_party = "JJP"    if mla_party == "JANNAYAKJANTAPARTY"
replace mla_party = "HJCBL"  if mla_party == "HARYANAJANHITCONGRESSBL"
replace mla_party = "HLP"    if mla_party == "HARYANALOKHITPARTY"
replace mla_party = "NISHAD" if mla_party == "NIRBALINDIANSHOSHITHAMARAAAMDAL"
replace mla_party = "SBSP"   if inlist(mla_party, "SUHELDEVBHARATIYASAMAJPARTY", "SUHELDEVBHARTIYASAMAJPARTY")
replace mla_party = "LJP"    if mla_party == "LOKJANSHAKTIPARTY"
replace mla_party = "AIMIM"  if mla_party == "ALLINDIAMAJLISEITTEHADULMUSLIMEEN"
replace mla_party = "HAMS"   if mla_party == "HINDUSTANIAWAMMORCHASECULAR"
replace mla_party = "VIP"    if mla_party == "VIKASSHEELINSAANPARTY"
replace mla_party = "RLSP"   if mla_party == "RASHTRIYALOKSAMTAPARTY"
replace mla_party = "LIP"    if mla_party == "LOKINSAAFPARTY"
replace mla_party = "JDL"    if mla_party == "JANSATTADALLOKTANTRIK"
replace mla_party = "PECP"   if mla_party == "PEACEPARTY"
replace mla_party = "QED"    if mla_party == "QUAMIEKTADAL"
replace mla_party = "IEMC"   if mla_party == "ITTEHADEMILLAITCOUNCIL"
replace mla_party = "NCP"    if mla_party == "NATIONALISTCONGRESSPARTY"
replace mla_party = "JMM"    if mla_party == "JHARKHANDMUKTIMORCHA"

* Pre-poll alliances by election, listing the members that won seats; a
* party not listed runs on its own.
gen mla_alliance = mla_party
replace mla_alliance = "SAD-BJP" if province == "Punjab_IND" & ///
    inlist(year_el, 2012, 2017) & inlist(mla_party, "SAD", "BJP")
replace mla_alliance = "AAP-LIP" if province == "Punjab_IND" & ///
    year_el == 2017 & inlist(mla_party, "AAP", "LIP")
replace mla_alliance = "SAD-BSP" if province == "Punjab_IND" & ///
    year_el == 2022 & inlist(mla_party, "SAD", "BSP")
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

********************************************************************************

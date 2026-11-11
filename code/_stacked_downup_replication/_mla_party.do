********************************************************************************
* Winner of each AC-election, with party and pre-poll alliance.
*
* Leaves one row per AC-election: ac_uq_id, province (Punjab_IND), year_el,
* mla_party, mla_alliance. Covers every AC of the four states. Shared by
* _app_disha_party_share.do and _app_coalition_generation.do.
*
* Alliances are fixed for the term; realignments are not modelled (e.g. JD(U)
* to the NDA in 2017). Replaces the data; callers use preserve/restore.
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

* Winner = position 1. Summing votes by name would merge namesakes (82 pairs).
keep if position == 1
isid ac_uq_id province year_el

* Party key: upper case, no punctuation; each label maps to one abbreviation.
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

* Pre-poll alliances (members that won seats); unlisted parties run alone.
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
replace mla_alliance = "PECP-AD" if province == "Uttar Pradesh" & ///
    year_el == 2012 & inlist(mla_party, "PECP", "AD")
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
    year_el == 2020 & inlist(mla_party, "BSP", "AIMIM")

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
* For the team's review; a failed write is not fatal.
capture noisily export delimited using ///
    "${int_data}/disha_mla_party${sample}.csv", replace
drop mla_party_raw

********************************************************************************

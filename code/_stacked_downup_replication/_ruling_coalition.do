********************************************************************************
* State ruling coalition by month, and whether the AC's MLA is in it.
*
* Creates: gov_period     state government in office (e.g. "BR2015b").
*          coalition      1 if the MLA's party has ministers or the MLA is an
*                         independent minister; missing if mla_party is.
*          coalition_ext  coalition plus documented outside support.
*
* Dates and sources: docs/ruling_coalition_sources.md. Undocumented support
* counts as 0. Party = the one elected with; defections are not followed.
* The month of a change belongs to the new status. Coded 2012m4-2023m1.
*
* Expects: ac_uq_id province year month year_el mla_party, calendar applied.
********************************************************************************

confirm variable ac_uq_id province year month year_el mla_party
confirm new variable gov_period coalition coalition_ext

gen int _ym = ym(year, month)

gen str8 gov_period = ""
replace gov_period = "PB2012"  if province == "Punjab_IND" & year_el == 2012
replace gov_period = "PB2017"  if province == "Punjab_IND" & year_el == 2017
replace gov_period = "PB2022"  if province == "Punjab_IND" & year_el == 2022
replace gov_period = "HR2009"  if province == "Haryana" & year_el == 2009
replace gov_period = "HR2014"  if province == "Haryana" & year_el == 2014
replace gov_period = "HR2019"  if province == "Haryana" & year_el == 2019
replace gov_period = "UP2012"  if province == "Uttar Pradesh" & year_el == 2012
replace gov_period = "UP2017a" if province == "Uttar Pradesh" & year_el == 2017 & _ym <  ym(2019, 5)
replace gov_period = "UP2017b" if province == "Uttar Pradesh" & year_el == 2017 & _ym >= ym(2019, 5)
replace gov_period = "UP2022"  if province == "Uttar Pradesh" & year_el == 2022
replace gov_period = "BR2010a" if province == "Bihar" & year_el == 2010 & _ym <  ym(2013, 6)
replace gov_period = "BR2010b" if province == "Bihar" & year_el == 2010 & _ym >= ym(2013, 6)
replace gov_period = "BR2015a" if province == "Bihar" & year_el == 2015 & _ym <  ym(2017, 7)
replace gov_period = "BR2015b" if province == "Bihar" & year_el == 2015 & _ym >= ym(2017, 7)
replace gov_period = "BR2020a" if province == "Bihar" & year_el == 2020 & _ym <  ym(2022, 8)
replace gov_period = "BR2020b" if province == "Bihar" & year_el == 2020 & _ym >= ym(2022, 8)

gen byte coalition = 0 if mla_party != "" & gov_period != ""
replace coalition = 1 if gov_period == "PB2012"  & inlist(mla_party, "SAD", "BJP")
replace coalition = 1 if gov_period == "PB2017"  & mla_party == "INC"
replace coalition = 1 if gov_period == "PB2022"  & mla_party == "AAP"
replace coalition = 1 if gov_period == "HR2009"  & mla_party == "INC"
replace coalition = 1 if gov_period == "HR2014"  & mla_party == "BJP"
replace coalition = 1 if gov_period == "HR2019"  & inlist(mla_party, "BJP", "JJP")
replace coalition = 1 if gov_period == "UP2012"  & mla_party == "SP"
replace coalition = 1 if gov_period == "UP2017a" & inlist(mla_party, "BJP", "ADS", "SBSP")
replace coalition = 1 if gov_period == "UP2017b" & inlist(mla_party, "BJP", "ADS")
replace coalition = 1 if gov_period == "UP2022"  & inlist(mla_party, "BJP", "ADS", "NISHAD")
replace coalition = 1 if gov_period == "BR2010a" & inlist(mla_party, "JDU", "BJP")
replace coalition = 1 if gov_period == "BR2010b" & mla_party == "JDU"
replace coalition = 1 if gov_period == "BR2015a" & inlist(mla_party, "JDU", "RJD", "INC")
replace coalition = 1 if gov_period == "BR2015b" & inlist(mla_party, "JDU", "BJP")
replace coalition = 1 if gov_period == "BR2015b" & mla_party == "LJP" & _ym < ym(2019, 5)
replace coalition = 1 if gov_period == "BR2020a" & inlist(mla_party, "BJP", "JDU", "HAMS")
replace coalition = 1 if gov_period == "BR2020a" & mla_party == "VIP" & _ym < ym(2022, 3)
replace coalition = 1 if gov_period == "BR2020b" & inlist(mla_party, "JDU", "RJD", "INC", "HAMS")

* Independent ministers, in the months they held office.
replace coalition = 1 if gov_period == "HR2009" & ac_uq_id == 309 & ///
    inrange(_ym, ym(2009, 11), ym(2011, 5))  // Panipat Rural, Om Prakash Jain
replace coalition = 1 if gov_period == "HR2009" & ac_uq_id == 322 & ///
    inrange(_ym, ym(2009, 11), ym(2012, 7))  // Sirsa, Gopal Kanda
replace coalition = 1 if gov_period == "HR2009" & ac_uq_id == 258 & ///
    _ym >= ym(2009, 11)                      // Faridabad NIT, Shiv Charan Lal Sharma
replace coalition = 1 if gov_period == "HR2009" & ac_uq_id == 269 & ///
    _ym >= ym(2009, 11)                      // Gurgaon, Sukhbir Kataria
replace coalition = 1 if gov_period == "HR2019" & ac_uq_id == 321 & ///
    _ym >= ym(2019, 11)                      // Rania, Ranjit Singh Chautala
* Kunda, Raja Bhaiya: out of the cabinet from March to September 2013.
replace coalition = 1 if gov_period == "UP2012" & ac_uq_id == 775 & ///
    !inrange(_ym, ym(2013, 3), ym(2013, 9))
replace coalition = 1 if gov_period == "BR2010b" & ac_uq_id == 81 & ///
    _ym >= ym(2014, 5)                       // Balrampur, Dulal Chandra Goswami
replace coalition = 1 if gov_period == "BR2010b" & ac_uq_id == 140 & ///
    inrange(_ym, ym(2014, 5), ym(2015, 1))   // Lauriya, Vinay Bihari
replace coalition = 1 if inlist(gov_period, "BR2020a", "BR2020b") & ac_uq_id == 73 & ///
    _ym >= ym(2021, 2)                       // Chakai, Sumit Kumar Singh

gen byte coalition_ext = coalition

* Outside support: parties without ministers.
replace coalition_ext = 1 if gov_period == "HR2009"  & mla_party == "BSP"
replace coalition_ext = 1 if gov_period == "HR2014"  & mla_party == "BSP"
replace coalition_ext = 1 if gov_period == "HR2019"  & mla_party == "HLP"
replace coalition_ext = 1 if gov_period == "UP2017a" & mla_party == "NISHAD" & ///
    _ym >= ym(2019, 4)
replace coalition_ext = 1 if gov_period == "UP2017b" & mla_party == "NISHAD"
replace coalition_ext = 1 if gov_period == "UP2022"  & mla_party == "JDL"
replace coalition_ext = 1 if gov_period == "BR2010b" & inlist(mla_party, "INC", "CPI")
replace coalition_ext = 1 if gov_period == "BR2010b" & mla_party == "RJD" & ///
    _ym >= ym(2014, 5)
replace coalition_ext = 1 if gov_period == "BR2015b" & inlist(mla_party, "LJP", "RLSP")
replace coalition_ext = 1 if gov_period == "BR2015b" & mla_party == "HAMS" & ///
    _ym < ym(2018, 2)
replace coalition_ext = 1 if gov_period == "BR2020b" & ///
    inlist(mla_party, "CPIMLL", "CPI", "CPM")

* Outside support: independents.
replace coalition_ext = 1 if gov_period == "PB2012" & inlist(ac_uq_id, 398, 406) & ///
    _ym < ym(2014, 3)                        // Atam Nagar and Ludhiana South, the Bains brothers
replace coalition_ext = 1 if gov_period == "HR2009" & ///
    inlist(ac_uq_id, 258, 259, 264, 269, 293) // Faridabad NIT, Hathin, Fatehabad, Gurgaon, Pundri
replace coalition_ext = 1 if gov_period == "HR2009" & ac_uq_id == 309 & ///
    _ym < ym(2011, 6)                        // Panipat Rural, until his resignation
replace coalition_ext = 1 if gov_period == "HR2009" & ac_uq_id == 322 & ///
    _ym < ym(2012, 8)                        // Sirsa, until his resignation
replace coalition_ext = 1 if gov_period == "HR2014" & ///
    inlist(ac_uq_id, 272, 293, 310)          // Punahana, Pundri, Samalkha
replace coalition_ext = 1 if gov_period == "HR2019" & ///
    inlist(ac_uq_id, 262, 267, 293, 298, 321) // Prithla, Badshahpur, Pundri, Nilokheri, Rania
replace coalition_ext = 1 if gov_period == "HR2019" & ac_uq_id == 316 & ///
    _ym < ym(2020, 2)                        // Meham, Balraj Kundu, until he withdrew
replace coalition_ext = 1 if gov_period == "HR2019" & ac_uq_id == 252 & ///
    _ym < ym(2020, 12)                       // Dadri, Sombir Sangwan, until he withdrew
replace coalition_ext = 1 if inlist(gov_period, "UP2017a", "UP2017b") & ///
    ac_uq_id == 720                          // Nautanwa, Aman Mani Tripathi
* Bihar: trust votes of June 2013 and July 2017.
replace coalition_ext = 1 if gov_period == "BR2010b" & ac_uq_id == 81 // Balrampur, Goswami
replace coalition_ext = 1 if gov_period == "BR2010b" & ac_uq_id == 140 & ///
    _ym < ym(2015, 2)                        // Lauriya, until he sided with Manjhi
replace coalition_ext = 1 if gov_period == "BR2010b" & inlist(ac_uq_id, 10, 168) & ///
    _ym < ym(2014, 5)                        // Obra and Dhaka, until Manjhi took over
replace coalition_ext = 1 if gov_period == "BR2015b" & ///
    inlist(ac_uq_id, 117, 119, 145)          // Bochaha, Kanti, Valmiki Nagar
replace coalition_ext = 1 if gov_period == "BR2015b" & ac_uq_id == 156 & ///
    _ym < ym(2019, 3)                        // Mokama, until he turned against it
replace coalition_ext = 1 if inlist(gov_period, "BR2020a", "BR2020b") & ///
    ac_uq_id == 73                           // Chakai, Sumit Kumar Singh

drop _ym

label variable gov_period    "State government in office"
label variable coalition     "MLA's party has ministers in the state government, or the MLA is a minister"
label variable coalition_ext "MLA in the state government or backing it from outside"

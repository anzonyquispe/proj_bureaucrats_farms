********************************************************************************
* State ruling coalition: the parties with ministers in the state government,
* month by month, and whether an AC's MLA belongs to one of them.
*
* Creates: gov_period ("BR2015b", ...): the state government in office. It
*              changes within a term when the government's parties change.
*          coalition: 1 if mla_party has ministers in that government, 0 if
*              not, missing when mla_party is missing.
*
* Only cabinet parties count, as in the DISHA ruling-coalition share:
* independents and parties that back the government from outside are 0 (INC
* governed Haryana 2009-14 with independents' support; the JD(U) governed
* Bihar 2013-15 with the support of INC, CPI and independents). The party is
* the one the MLA won the general election with; by-elections and defections
* are not followed.
*
* Changes within a term. The month of a change belongs to the new government,
* as in the election calendar.
*   Uttar Pradesh 2017: SBSP leaves the government in May 2019.
*   Bihar 2010: the JD(U) drops the BJP in June 2013.
*   Bihar 2015: the JD(U) leaves the Mahagathbandhan for the NDA in July 2017.
*   Bihar 2020: the JD(U) returns to the Mahagathbandhan in August 2022.
*
* Covers the terms that span the fire panel (September 2012 to August 2022);
* other months are left without a government period.
*
* Expects: province (calendar spelling, Punjab_IND), year, month, year_el and
* mla_party in memory, with the election calendar already applied.
********************************************************************************

confirm variable province year month year_el mla_party
confirm new variable gov_period coalition

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
drop _ym

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
replace coalition = 1 if gov_period == "BR2015b" & inlist(mla_party, "JDU", "BJP", "LJP")
replace coalition = 1 if gov_period == "BR2020a" & inlist(mla_party, "BJP", "JDU", "VIP", "HAMS")
replace coalition = 1 if gov_period == "BR2020b" & inlist(mla_party, "JDU", "RJD", "INC", "HAMS")

label variable gov_period "State government in office"
label variable coalition  "MLA's party has ministers in the state government"

********************************************************************************

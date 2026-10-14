********************************************************************************
* Assign each AC-month to the election whose term covers it, and label it.
*
* Creates: year_el (election year of the sitting term) and election
*          ("Punjab 2017", "Bihar 2015", ...).
*
* _app_disha.do and app_disha_desc.do each carried their own identical copy of
* this block, thirty lines of hand-coded cutoffs. Two copies of an electoral
* calendar drift apart, so it lives here and both include it.
*
* The cutoffs are the month the assembly took office, which is also what
* year_take/month_take record in the master and what build_ac_terms reads.
* They are hard-coded here because action_final.dta does not carry year_take.
* If the calendar ever changes, ac_india_elec_yr_clean.csv is the source of
* truth and this file has to follow it.
*
* Expects: province, year, month in memory.
********************************************************************************

confirm variable province year month

* The candidate file spells Punjab this way; align before matching on it.
replace province = "Punjab_IND" if province == "Punjab"

capture drop year_el
capture drop election
gen int year_el = .

* month_take is the month the new assembly took office: a month on or after it
* belongs to that election, earlier months to the previous one.
local bihar   12
local haryana 11
local punjab   4
local uttar    4

foreach y in 2010 2015 2020 {
    local next = `y' + 5
    replace year_el = `y' if province == "Bihar" & ///
        ((year > `y' & year < `next') | ///
         (year == `y' & month >= `bihar') | ///
         (year == `next' & month < `bihar'))
}

foreach y in 2009 2014 2019 2024 {
    local next = `y' + 5
    replace year_el = `y' if province == "Haryana" & ///
        ((year > `y' & year < `next') | ///
         (year == `y' & month >= `haryana') | ///
         (year == `next' & month < `haryana'))
}

foreach y in 2012 2017 2022 {
    local next = `y' + 5
    replace year_el = `y' if province == "Punjab_IND" & ///
        ((year > `y' & year < `next') | ///
         (year == `y' & month >= `punjab') | ///
         (year == `next' & month < `punjab'))
}

foreach y in 2012 2017 2022 {
    local next = `y' + 5
    replace year_el = `y' if province == "Uttar Pradesh" & ///
        ((year > `y' & year < `next') | ///
         (year == `y' & month >= `uttar') | ///
         (year == `next' & month < `uttar'))
}

gen str32 election = ""
replace election = "Bihar " + string(year_el) if province == "Bihar"
replace election = "Haryana " + string(year_el) if province == "Haryana"
* The label drops the _IND suffix, because the candidate file uses "Punjab".
replace election = "Punjab " + string(year_el) if province == "Punjab_IND"
replace election = "Uttar Pradesh " + string(year_el) if province == "Uttar Pradesh"
replace election = "" if year_el == .

quietly count if year_el == .
if r(N) > 0 {
    display as text "AC-months outside every electoral term: " r(N)
}

********************************************************************************

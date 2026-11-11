********************************************************************************
* Whether each AC's MLA is in the state ruling coalition, by month. Input of
* the Figure 3 coalition decomposition (_app_25). Covers every AC of the four
* states (MLA: _mla_party.do; coalition: _ruling_coalition.do).
*
* Output (data_output/intermediate): coalition_ac.dta/.csv, one row per AC x
* month, 2012m4-2023m1, with the month stored as cohort (year * 12 + month)
* so fire panels merge on ac_uq_id cohort. No ${sample} suffix. Runs on the
* team's Dropbox; the cluster only needs the .dta copied to intermediate.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults; is_rural_var, fe_list and ster_suffix are unused here.
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

********************************************************************************
* 1. MLA of each AC-election
********************************************************************************

do "${code}/_mla_party.do"
keep ac_uq_id province year_el mla_party
tempfile mla
save `mla'

********************************************************************************
* 2. AC x calendar month, with the term in force and its MLA
********************************************************************************

keep ac_uq_id province
duplicates drop
isid ac_uq_id

* 2012m4: first month with all four states in a term. 2023m1: last cohort of
* the fire panels (data end in 2022m8, cohorts keep months -5 to 6).
local first = ym(2012, 4)
local last  = ym(2023, 1)
expand `last' - `first' + 1
bysort ac_uq_id: gen int _ym = `first' + _n - 1
gen int year = year(dofm(_ym))
gen int month = month(dofm(_ym))
drop _ym

do "${code}/_app_disha_election_calendar.do"
drop election
assert !missing(year_el)

merge m:1 ac_uq_id province year_el using `mla', keep(master match)
quietly count if _merge == 1
if r(N) > 0 {
    display as error "AC-months whose term has no winner in the candidate file: " r(N)
    tab province year_el if _merge == 1
    exit 459
}
drop _merge

********************************************************************************
* 3. Ruling coalition
********************************************************************************

do "${code}/_ruling_coalition.do"
assert gov_period != "" & !missing(coalition)
* Government only, as in the DISHA share: no outside support.
drop coalition_ext
rename coalition coalition_ac
label variable coalition_ac "AC's MLA belongs to the state ruling coalition"

display as text _n "Government parties by period (AC-months; independents are IND):"
tab mla_party gov_period if coalition_ac == 1
display as text _n "Share of ACs in the coalition by government period:"
tabulate gov_period, summarize(coalition_ac) means

gen long cohort = year * 12 + month
label variable cohort "Calendar month, year * 12 + month"
order ac_uq_id cohort year month province year_el gov_period mla_party coalition_ac
sort ac_uq_id cohort
isid ac_uq_id cohort
compress
save "${int_data}/coalition_ac.dta", replace
export delimited using "${int_data}/coalition_ac.csv", replace

display as result "Generated: ${int_data}/coalition_ac.dta"

********************************************************************************

********************************************************************************
* Whether each AC's MLA belongs to the state ruling coalition, month by month.
* Input of the coalition decomposition of Figure 3 (_app_25).
*
* The MLA is the general-election winner of the AC (_mla_party.do) and the
* coalition is the set of parties with ministers in the state government that
* month (_ruling_coalition.do). Every AC of the four states is covered,
* including those spanning several districts.
*
* Output (data_output/intermediate):
*   coalition_ac.dta/.csv: one row per AC x calendar month, April 2012 to
*       December 2022, with the MLA's party, the state government in office
*       and coalition_ac. The month is stored as cohort (year * 12 + month,
*       the stacked panels' coding), so a fire panel merges it on
*       ac_uq_id cohort and gets the status at each stack's cohort month.
*
* The candidate file does not depend on the sample, so the output carries no
* ${sample} suffix. Runs where the candidate file lives (the team's Dropbox);
* the cluster jobs only need the .dta copied into data_output/intermediate.
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

* April 2012 is the first month in which all four states sit in a term of the
* candidate file (Punjab and Uttar Pradesh voted in early 2012).
local first = ym(2012, 4)
local last  = ym(2022, 12)
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

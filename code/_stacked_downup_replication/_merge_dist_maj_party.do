********************************************************************************
* Attach dist_maj_party (_app_dist_maj_party_generation.do) to a stacked fire
* panel, fixed at each stack's cohort month: every row of a stack takes the
* district majority of the term in force when the stack's treatment starts,
* so the moderator is constant within the stack.
*
* Rows of ACs spanning several districts have no district in the DISHA
* crosswalk and are dropped; the log reports how many.
*
* The crosswalk does not depend on the sample, so the full-sample file is read
* for every $sample.
*
* Expects: province (string), ac_uq_id and cohort (numeric), year, month and
* relative_monthyear or monthyear, with cohort coded as year * 12 + month.
********************************************************************************

confirm string variable province
confirm numeric variable ac_uq_id cohort
confirm new variable year_el dist_maj_party

* Check that cohort is coded as year * 12 + month.
capture confirm variable relative_monthyear
if !_rc {
    assert year * 12 + month == cohort if relative_monthyear == 0
}
else {
    confirm numeric variable monthyear
    assert year * 12 + month == monthyear
}

preserve
    keep province cohort
    duplicates drop
    gen int year = floor((cohort - 1) / 12)
    gen int month = cohort - 12 * year
    * The calendar rewrites Punjab as Punjab_IND; keep the panel's spelling.
    gen str32 _province = province
    do "${code}/_app_disha_election_calendar.do"
    quietly count if missing(year_el)
    if r(N) > 0 {
        display as error "Cohort months outside every electoral term: " r(N)
        exit 459
    }
    keep _province cohort year_el
    rename _province province
    tempfile cohort_term
    save `cohort_term'
restore

merge m:1 province cohort using `cohort_term', assert(match) nogen

merge m:1 ac_uq_id year_el using "${int_data}/dist_maj_party.dta", ///
    keepusing(dist_maj_party) keep(master match)

egen byte _tag_ac = tag(ac_uq_id)
egen byte _tag_out = tag(ac_uq_id) if _merge == 1
quietly count if _tag_ac
local n_acs_all = r(N)
quietly count if _tag_out == 1
display as result "ACs without dist_maj_party (spanning several districts): " ///
    r(N) " of `n_acs_all'"
quietly count if _merge == 1
display as result "Rows dropped: " r(N) " of " _N
keep if _merge == 3
drop _merge _tag_ac _tag_out
assert inlist(dist_maj_party, 0, 1)

display as text _n "dist_maj_party by treatment group (rows):"
tab treat dist_maj_party, row

********************************************************************************

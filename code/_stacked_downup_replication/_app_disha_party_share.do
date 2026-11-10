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
* Winners, party labels and alliances come from _mla_party.do.
*
* Expects: ac_uq_id, distr_id, province, year_el and is_rural in memory, and
* the election calendar already applied.
********************************************************************************

confirm variable ac_uq_id distr_id province year_el is_rural

********************************************************************************
* 1. Winner of each AC-election and their party
********************************************************************************

preserve
    do "${code}/_mla_party.do"
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

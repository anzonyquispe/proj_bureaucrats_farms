********************************************************************************
* Political fragmentation of the AC's district, for the DISHA panel.
*
* Creates (g = party|alliance, u = all|rural):
*   enp_<g>_<u>     effective number of parties by seats, district x term
*                   (1 / sum p_i^2); each independent is its own party.
*   enp1_<g>_<u>    enp - 1, used in the regressions.
*   ruling_<u>      share of the district's ACs held by the state government
*                   that month (coalition, _ruling_coalition.do).
*   ruling_ext_<u>  the same, with outside support (coalition_ext).
* "rural" counts only the ACs with a rural grid in the term.
*
* Expects: ac_uq_id distr_id province year month year_el is_rural mla_party
* mla_alliance, after the calendar and _app_disha_party_share.do.
********************************************************************************

confirm variable ac_uq_id distr_id province year month year_el is_rural ///
    mla_party mla_alliance

********************************************************************************
* 1. Effective number of parties from seats, district x term
********************************************************************************

preserve
    keep if !missing(year_el) & !missing(distr_id)
    gen byte _rural_month = (is_rural != 0 & !missing(is_rural))
    collapse (max) rural = _rural_month (firstnm) mla_party mla_alliance, ///
        by(ac_uq_id distr_id province year_el)
    egen long _ac = group(ac_uq_id)
    gen byte _u_all = 1
    gen byte _u_rural = rural
    foreach g in party alliance {
        * Each independent is a party of its own.
        gen _grp = mla_`g'
        replace _grp = "IND" + string(_ac) if mla_party == "IND"
        foreach u in all rural {
            gen byte _in = _u_`u' & _grp != ""
            bysort distr_id year_el: egen _total = total(_in)
            bysort distr_id year_el _grp: egen _same = total(_in)
            * Summing n_i / N^2 over the ACs of party i gives p_i^2.
            gen _c = cond(_in, _same / _total^2, 0)
            bysort distr_id year_el: egen _hhi = total(_c)
            gen enp_`g'_`u' = 1 / _hhi if _total > 0
            gen enp1_`g'_`u' = enp_`g'_`u' - 1
            drop _in _total _same _c _hhi
        }
        drop _grp
    }
    keep ac_uq_id year_el enp_* enp1_*
    tempfile enp
    save `enp'
restore
merge m:1 ac_uq_id year_el using `enp', nogen keep(master match)

********************************************************************************
* 2. Ruling-coalition shares, district x month
********************************************************************************

* By month: an independent's status can change within a government.
do "${code}/_ruling_coalition.do"

preserve
    keep if !missing(year_el) & !missing(distr_id)
    isid ac_uq_id year month
    gen byte _rural_month = (is_rural != 0 & !missing(is_rural))
    bysort ac_uq_id year_el: egen byte rural = max(_rural_month)
    gen byte _u_all = 1
    gen byte _u_rural = rural
    foreach c in coalition coalition_ext {
        local m = cond("`c'" == "coalition", "ruling", "ruling_ext")
        foreach u in all rural {
            gen byte _in = _u_`u' & !missing(`c')
            bysort distr_id year month: egen _total = total(_in)
            bysort distr_id year month: egen _gov = total(_in & `c' == 1)
            gen `m'_`u' = _gov / _total if _total > 0
            drop _in _total _gov
        }
    }
    keep ac_uq_id year month ruling_*
    tempfile rc
    save `rc'
restore
merge 1:1 ac_uq_id year month using `rc', nogen keep(master match)

********************************************************************************

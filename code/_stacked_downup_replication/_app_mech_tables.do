********************************************************************************
* Mechanism tables of the appendix (Section B.6), at AC x month-year:
*   B.8  descriptive statistics (tab:disha_descriptive)
*   B.9  fires on exposure, month and quarter (tab:mechanism_count)
*   B.10 crop-burning documents and Air Act court cases (tab:mechanism)
*   B.11 Air Act court cases, t to t+3 (tab:app_courts_leads)
* Writes tables/mech_results.csv and tables/mech_descriptives.csv;
* _app_mech_tables.py turns them into the .tex tables.
*
* Inputs (data_output/intermediate): action_final_merged_kw.dta
* (_app_mech_merge.do), data_2012_2024_ac_downup_pop_rice.dta (AC 2010
* population), cb_district_month.csv and cb_entry.csv (_app_mech_cb_docs.py).
* Not an event study (no treat or relative time), so the ymean / moderator
* template does not apply. Exposure is standardized within each sample.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for the five sbatch-array parameters. These tables are
    * a single specification, so fe_list and ster_suffix are inert here.
    global location     "shell"
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
global tables   "${code}/../../tables"

* Regression with AC-clustered SE; posts each regressor except the wind
* controls. Mean DV: ymean() if given, else the mean in the estimation sample.
capture program drop mreg
program define mreg
    syntax varlist, h(name) tab(string) col(string) absorb(string) [ymean(string) lead(integer 0)]
    gettoken y xs : varlist
    quietly reghdfe `y' `xs', absorb(`absorb') vce(cluster ac_uq_id)
    local ym "`ymean'"
    if "`ym'" == "" {
        quietly summarize `y' if e(sample)
        local ym = r(mean)
    }
    foreach v of local xs {
        if inlist("`v'", "wind_direction", "av_wind_speed") continue
        post `h' ("`tab'") ("`col'") (`lead') ("`v'") (_b[`v']) (_se[`v']) ///
            (2*ttail(e(df_r), abs(_b[`v'] / _se[`v']))) (e(N)) (e(N_clust)) (`ym')
    }
end

* Descriptive row: summary statistics, or distinct values for identifiers.
capture program drop dpost
program define dpost
    syntax varname, h(name) panel(string) key(string) [id]
    if "`id'" != "" {
        tempvar t
        egen `t' = tag(`varlist')
        quietly count if `t'
        post `h' ("`panel'") ("`key'") (.) (.) (.) (.) (_N) (r(N))
    }
    else {
        quietly summarize `varlist'
        post `h' ("`panel'") ("`key'") (r(mean)) (r(sd)) (r(min)) (r(max)) (r(N)) (.)
    }
end

tempname h d
postfile `h' str4 tab str4 col byte lead str16 var double(b se p) long(N nclust) double ymean ///
    using "${tables}/mech_results.dta", replace
postfile `d' str1 panel str16 key double(mean sd min max) long(N unique) ///
    using "${tables}/mech_descriptives.dta", replace

********************************************************************************
* Inputs
********************************************************************************

* AC population 2010 (GPW v4); the team's AC_total_pop.dta was 55,547 for every AC.
use ac_uq_id total_pop_ac using "${int_data}/data_2012_2024_ac_downup_pop_rice.dta", clear
bysort ac_uq_id: keep if _n == 1
tempfile acpop
save `acpop'

* Documents: first month with a document of any kind, and district-month counts.
import delimited using "${int_data}/cb_entry.csv", clear varnames(1)
rename district_panel district
gen fd = date(first_doc, "YMD")
gen entry_my = year(fd) * 12 + month(fd)
keep district entry_my
tempfile entry
save `entry'
import delimited using "${int_data}/cb_district_month.csv", clear varnames(1)
rename district_panel district
keep district year month n_cb_rel23 n_cb_rel3
tempfile cb
save `cb'

* AC-month panel, 2012m9-2022m8 (monthyear = year*12 + month).
use ac_uq_id monthyear year month district distr_id province is_rural count count_prev_year ///
    count_downwind_rural_prev_year court_cases court_any wind_direction av_wind_speed ///
    using "${int_data}/action_final_merged_kw${sample}.dta", clear
merge m:1 ac_uq_id using `acpop', keep(master match)
assert _merge == 3
drop _merge
gen double expo = count_downwind_rural_prev_year / total_pop_ac
replace court_any = court_any * 100
merge m:1 district year month using `cb', keep(master match) nogen
merge m:1 district using `entry', keep(master match) nogen
foreach v in n_cb_rel23 n_cb_rel3 {
    replace `v' = 0 if `v' == .
}
* An entry before the panel starts means the district is in from 2012m9.
replace entry_my = max(entry_my, 2012*12 + 9) if entry_my < .
gen a_rel23 = (n_cb_rel23 > 0) * 100
gen a_rel3 = (n_cb_rel3 > 0) * 100
gen byte s_e = is_rural != 0 & entry_my < . & monthyear >= entry_my
gen byte s_court = is_rural != 0 & monthyear <= 2018*12 + 12
* Court cases k months after the exposure month.
sort ac_uq_id monthyear
forvalues k = 0/3 {
    by ac_uq_id: gen double court_any_f`k' = court_any[_n + `k'] if monthyear[_n + `k'] == monthyear + `k'
}
tempfile panel
save `panel'

********************************************************************************
* Documents sample, month: B.10 cols 1-2, B.9 cols 1-2, B.8 panel A
********************************************************************************
keep if s_e
egen z = std(expo)
quietly summarize a_rel23
mreg a_rel23 z, h(`h') tab(B10) col(c1) absorb(ac_uq_id monthyear) ymean(`r(mean)')
quietly summarize a_rel3
mreg a_rel3 z, h(`h') tab(B10) col(c2) absorb(ac_uq_id monthyear) ymean(`r(mean)')
mreg count z wind_direction av_wind_speed, h(`h') tab(B9) col(c1) absorb(ac_uq_id monthyear)
mreg count z count_prev_year wind_direction av_wind_speed, h(`h') tab(B9) col(c2) absorb(ac_uq_id monthyear)
foreach v in ac_uq_id distr_id year month province {
    dpost `v', h(`d') panel(A) key(`v') id
}
dpost count, h(`d') panel(A) key(fires)
dpost count_prev_year, h(`d') panel(A) key(fires_l12)
dpost a_rel23, h(`d') panel(A) key(most)
dpost a_rel3, h(`d') panel(A) key(only)
dpost expo, h(`d') panel(A) key(expo)

********************************************************************************
* Documents sample, quarter: B.10 cols 3-4, B.9 cols 3-4, B.8 panel A
* (calendar quarters, complete quarters only; counts, fires and exposure summed)
********************************************************************************
use `panel', clear
gen cq = yq(year, ceil(month / 3))
gen entry_q = yq(floor((entry_my - 1) / 12), ceil((mod(entry_my - 1, 12) + 1) / 3)) if entry_my < .
gen byte one = 1
gen byte nm = expo < .
collapse (sum) n_cb_rel23 n_cb_rel3 count count_prev_year expo nm nmonths = one ///
    (mean) wind_direction av_wind_speed (max) is_rural (firstnm) entry_q, by(ac_uq_id cq)
keep if nmonths == 3
replace expo = . if nm < 3
gen a_rel23 = (n_cb_rel23 > 0) * 100
gen a_rel3 = (n_cb_rel3 > 0) * 100
keep if is_rural != 0 & entry_q < . & cq >= entry_q
egen z = std(expo)
quietly summarize a_rel23
mreg a_rel23 z, h(`h') tab(B10) col(c3) absorb(ac_uq_id cq) ymean(`r(mean)')
quietly summarize a_rel3
mreg a_rel3 z, h(`h') tab(B10) col(c4) absorb(ac_uq_id cq) ymean(`r(mean)')
mreg count z wind_direction av_wind_speed, h(`h') tab(B9) col(c3) absorb(ac_uq_id cq)
mreg count z count_prev_year wind_direction av_wind_speed, h(`h') tab(B9) col(c4) absorb(ac_uq_id cq)
dpost count, h(`d') panel(A) key(q_fires)
dpost a_rel23, h(`d') panel(A) key(q_most)
dpost a_rel3, h(`d') panel(A) key(q_only)
dpost expo, h(`d') panel(A) key(q_expo)

********************************************************************************
* Court cases sample, month: B.10 col 5, B.11, B.8 panel B
********************************************************************************
use `panel', clear
keep if s_court
egen z = std(expo)
forvalues k = 0/3 {
    quietly summarize court_any_f`k'
    local ym = r(mean)
    if `k' == 0 mreg court_any_f0 z, h(`h') tab(B10) col(c5) absorb(ac_uq_id monthyear) ymean(`ym')
    mreg court_any_f`k' z, h(`h') tab(B11) col(t) absorb(ac_uq_id monthyear) ymean(`ym') lead(`k')
}
foreach v in ac_uq_id distr_id year month province {
    dpost `v', h(`d') panel(B) key(`v') id
}
dpost court_any, h(`d') panel(B) key(court)
dpost expo, h(`d') panel(B) key(expo)

********************************************************************************
* Court cases sample, quarter: B.10 col 6, B.8 panel B
* (complete quarters 2012q4-2018q4; cases and exposure summed)
********************************************************************************
use `panel', clear
keep if s_court & court_cases < .
gen cq = yq(year, ceil(month / 3))
gen byte one = 1
gen byte nm = expo < .
collapse (sum) court_cases expo nm nmonths = one, by(ac_uq_id cq)
keep if nmonths == 3
replace expo = . if nm < 3
gen court_any = (court_cases > 0) * 100
egen z = std(expo)
quietly summarize court_any
mreg court_any z, h(`h') tab(B10) col(c6) absorb(ac_uq_id cq) ymean(`r(mean)')
dpost court_any, h(`d') panel(B) key(q_court)
dpost expo, h(`d') panel(B) key(q_expo)

postclose `h'
postclose `d'
foreach f in mech_results mech_descriptives {
    use "${tables}/`f'.dta", clear
    export delimited using "${tables}/`f'.csv", replace
    erase "${tables}/`f'.dta"
}
display "ALL DONE"

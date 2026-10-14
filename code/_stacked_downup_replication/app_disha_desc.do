********************************************************************************
* Descriptive statistics for the DISHA appendix sample.
*
* Input: action_final.dta, written by _app_disha_generation.do.
*
* The sample is pinned to the estimation sample of _app_disha.do's controlled
* fires regression, so the table describes the rows the estimates actually use
* rather than the full AC-month panel.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for the five sbatch-array parameters. The DISHA
    * tables are a single specification, so fe_list and ster_suffix are inert
    * here; they stay for consistency with the other analysis dofiles.
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

*-------------------------------------------------------------------------------
* Helper programs
*  NOTE: these are rclass, so calling them WIPES r().  Always copy every r()
*        result you need into a scalar/local BEFORE calling them.
*        They take a scalar NAME (or a literal), not a rounded value, so the
*        full precision of the statistic is preserved.
*-------------------------------------------------------------------------------

capture program drop _fmt_num
program define _fmt_num, rclass
    args x
    if missing(`x') {
        return local out ""
        exit
    }
    local out : display %15.3fc `x'
    local out = strtrim("`out'")
    return local out "`out'"
end

capture program drop _fmt_int
program define _fmt_int, rclass
    args x
    if missing(`x') {
        return local out ""
        exit
    }
    local out : display %20.0fc `x'
    local out = strtrim("`out'")
    return local out "`out'"
end

capture program drop _unique_count
program define _unique_count, rclass
    syntax varname [if]
    preserve
        if `"`if'"' != "" {
            quietly keep `if'
        }
        quietly keep `varlist'
        quietly drop if missing(`varlist')
        quietly count
        local nobs = r(N)
        quietly duplicates drop
        quietly count
        return scalar n    = r(N)
        return scalar nobs = `nobs'
    restore
end

use "${int_data}/action_final${sample}.dta", clear

rename total_pop_ac_nosmall tot_population

gen pop_share1 = count_downwind_rural_prev_year / tot_population
gen pop_share2 = any_downwind_rural_prev_year / tot_population

* Formerly: zscore pop_share`i' if ..., stub(std_)
forvalues i = 1/2 {
    egen std_pop_share`i' = std(pop_share`i') if disha_sample & is_rural != 0
}

do "${code}/_app_disha_election_calendar.do"
do "${code}/_app_disha_incumbents.do"

*-------------------------------------------------------------------------------
* Outcomes, built exactly as in _app_disha.do
*-------------------------------------------------------------------------------

gen y_fir = (fir > 0 & fir != .) * 100
bysort ac_uq_id (monthyear): gen y_fir_tp1 = y_fir[_n + 1]

gen y_agri = (topic_primary_agriculture > 0 & topic_primary_agriculture != .) * 100
gen y_environment = (environment_pollution > 0 & environment_pollution != .) * 100
gen y_development = (topic_primary_development > 0 & topic_primary_development != .) * 100
gen y_election = (topic_primary_election_campaign > 0 & topic_primary_election_campaign != .) * 100
gen y_governance = (topic_primary_governance > 0 & topic_primary_governance != .) * 100
gen y_welfare = (topic_primary_welfare > 0 & topic_primary_welfare != .) * 100

gen n_others = number_docs - environment_pollution - topic_primary_agriculture ///
    - topic_primary_development - topic_primary_election_campaign ///
    - topic_primary_governance - topic_primary_welfare
gen y_others = (n_others > 0 & n_others != .) * 100

format qtr %tq

foreach y of varlist y_environment y_agri y_development y_election ///
        y_governance y_welfare y_others y_fir {
    bysort ac_uq_id qtr: egen `y'_qtr = max(`y')
}

* Same definition as _app_disha.do, which is what the table should describe.
capture drop substitution_qtr
gen substitution_qtr = y_environment_qtr - ///
    (y_agri_qtr + y_development_qtr + y_election_qtr + y_governance_qtr + ///
     y_welfare_qtr + y_others_qtr) / 6
replace substitution_qtr = 0 if substitution_qtr == .

encode election, gen(election_id)
gen countk = count * 1000

* Restrict to the rows the controlled fires regression actually uses.
quietly reghdfe countk std_pop_share2 count_prev_year ///
    if disha_sample == 1 & is_rural != 0, ///
    absorb(ac_uq_id monthyear) cluster(ac_uq_id)
gen byte esample = e(sample)
keep if esample == 1
drop esample

quietly count
display as result "Descriptive sample: " r(N) " AC-months"

*-------------------------------------------------------------------------------
* Descriptive statistics table
*-------------------------------------------------------------------------------

* Extra restriction on top of the estimation sample. Leave empty to describe it
* in full.
local sample_if ""

* LaTeX end-of-row. Stata's file write passes backslashes through literally,
* so the row terminator is written as a plain "\\" (NOT "\\\\").
local eol "\\"

local colsel ac_uq_id year month province count ///
    substitution_qtr y_environment_qtr y_agri_qtr ///
    y_development_qtr y_election_qtr y_governance_qtr y_welfare_qtr ///
    y_others_qtr y_fir ///
    pop_share2 av_wind_speed wind_direction
local uniquevars ac_uq_id year month province

* Row labels. The macro name must be lab_<varname> exactly, otherwise the row
* falls back to the variable label and then to the escaped variable name.
local lab_ac_uq_id              "Assembly Constituency"
local lab_year                  "Year"
local lab_month                 "Month"
local lab_province              "Province"
local lab_count                 "Number of Fires"
local lab_substitution_qtr      "Substitution Index"
local lab_y_environment_qtr     "Any Environment / Pollution Document (\%)"
local lab_y_agri_qtr            "Any Agriculture Document (\%)"
local lab_y_development_qtr     "Any Development Document (\%)"
local lab_y_election_qtr        "Any Election Campaign Document (\%)"
local lab_y_governance_qtr      "Any Governance Document (\%)"
local lab_y_welfare_qtr         "Any Welfare Document (\%)"
local lab_y_others_qtr          "Any Other-Topic Document (\%)"
local lab_y_fir                 "Any FIR (\%)"
local lab_pop_share2            "Downwind Rural Pop., Previous Year (share)"
local lab_av_wind_speed         "Average Wind Speed"
local lab_wind_direction        "Wind Direction"

capture file close texout
file open texout using "${tables}/descriptives_disha${sample}.tex", write replace

file write texout "\begin{tabular}{lrrrrrr}" _n
file write texout "\toprule" _n
file write texout " & Mean & SD & Min & Max & Observations & Unique Obs.`eol'" _n
file write texout "\midrule" _n

local in_id_block = 1

foreach v of local colsel {

    local meanfmt ""
    local sdfmt   ""
    local minfmt  ""
    local maxfmt  ""
    local Nfmt    ""
    local ufmt    ""

    local isuniq = 0
    if strpos(" `uniquevars' ", " `v' ") local isuniq = 1

    * rule between the identifier rows and the variable rows
    if `in_id_block' == 1 & `isuniq' == 0 {
        file write texout "\midrule" _n
        local in_id_block = 0
    }

    if `isuniq' == 1 {
        quietly _unique_count `v' `sample_if'
        local nuniq = r(n)
        local nobs  = r(nobs)
        _fmt_int `nuniq'
        local ufmt "`r(out)'"
        _fmt_int `nobs'
        local Nfmt "`r(out)'"
    }
    else {
        tempname smean ssd smin smax
        quietly summarize `v' `sample_if'
        * copy everything out of r() BEFORE the first _fmt_* call wipes it
        scalar `smean' = r(mean)
        scalar `ssd'   = r(sd)
        scalar `smin'  = r(min)
        scalar `smax'  = r(max)
        local  nobs    = r(N)

        _fmt_num `smean'
        local meanfmt "`r(out)'"
        _fmt_num `ssd'
        local sdfmt "`r(out)'"
        _fmt_num `smin'
        local minfmt "`r(out)'"
        _fmt_num `smax'
        local maxfmt "`r(out)'"
        _fmt_int `nobs'
        local Nfmt "`r(out)'"
    }

    * label, with fallbacks so a missing lab_* macro never blanks the row
    local vlabel "`lab_`v''"
    if "`vlabel'" == "" {
        local vlabel : variable label `v'
    }
    if "`vlabel'" == "" {
        local vlabel = subinstr("`v'", "_", "\_", .)
    }

    file write texout "`vlabel' & `meanfmt' & `sdfmt' & `minfmt' & `maxfmt' & `Nfmt' & `ufmt'`eol'" _n
}

file write texout "\bottomrule" _n
file write texout "\end{tabular}" _n
file close texout

display as result "Generated: ${tables}/descriptives_disha${sample}.tex"

********************************************************************************

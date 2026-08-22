********************************************************************************
* Descriptive table for the stacked protest sample
* Output actively referenced by main.tex:
*   tables/_protest_stacked_descriptive.tex
********************************************************************************

version 17
clear
set more off

if "$root" == "" {
    * Standalone defaults for the five cluster parameters.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1"
    global ster_suffix  ""
    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }
}

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"

local protest_input ///
    "${int_data}/stacked_data_protest5km_election_sameterm${sample}.csv"
capture confirm file "`protest_input'"
if _rc {
    local protest_input ///
        "${int_data}/cohortes_protest_term/stacked_data_protest5km_election_sameterm${sample}.csv"
}
capture confirm file "`protest_input'"
if _rc {
    local protest_input ///
        "${int_data}/cohorts_protest_term/stacked_data_protest5km_election_sameterm${sample}.csv"
}
confirm file "`protest_input'"
display as text "Final same-term protest input: `protest_input'"
import delimited using "`protest_input'", clear varnames(1) case(preserve)

confirm variable cohort_id
confirm variable cohort_election_year
confirm variable cohort_term_start
confirm variable cohort_analysis_max
assert monthyear >= cohort_term_start
assert monthyear <= cohort_analysis_max
assert cohort_term_start <= cohort
assert inrange(cohort_analysis_max - cohort_term_start, 0, 59)
bysort cohort_id: assert cohort == cohort[1]
bysort cohort_id: assert cohort_election_year == cohort_election_year[1]

capture confirm variable relative_year_bin
if _rc {
    rename relative_year relative_year_bin
}
assert relative_year_bin == floor((monthyear - cohort) / 12)
drop if relative_year_bin == -5
display as text "Canonical protest sample: full same-term support except relative year -5"

* Prefer raw count and rebuild the scaled regression outcome.
capture drop countk
gen countk = count * 1000

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural) nogen
keep if ${is_rural_var} == 1

egen prov = group(province)
egen legis_govyear = group(province election_year)
egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
egen province_cohort = group(province cohort_id)
egen relativeyear_cohort = group(relative_year_bin cohort_id)
egen ac_elec_yr = group(ac_uq_id cohort_election_year cohort_id)

bysort unique_small_grid_id_cohort: egen byte has_pre = max(relative_year_bin < 0)
bysort unique_small_grid_id_cohort: egen byte has_post = max(relative_year_bin >= 0)
egen byte unit_tag = tag(unique_small_grid_id_cohort)
quietly count if unit_tag
local units_before = r(N)
quietly count if unit_tag & has_pre == 1 & has_post == 1
local units_balanced = r(N)
display as text "Grid-cohort units with pre and post periods: `units_balanced' of `units_before'"
keep if has_pre == 1 & has_post == 1
assert has_pre == 1 & has_post == 1
drop unit_tag has_pre has_post
gen post_ = relative_year_bin >= 0
gen protest = post_ * treat
gen moderator = 0

* Restrict descriptives to the same estimation sample used by the baseline DiD.
quietly reghdfejl countk ///
    ib0.post_##ib0.treat##ib0.moderator wind_direction av_wind_speed, ///
    absorb(unique_small_grid_id_cohort relativeyear_cohort ///
           province_cohort#election_year province_cohort#c.monthyear) ///
    vce(cluster ac_elec_yr)
keep if e(sample)

capture program drop _fmt_num
program define _fmt_num, rclass
    args x
    if missing(`x') {
        return local out ""
        exit
    }
    local out : display %15.3fc `x'
    local out = strtrim("`out'")
    while substr("`out'", -1, 1) == "0" & strpos("`out'", ".") > 0 {
        local out = substr("`out'", 1, strlen("`out'") - 1)
    }
    if substr("`out'", -1, 1) == "." {
        local out = substr("`out'", 1, strlen("`out'") - 1)
    }
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
    syntax varname
    preserve
        keep `varlist'
        drop if missing(`varlist')
        duplicates drop
        count
        return scalar n = r(N)
    restore
end

local colsel unique_small_grid_id year month ac_uq_id prov protest5km ///
    cohort legis_govyear relative_year_bin protest countk ///
    rice_prod_aclvl_ahigh
local contvars countk rice_prod_aclvl_ahigh protest relative_year_bin

local lab_unique_small_grid_id  "Grid ID"
local lab_year                  "Year"
local lab_month                 "Month"
local lab_ac_uq_id              "Assembly Constituency (AC)"
local lab_prov                  "Province"
local lab_protest5km            "Within 5 km of Protest"
local lab_cohort                "Cohort"
local lab_legis_govyear         "Legislature"
local lab_relative_year_bin     "Relative year"
local lab_protest               "Protest"
local lab_countk                "Number of Fires (in 1,000 units)"
local lab_rice_prod_aclvl_ahigh "High Rice Production (AC level)"

capture file close texout
file open texout using "${tables}/_protest_stacked_descriptive${sample}.tex", write replace
file write texout "\begin{tabular}{lrrrrrr}" _n
file write texout "\toprule" _n
file write texout " & Mean & SD & Min & Max & Observations & Unique Obs.\\\\" _n
file write texout "\midrule" _n

foreach v of local colsel {
    quietly count if !missing(`v')
    local Nval = r(N)
    quietly _unique_count `v'
    local uval = r(n)
    _fmt_int `Nval'
    local Nfmt "`r(out)'"
    _fmt_int `uval'
    local ufmt "`r(out)'"

    local meanfmt ""
    local sdfmt ""
    local minfmt ""
    local maxfmt ""
    if strpos(" `contvars' ", " `v' ") {
        quietly summarize `v'
        _fmt_num `r(mean)'
        local meanfmt "`r(out)'"
        _fmt_num `r(sd)'
        local sdfmt "`r(out)'"
        _fmt_num `r(min)'
        local minfmt "`r(out)'"
        _fmt_num `r(max)'
        local maxfmt "`r(out)'"
    }
    local vlabel "`lab_`v''"
    file write texout "`vlabel' & `meanfmt' & `sdfmt' & `minfmt' & `maxfmt' & `Nfmt' & `ufmt'\\\\" _n
}

file write texout "\bottomrule" _n
file write texout "\end{tabular}" _n
file close texout
display as result "Generated: ${tables}/_protest_stacked_descriptive${sample}.tex"

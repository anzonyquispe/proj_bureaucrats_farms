********************************************************************************
* Descriptive table for the stacked politician-characteristics sample
* Output actively referenced by main.tex:
*   tables/_politicians_stacked_descriptive.tex
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

* Exact sample exported by the richest interacted politician DiD.
import delimited using ///
    "${int_data}/politician_downup_ac_pop_esample${sample}.csv", ///
    clear varnames(1) case(preserve)
display as text "Politician richest-DiD descriptive sample: " _N

capture drop prov legis_govyear agri_politician
egen prov = group(province)
egen legis_govyear = group(province election_year)
gen agri_politician = post_ * treat

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

local colsel unique_small_grid_id year month ac_uq_id prov election_year ///
    cohort legis_govyear self_profession_nomiss relative_year_bin ///
    agri_politician countk ///
    rice_prod_aclvl_ahigh
local contvars countk rice_prod_aclvl_ahigh relative_year_bin agri_politician

local lab_unique_small_grid_id  "Grid ID"
local lab_year                  "Year"
local lab_month                 "Month"
local lab_ac_uq_id              "Assembly Constituency (AC)"
local lab_prov                  "Province"
local lab_election_year         "Election Year"
local lab_cohort                "Cohort"
local lab_legis_govyear         "Legislature"
local lab_self_profession_nomiss "Agricultural Politician"
local lab_relative_year_bin     "Relative year"
local lab_agri_politician       "Switching to Agri Pol"
local lab_countk                "Number of Fires (in 1,000 units)"
local lab_rice_prod_aclvl_ahigh "High Rice Production (AC level)"

capture file close texout
file open texout using "${tables}/_politicians_stacked_descriptive${sample}${ster_suffix}.tex", write replace
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
display as result "Generated: ${tables}/_politicians_stacked_descriptive${sample}${ster_suffix}.tex"

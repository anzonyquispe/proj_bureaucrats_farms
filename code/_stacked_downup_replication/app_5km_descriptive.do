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
    global is_rural_var "is_rural_area"
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
global tables   "${root}/tex/paper/tables"

import delimited using "${int_data}/stacked_data_protest5km${sample}.csv", ///
    clear varnames(1) case(preserve)

capture confirm variable relative_year_bin
if _rc {
    rename relative_year relative_year_bin
}

* Prefer raw count and rebuild the scaled regression outcome.
capture drop countk
gen countk = count * 1000

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keep(master match) keepusing(is_rural_area is_rural_farzad) nogen
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

egen prov = group(province)
egen legis_govyear = group(province election_year)
egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort)
egen province_cohort = group(province cohort)
egen ac_elec_yr = group(ac_uq_id election_year cohort)
gen post_ = relative_year_bin >= 0
gen protest = post_ * treat
gen moderator = 0

* Restrict descriptives to the same estimation sample used by the baseline DiD.
quietly reghdfejl countk ///
    ib0.post_##ib0.treat##ib0.moderator wind_direction av_wind_speed, ///
    absorb(unique_small_grid_id_cohort relative_year_bin ///
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

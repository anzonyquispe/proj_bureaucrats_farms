********************************************************************************
* Descriptive table for the main rural stacked downup_ac_pop DiD sample
* Output actively referenced by main.tex: tables/descriptives_main.tex
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

* This file is written directly by specification 4 of _main_1_did.do.
* Reading it guarantees exact identity between the regression and descriptive
* samples without rerunning a costly HDFE model. asdouble keeps every decimal,
* so the distinct-value counts of the wind variables are exact.
import delimited using ///
    "${int_data}/main_downup_ac_pop_esample${sample}.csv", ///
    clear varnames(1) case(preserve) asdouble
display as text "Main specification-4 descriptive sample: " _N

* Match prov exactly: a bare "drop prov" abbreviates to province and drops it.
capture confirm variable prov, exact
if !_rc drop prov
egen prov = group(province)

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

* Write one row to texout: observations and distinct values for every
* variable, plus mean, SD, min and max for continuous variables.
capture program drop _desc_row
program define _desc_row
    syntax varname, label(string) [continuous]
    quietly count if !missing(`varlist')
    _fmt_int `r(N)'
    local Nfmt "`r(out)'"
    quietly _unique_count `varlist'
    _fmt_int `r(n)'
    local ufmt "`r(out)'"
    local meanfmt ""
    local sdfmt ""
    local minfmt ""
    local maxfmt ""
    if "`continuous'" != "" {
        quietly summarize `varlist'
        * _fmt_num is rclass, so the first call clears summarize's r().
        * Store all four statistics before formatting any of them.
        local sum_mean = r(mean)
        local sum_sd   = r(sd)
        local sum_min  = r(min)
        local sum_max  = r(max)
        _fmt_num `sum_mean'
        local meanfmt "`r(out)'"
        _fmt_num `sum_sd'
        local sdfmt "`r(out)'"
        _fmt_num `sum_min'
        local minfmt "`r(out)'"
        _fmt_num `sum_max'
        local maxfmt "`r(out)'"
    }
    file write texout "`label' & `meanfmt' & `sdfmt' & `minfmt' & `maxfmt' & `Nfmt' & `ufmt'\\" _n
end

local colsel unique_small_grid_id year month ac_uq_id prov count ///
    downup_ac_pop av_wind_speed wind_direction rice_prod_aclvl_ahigh
local contvars count downup_ac_pop av_wind_speed wind_direction rice_prod_aclvl_ahigh
* Keep only the table variables; _unique_count preserves the whole dataset.
keep `colsel'

local lab_unique_small_grid_id  "Grid"
local lab_year                  "Year"
local lab_month                 "Month"
local lab_ac_uq_id              "Assembly Constituency (AC)"
local lab_prov                  "Province"
local lab_count                 "Number of Fires"
local lab_downup_ac_pop         "Down \$>\$ Up"
local lab_av_wind_speed         "Average Wind Speed"
local lab_wind_direction        "Wind Direction"
local lab_rice_prod_aclvl_ahigh "High Rice Production"

capture file close texout
file open texout using "${tables}/descriptives_main${sample}${ster_suffix}.tex", write replace
file write texout "\begin{tabular}{lrrrrrr}" _n
file write texout "\toprule" _n
file write texout " & Mean & SD & Min & Max & Observations & Unique Obs.\\" _n
file write texout "\midrule" _n

foreach v of local colsel {
    local continuous ""
    if strpos(" `contvars' ", " `v' ") local continuous "continuous"
    _desc_row `v', label("`lab_`v''") `continuous'
}

* Fires and Down > Up on the grid-cell-month panel before stacking, where
* every rural grid-cell-month appears once. Same rural and period filters as
* _main_1_did.do; the mean of Down > Up here is the share of all grid-months
* in which smoke reaches the AC's own population.
import delimited using "${int_data}/0_master_dataset${sample}.csv", ///
    clear varnames(1) case(preserve)
keep unique_small_grid_id year month count downup_ac_pop
merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keepusing(${is_rural_var}) keep(3) nogen
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)
isid unique_small_grid_id year month
display as text "Grid-cell-month panel before stacking: " _N

file write texout "\midrule" _n
_desc_row count, label("Number of Fires (not stacked)") continuous
_desc_row downup_ac_pop, label("Down \$>\$ Up (not stacked)") continuous

file write texout "\bottomrule" _n
file write texout "\end{tabular}" _n
file close texout
display as result "Generated: ${tables}/descriptives_main${sample}${ster_suffix}.tex"

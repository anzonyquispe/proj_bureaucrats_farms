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
* samples without rerunning a costly HDFE model.
import delimited using ///
    "${int_data}/main_downup_ac_pop_esample${sample}.csv", ///
    clear varnames(1) case(preserve)
display as text "Main specification-4 descriptive sample: " _N

capture drop prov
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

local colsel unique_small_grid_id year month ac_uq_id prov count ///
    downup_ac_pop av_wind_speed wind_direction rice_prod_aclvl_ahigh
local uniquevars unique_small_grid_id year month ac_uq_id prov

local lab_unique_small_grid_id  "Grid"
local lab_year                  "Year"
local lab_month                 "Month"
local lab_ac_uq_id              "Assembly"
local lab_prov                  "Province"
local lab_count                 "Number of Fires"
local lab_downup_ac_pop         "Down \$\times\$ Up AC Pop"
local lab_av_wind_speed         "Average Wind Speed"
local lab_wind_direction        "Wind Direction"
local lab_rice_prod_aclvl_ahigh "Rice Production"

capture file close texout
file open texout using "${tables}/descriptives_main${sample}${ster_suffix}.tex", write replace
file write texout "\begin{tabular}{lrrrrrr}" _n
file write texout "\toprule" _n
file write texout " & Mean & SD & Min & Max & Observations & Unique Obs.\\\\" _n
file write texout "\midrule" _n

foreach v of local colsel {
    local meanfmt ""
    local sdfmt ""
    local minfmt ""
    local maxfmt ""
    local Nfmt ""
    local ufmt ""
    if strpos(" `uniquevars' ", " `v' ") {
        quietly _unique_count `v'
        _fmt_int `r(n)'
        local ufmt "`r(out)'"
    }
    else {
        quietly summarize `v'
        _fmt_num `r(mean)'
        local meanfmt "`r(out)'"
        _fmt_num `r(sd)'
        local sdfmt "`r(out)'"
        _fmt_num `r(min)'
        local minfmt "`r(out)'"
        _fmt_num `r(max)'
        local maxfmt "`r(out)'"
        quietly count if !missing(`v')
        _fmt_int `r(N)'
        local Nfmt "`r(out)'"
    }
    local vlabel "`lab_`v''"
    file write texout "`vlabel' & `meanfmt' & `sdfmt' & `minfmt' & `maxfmt' & `Nfmt' & `ufmt'\\\\" _n
}

file write texout "\bottomrule" _n
file write texout "\end{tabular}" _n
file close texout
display as result "Generated: ${tables}/descriptives_main${sample}${ster_suffix}.tex"

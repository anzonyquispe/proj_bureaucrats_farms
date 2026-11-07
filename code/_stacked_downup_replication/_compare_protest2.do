********************************************************************************
* Side-by-side protest estimates: keyword-rule protests (paper) vs protest2.
*
* For every protest .ster stem, reads tables/<stem>.ster (or
* tables/<stem>_keyword.ster when it exists) and tables/<stem>_protest2.ster and
* keeps each identified coefficient whose name involves treat, with its
* standard error, N, number of clusters and source file.
* Output: tables/protest2_comparison.csv (one row per stem x model x term).
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults: run from the code directory.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1"
    global ster_suffix  ""
    global code         "`c(pwd)'"
}
global tables "${code}/../../tables"

local stems ///
    _main_4_protest_5km_fe12_did_downup_rural ///
    _main_4_protest_5km_fe12_did_downup_rural_acpop ///
    _app_12_protest_5km_fe_did_rural ///
    _app_13_protest_5km_fe12_did_ricemods_rural_acpop ///
    _app_17_5km_fe12_evst_all_rural ///
    _app_18_protest_5km_fe12_did_downup_plot_rural ///
    _app_18_protest_5km_fe12_did_downup_plot_rural_acpop

tempname results
tempfile long
postfile `results' str60 stem str10 version str20 model str100 term ///
    double(b se N N_clust) str80 source using `long'
foreach stem of local stems {
    foreach version in protest protest2 {
        local file "`stem'.ster"
        * The paper files of _app_12 and _app_13 predate the current code, so
        * their keyword-rule reruns (suffix _keyword) are the baseline instead.
        capture confirm file "${tables}/`stem'_keyword.ster"
        if !_rc local file "`stem'_keyword.ster"
        if "`version'" == "protest2" local file "`stem'_protest2.ster"
        confirm file "${tables}/`file'"
        estimates clear
        estread using "${tables}/`file'"
        quietly estimates dir
        foreach model in `r(names)' {
            quietly estimates restore `model'
            matrix b = e(b)
            matrix V = e(V)
            local terms : colfullnames b
            local j = 0
            foreach term of local terms {
                local ++j
                * Base and omitted levels carry zero variance.
                if strpos("`term'", "treat") == 0 | V[`j', `j'] == 0 continue
                post `results' ("`stem'") ("`version'") ("`model'") ("`term'") ///
                    (b[1, `j']) (sqrt(V[`j', `j'])) (e(N)) (e(N_clust)) ("`file'")
            }
        }
    }
}
postclose `results'

use `long', clear
reshape wide b se N N_clust source, i(stem model term) j(version) string
order stem model term bprotest bprotest2 seprotest seprotest2 ///
    Nprotest Nprotest2 N_clustprotest N_clustprotest2 sourceprotest sourceprotest2
export delimited using "${tables}/protest2_comparison.csv", replace
display as result "Generated: ${tables}/protest2_comparison.csv (" _N " rows)"

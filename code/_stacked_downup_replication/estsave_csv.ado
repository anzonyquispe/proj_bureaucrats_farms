*! estsave_csv v1.2 - Export stored estimates and covariance matrices to CSV
program define estsave_csv
    version 14.0
    syntax namelist using/, [replace append]

    local outfile `"`using'"'
    tempfile coef_all coef_cur scalar_all scalar_cur
    local first = 1

    foreach est of local namelist {
        quietly estimates restore `est'
        matrix b = e(b)
        matrix V = e(V)
        local k = colsof(b)
        local cnames : colfullnames b

        preserve
        clear
        quietly set obs `k'
        gen strL reg = "`est'"
        gen strL var = ""
        gen double beta = .
        capture local ymean_val `"`e(ymean)'"'
        if !_rc & `"`ymean_val'"' != "" gen strL ymean = `"`ymean_val'"'
        else gen strL ymean = ""

        forvalues j = 1/`k' {
            local nm : word `j' of `cnames'
            quietly replace var = "`nm'" in `j'
            quietly replace beta = b[1, `j'] in `j'
            gen double cov`j' = .
        }
        forvalues i = 1/`k' {
            forvalues j = 1/`k' {
                quietly replace cov`j' = V[`i', `j'] in `i'
            }
        }
        quietly save `coef_cur', replace
        if `first' quietly save `coef_all', replace
        else {
            quietly use `coef_all', clear
            quietly append using `coef_cur'
            quietly save `coef_all', replace
        }
        restore

        preserve
        clear
        quietly set obs 1
        gen strL reg = "`est'"
        local escalars : e(scalars)
        foreach sc of local escalars {
            local scval = e(`sc')
            local safe = subinstr("`sc'", "-", "_", .)
            capture gen double `safe' = `scval'
            if _rc capture gen double sc_`safe' = `scval'
        }
        local emacros : e(macros)
        foreach mc of local emacros {
            capture local mcval `"`e(`mc')'"'
            if !_rc & `"`mcval'"' != "" {
                if strlen(`"`mcval'"') > 244 local mcval = substr(`"`mcval'"', 1, 244)
                local safe = subinstr("`mc'", "-", "_", .)
                capture gen strL `safe' = `"`mcval'"'
                if _rc capture gen strL mc_`safe' = `"`mcval'"'
            }
        }
        quietly save `scalar_cur', replace
        if `first' {
            quietly save `scalar_all', replace
            local first = 0
        }
        else {
            quietly use `scalar_all', clear
            quietly append using `scalar_cur'
            quietly save `scalar_all', replace
        }
        restore
    }

    local basefile = subinstr(`"`outfile'"', ".csv", "", .)
    quietly use `coef_all', clear
    order reg var beta ymean
    quietly export delimited using "`basefile'.csv", `replace' `append'
    quietly use `scalar_all', clear
    quietly export delimited using "`basefile'_scalars.csv", `replace' `append'
    display as result "Estimates exported to `basefile'.csv"
end


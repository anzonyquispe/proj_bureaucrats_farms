*! estsave_csv v1.2 - Save stored estimates to CSV for LaTeX table generation
*! Author: Generated for sa_fires project
*! Usage: estsave_csv evreg1 evreg2 ... using "filename.csv", replace

program define estsave_csv
    version 14.0
    syntax namelist using/, [replace append]

    * Parse output filename
    local outfile `"`using'"'

    * Temporary files
    tempfile coef_all coef_cur scalar_all scalar_cur

    local first = 1

    foreach est of local namelist {

        * Restore the estimate
        quietly est restore `est'

        *-----------------------------------------------------------------------
        * 1. COEFFICIENTS + VARIANCE-COVARIANCE MATRIX (WIDE FORMAT)
        *-----------------------------------------------------------------------
        matrix b = e(b)
        matrix V = e(V)
        local k = colsof(b)
        local cnames : colfullnames b

        * Get degrees of freedom for p-value calculation
        local df = e(df_r)
        if missing(`df') | `df' == 0 {
            local df = e(N) - e(rank)
        }
        if missing(`df') | `df' <= 0 {
            local df = 1000000  // Use normal approximation
        }

        preserve
        clear
        quietly set obs `k'

        * Basic columns
        gen strL reg = "`est'"
        gen strL var = ""
        gen double beta = .

        * Get ymean macro if it exists
        capture local ymean_val `"`e(ymean)'"'
        if _rc == 0 & `"`ymean_val'"' != "" {
            gen strL ymean = `"`ymean_val'"'
        }
        else {
            gen strL ymean = ""
        }

        * Fill var, beta
        forvalues j = 1/`k' {
            local nm : word `j' of `cnames'
            quietly replace var = "`nm'" in `j'
            quietly replace beta = b[1,`j'] in `j'
        }

        * Create covariance columns cov1..covk
        forvalues j = 1/`k' {
            gen double cov`j' = .
        }

        * Fill covariance matrix
        forvalues i = 1/`k' {
            forvalues j = 1/`k' {
                quietly replace cov`j' = V[`i',`j'] in `i'
            }
        }

        quietly save `coef_cur', replace

        if `first' {
            quietly save `coef_all', replace
        }
        else {
            quietly use `coef_all', clear
            quietly append using `coef_cur'
            quietly save `coef_all', replace
        }
        restore

        *-----------------------------------------------------------------------
        * 2. SCALARS + MACROS (ONE ROW PER REGRESSION)
        *-----------------------------------------------------------------------
        preserve
        clear
        quietly set obs 1

        gen strL reg = "`est'"

        * Add all scalars
        local escalars : e(scalars)
        foreach sc of local escalars {
            local scval = e(`sc')
            local safesc = subinstr("`sc'", "-", "_", .)
            capture gen double `safesc' = `scval'
            if _rc {
                capture gen double sc_`safesc' = `scval'
            }
        }

        * Add ALL macros (including FE indicators like gridfe, acfe, etc.)
        local emacros : e(macros)
        foreach mc of local emacros {
            capture local mcval `"`e(`mc')'"'
            if !_rc & `"`mcval'"' != "" {
                if strlen(`"`mcval'"') > 244 {
                    local mcval = substr(`"`mcval'"', 1, 244)
                }
                local safemc = subinstr("`mc'", "-", "_", .)
                capture gen strL `safemc' = `"`mcval'"'
                if _rc {
                    capture gen strL mc_`safemc' = `"`mcval'"'
                }
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

    *---------------------------------------------------------------------------
    * EXPORT TO CSV FILES
    *---------------------------------------------------------------------------

    * Get base filename without extension
    local basefile = subinstr(`"`outfile'"', ".csv", "", .)

    * Export coefficients + vcov (main file)
    quietly use `coef_all', clear
    order reg var beta ymean
    quietly export delimited using "`basefile'.csv", `replace' `append'
    display as text "Coefficients + VCoV saved to: `basefile'.csv"

    * Export scalars + macros summary
    quietly use `scalar_all', clear
    quietly export delimited using "`basefile'_scalars.csv", `replace' `append'
    display as text "Scalars + Macros saved to: `basefile'_scalars.csv"

    display as text ""
    display as result "All estimates exported successfully!"

end

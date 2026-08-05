*! estload_csv v1.0 - Reconstruct estimate objects exported by estsave_csv
program define estload_csv
    version 14.0
    syntax using/

    local infile `"`using'"'
    local basefile = subinstr(`"`infile'"', ".csv", "", .)
    preserve
    quietly import delimited using "`basefile'.csv", clear varnames(1)
    quietly levelsof reg, local(regs)

    foreach r of local regs {
        preserve
        quietly keep if reg == "`r'"
        local k = _N
        matrix b = J(1, `k', .)
        matrix V = J(`k', `k', .)
        local varnames ""
        forvalues i = 1/`k' {
            local vname = var[`i']
            local varnames `"`varnames' `vname'"'
            matrix b[1, `i'] = beta[`i']
            forvalues j = 1/`k' {
                matrix V[`i', `j'] = cov`j'[`i']
            }
        }
        matrix colnames b = `varnames'
        matrix rownames V = `varnames'
        matrix colnames V = `varnames'
        restore, preserve
        quietly ereturn post b V
        estimates store `r'
        display as text "Loaded estimate: `r'"
    }
    restore
end


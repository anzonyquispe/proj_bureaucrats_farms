*! estload_csv v1.0 - Load estimates from CSV files (created by estsave_csv)
*! Author: Generated for sa_fires project
*! Usage: estload_csv using "filename.csv"
*!
*! This ado file reconstructs Stata estimate objects from CSV files,
*! allowing lincom and other post-estimation commands to work.

program define estload_csv
    version 14.0
    syntax using/

    * Parse input filename
    local infile `"`using'"'

    * Get base filename without extension
    local basefile = subinstr(`"`infile'"', ".csv", "", .)

    * Read the CSV file
    preserve
    quietly import delimited using "`basefile'.csv", clear varnames(1)

    * Get list of unique regressions
    quietly levelsof reg, local(regs)

    foreach r of local regs {

        * Subset to this regression
        preserve
        quietly keep if reg == "`r'"

        * Get number of coefficients
        local k = _N

        * Create coefficient vector b
        matrix b = J(1, `k', .)

        * Create variance-covariance matrix V
        matrix V = J(`k', `k', .)

        * Get variable names for matrix labels
        local varnames ""
        forvalues i = 1/`k' {
            local vname = var[`i']
            local varnames `"`varnames' `vname'"'

            * Fill coefficient
            matrix b[1, `i'] = beta[`i']

            * Fill variance-covariance matrix row
            forvalues j = 1/`k' {
                capture local cov_val = cov`j'[`i']
                if _rc == 0 & !missing(`cov_val') {
                    matrix V[`i', `j'] = `cov_val'
                }
                else {
                    matrix V[`i', `j'] = 0
                }
            }
        }

        * Set matrix row and column names
        matrix colnames b = `varnames'
        matrix rownames V = `varnames'
        matrix colnames V = `varnames'

        restore, preserve

        * Get N from scalars file if exists
        local n_obs = .
        capture {
            preserve
            quietly import delimited using "`basefile'_scalars.csv", clear varnames(1)
            quietly keep if reg == "`r'"
            if _N > 0 {
                capture local n_obs = N[1]
            }
            restore
        }

        * Post the estimation results
        * This makes lincom and other post-estimation commands work
        quietly ereturn post b V

        * Add N if available
        if !missing(`n_obs') & `n_obs' != . {
            ereturn scalar N = `n_obs'
        }

        * Store the estimate
        estimates store `r'

        display as text "Loaded estimate: `r' (`k' coefficients)"
    }

    restore

    display as text ""
    display as result "All estimates loaded successfully from `basefile'.csv"

end

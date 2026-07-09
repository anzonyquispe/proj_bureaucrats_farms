clear all
global main = "C:\Users\Anzony\Dropbox\sa_fires\proj_bureaucrats_farms"
cd ${main}

import delimited "data_output/intermediate/poli_char_sample.csv", clear
* Example run
egen prov = group(province)

cap program drop desc_table
program define desc_table, eclass
    syntax varlist

    local k : word count `varlist'
    tempname b
    matrix `b' = J(`k',6,.)
    matrix colnames `b' = mean sd min max N unique

    local i = 1
    foreach v of varlist `varlist' {
        quietly summarize `v'
        local N = r(N)
        local mean = r(mean)
        local sd   = r(sd)
        local min  = r(min)
        local max  = r(max)

        quietly unique `v'
        local uniq = r(unique)

        matrix `b'[`i',1] = `mean'
        matrix `b'[`i',2] = `sd'
        matrix `b'[`i',3] = `min'
        matrix `b'[`i',4] = `max'
        matrix `b'[`i',5] = `N'
        matrix `b'[`i',6] = `uniq'

        local ++i
    }

    // Label rows by variable names
    matrix rownames `B' = `varlist'

    // Flatten Kx6 into 1x(K*6) so ereturn post accepts it
    // Order: mean(var1..varK) sd(var1..varK) ... unique(var1..varK)
    mata:
        B = st_matrix(st_local("B"))
        bb = vec(B)'                      // 1 x (K*6), stacks columns
        st_matrix("bb", bb)
    end

    // Build matching colnames for the flattened vector
    local cnames
    foreach stat in mean sd min max N unique {
        foreach v of varlist `varlist' {
            local cnames `cnames' `stat':`v'
        }
    }
    matrix colnames bb = `cnames'

    // Dummy V so the estimate is fully formed
    tempname V
    matrix `V' = J(colsof(bb), colsof(bb), .)

    // Post results
    ereturn post bb `V'
    ereturn local cmd "desc_table"
    ereturn matrix STATS = `B'          // the pretty Kx6 table
    ereturn local varlist "`varlist'"
end


desc_table unique_small_grid_id year month ac_uq_id prov relative_year_bin post treat countk

* Save results
estimates save descriptives.ster, replace
 
summarize unique_small_grid_id
* Save the results in a ster file
estimates save descriptives.ster, replace





cap program drop desc_table
program define desc_table, eclass
    // Usage: desc_table varlist
    syntax varlist

    // Build K x 6 matrix of stats
    local k : word count `varlist'
    tempname B
    matrix `B' = J(`k', 6, .)
    matrix colnames `B' = mean sd min max N unique

    local i = 1
    foreach v of varlist `varlist' {
        // N (non-missing)
        quietly count if !missing(`v')
        local N = r(N)

        // Unique values (prefer distinct if available; fallback to levelsof)
        capture which unique
        if (_rc == 0) {
            quietly unique `v'
            local uniq = r(unique)
        }
        else {
            quietly levelsof `v', local(__lvls)
            local uniq : word count `__lvls'
        }

        // If numeric, summarize; if string, leave mean/sd/min/max as missing
        capture confirm numeric variable `v'
        if (_rc == 0) {
            quietly summarize `v'
            matrix `B'[`i',1] = r(mean)
            matrix `B'[`i',2] = r(sd)
            matrix `B'[`i',3] = r(min)
            matrix `B'[`i',4] = r(max)
        }

        matrix `B'[`i',5] = `N'
        matrix `B'[`i',6] = `uniq'

        local ++i
    }

    // Label rows by variable names
    matrix rownames `B' = `varlist'

    // Flatten Kx6 into 1x(K*6) so ereturn post accepts it
    // Order: mean(var1..varK) sd(var1..varK) ... unique(var1..varK)
    mata:
        B = st_matrix(st_local("B"))
        bb = vec(B)'                      // 1 x (K*6), stacks columns
        st_matrix("bb", bb)
    end

    // Build matching colnames for the flattened vector
    local cnames
    foreach stat in mean sd min max N unique {
        foreach v of varlist `varlist' {
            local cnames `cnames' `stat':`v'
        }
    }
    matrix colnames bb = `cnames'

    // Dummy V so the estimate is fully formed
    tempname V
    matrix `V' = J(colsof(bb), colsof(bb), .)

    // Post results
    ereturn post bb `V'
    ereturn local cmd "desc_table"
    ereturn matrix STATS = `B'          // the pretty Kx6 table
    ereturn local varlist "`varlist'"
end

// Example usage (avoid duplicates in varlist)
desc_table unique_small_grid_id year month ac_uq_id prov relative_year_bin post treat countk

// Save as .ster
estimates save descriptives.ster, replace

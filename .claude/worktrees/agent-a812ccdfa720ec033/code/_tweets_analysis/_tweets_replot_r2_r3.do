// _tweets_replot_r2_r3.do
// Walk every r2_*.ster and r3_*.ster file in ${shell}/tex/paper/figures/, read
// did_multiplegt_dyn estimates directly from e() scalars, and produce TWO
// connected-scatter event-study plots per ster:
//   <stem>.png         original estimates with 95% CIs
//   <stem>_rotated.png same outcome with a linear pre-trend (fit on x<0
//                       via OLS no-constant) extrapolated across all periods
//                       and subtracted from each estimate -- mirrors the
//                       agregation_result() rotation used in
//                       code/_replication_rural/tools/plot_event_studies.R.
//
// Convention:
//   e(Placebo_k) / e(se_placebo_k)  -> x = -k     (k = 1..5)
//   e(Effect_k)  / e(se_effect_k)   -> x = +k     (k = 1..5)
//   omitted reference at x = 0 (beta=0, no CI)
//   CI = beta +/- 1.96 * se

clear all
set more off

local sters_dir "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms/tex/paper/figures"

display as text "Replotting r2_*/r3_* ster files in: `sters_dir'"

local n_ok   = 0
local n_fail = 0

foreach pat in "r2_*.ster" "r3_*.ster" {
    local files : dir "`sters_dir'" files "`pat'"
    local nfiles : word count `files'
    display as text _newline "=== Pattern `pat' : `nfiles' files ==="

    foreach f of local files {
        local stem = subinstr("`f'", ".ster", "", .)
        display as text _newline ">>> `stem'"

        capture estimates use "`sters_dir'/`f'"
        if _rc != 0 {
            display as error "[fail] cannot load `f' (rc=`=_rc')"
            local n_fail = `n_fail' + 1
            continue
        }

        tempfile post_tmp
        capture postclose ph_tmp
        postfile ph_tmp double(x beta se) using "`post_tmp'", replace

        local found = 0
        forvalues k = 1/5 {
            local beta_val = e(Placebo_`k')
            local se_val   = e(se_placebo_`k')
            if !missing(`beta_val') & !missing(`se_val') {
                post ph_tmp (-`k') (`beta_val') (`se_val')
                local found = `found' + 1
            }
        }
        forvalues k = 1/5 {
            local beta_val = e(Effect_`k')
            local se_val   = e(se_effect_`k')
            if !missing(`beta_val') & !missing(`se_val') {
                post ph_tmp (`k') (`beta_val') (`se_val')
                local found = `found' + 1
            }
        }
        post ph_tmp (0) (0) (0)
        postclose ph_tmp

        if `found' == 0 {
            display as error "[fail] no e(Effect_*) / e(Placebo_*) in `f'"
            local n_fail = `n_fail' + 1
            continue
        }

        use "`post_tmp'", clear
        sort x
        gen ci_lo = beta - 1.96 * se
        gen ci_hi = beta + 1.96 * se

        // -------------------------------------------------------------------
        // 1) Original event study
        // -------------------------------------------------------------------
        twoway (rcap ci_hi ci_lo x, lc(navy) lwidth(medthin)) ///
               (connected beta x, ms(O) mc(navy) lc(navy) msize(small)), ///
            xline(0, lp(dash) lc(gray)) yline(0, lp(solid) lc(red)) ///
            xtitle("Time relative to switch") ///
            ytitle("Effect on tweets") ///
            xlabel(-5(1)5) ///
            legend(off) ///
            title("`stem'", size(small)) ///
            graphregion(color(white))

        capture graph export "`sters_dir'/`stem'.png", replace width(1200)
        if _rc != 0 {
            display as error "[fail] graph export failed for `stem'"
            local n_fail = `n_fail' + 1
            continue
        }

        // -------------------------------------------------------------------
        // 2) Rotated event study: fit linear pre-trend through omitted period
        //    (x=0, beta=0) via OLS without constant on x<0, then subtract.
        // -------------------------------------------------------------------
        capture quietly regress beta x if x < 0, noconstant
        if _rc != 0 | missing(_b[x]) {
            // Pre-trend not estimable (e.g. all betas zero); skip rotation.
            display as text "  -- pre-trend not estimable; skipping rotated plot"
            local n_ok = `n_ok' + 1
            estimates clear
            clear
            continue
        }
        scalar slope = _b[x]
        gen trend       = slope * x
        gen res_b       = beta - trend
        gen rot_ci_lo   = res_b - 1.96 * se
        gen rot_ci_hi   = res_b + 1.96 * se
        // Omitted period (x=0): keep at zero (residual = 0 - 0 = 0).
        replace res_b     = 0 if x == 0
        replace rot_ci_lo = 0 if x == 0
        replace rot_ci_hi = 0 if x == 0

        twoway (rcap rot_ci_hi rot_ci_lo x, lc(maroon) lwidth(medthin)) ///
               (connected res_b x, ms(O) mc(maroon) lc(maroon) msize(small)), ///
            xline(0, lp(dash) lc(gray)) yline(0, lp(solid) lc(red)) ///
            xtitle("Time relative to switch") ///
            ytitle("Effect on tweets (rotated)") ///
            xlabel(-5(1)5) ///
            legend(off) ///
            title("`stem' (rotated)", size(small)) ///
            graphregion(color(white))

        capture graph export "`sters_dir'/`stem'_rotated.png", replace width(1200)
        if _rc != 0 {
            display as error "[fail] rotated graph export failed for `stem'"
            local n_fail = `n_fail' + 1
        }
        else {
            local n_ok = `n_ok' + 1
        }

        scalar drop _all
        estimates clear
        clear
    }
}

display as text _newline "=== DONE: `n_ok' plotted, `n_fail' failed ==="

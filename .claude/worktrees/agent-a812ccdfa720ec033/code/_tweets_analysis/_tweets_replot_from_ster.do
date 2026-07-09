// _tweets_replot_from_ster.do
// Walk every .ster file in `sters_dir`, read the did_multiplegt_dyn point
// estimates and standard errors directly from e() scalars, and produce a
// connected-scatter event-study plot per file with 95% CIs. Omitted
// reference at x=0 (beta=0, no CI).
//
// Convention (did_multiplegt_dyn stores everything as e() scalars):
//   point: e(Effect_k), e(Placebo_k)        — k post / k pre
//   SE   : e(se_effect_k), e(se_placebo_k)  — same k
//   x    : Effect_k -> +k    Placebo_k -> -k    (omitted -> 0)
//   CI   : beta ± 1.96 * se   (95% normal)

clear all
set more off

local sters_dir "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms/tex/paper/figures/tmp_figs"

display as text "Replotting from ster files in: `sters_dir'"

local files : dir "`sters_dir'" files "*.ster"
local nfiles : word count `files'
if `nfiles' == 0 {
    display as error "No .ster files found in `sters_dir'"
    exit 1
}
display as text "Found `nfiles' ster files."

local n_ok   = 0
local n_fail = 0

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
    // Placebos: k = 1..5 -> x = -k
    forvalues k = 1/5 {
        local beta_val = e(Placebo_`k')
        local se_val   = e(se_placebo_`k')
        if !missing(`beta_val') & !missing(`se_val') {
            post ph_tmp (-`k') (`beta_val') (`se_val')
            local found = `found' + 1
        }
    }
    // Effects: k = 1..5 -> x = +k
    forvalues k = 1/5 {
        local beta_val = e(Effect_`k')
        local se_val   = e(se_effect_`k')
        if !missing(`beta_val') & !missing(`se_val') {
            post ph_tmp (`k') (`beta_val') (`se_val')
            local found = `found' + 1
        }
    }
    // Omitted reference period at x = 0 (no CI).
    post ph_tmp (0) (0) (0)
    postclose ph_tmp

    if `found' == 0 {
        display as error "[fail] no e(Effect_*) or e(Placebo_*) scalars in `f'"
        local n_fail = `n_fail' + 1
        continue
    }

    use "`post_tmp'", clear
    sort x
    gen ci_lo = beta - 1.96 * se
    gen ci_hi = beta + 1.96 * se

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
        display as error "[fail] graph export failed for `stem' (rc=`=_rc')"
        local n_fail = `n_fail' + 1
    }
    else {
        local n_ok = `n_ok' + 1
    }

    estimates clear
    clear
}

display as text _newline "=== DONE: `n_ok' plotted, `n_fail' failed ==="

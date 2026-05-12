// _tweets_did_event_study.do  (rubric_2)
// Event-study (did_multiplegt_dyn) over a list of rubric_2 tweet outcomes.
// One Stata process per sbatch file; each loops through the outcomes passed in
// via the $outcome_list global and saves a .ster + .png for every successful
// run, both in ${shell}/tex/paper/figures/ (no subfolders, no mkdir).
//
// Globals expected (set by the sbatch wrapper):
//   $shell        : data root, e.g. /groups/sgulzar/sa_fires/proj_bureaucrats_farms
//   $job_name     : sbatch identifier (used only for log messages)
//   $outcome_list : space-separated outcome variables to run

clear all
set more off
set linesize 240

// Standalone defaults (interactive testing on a local Mac).
if "$shell" == "" {
    global shell        "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
}
if "$job_name" == "" {
    global job_name     "tweets_r2_test"
}
if "$outcome_list" == "" {
    global outcome_list "ar3_all"
}

global int_data  "${shell}/data_output/intermediate"
global figures   "${shell}/tex/paper/figures"

// Fail fast (and noisily) if did_multiplegt_dyn isn't on the ado path.
// Run-once fix on the cluster login node:
//   module load stata
//   stata-mp -b -e 'ssc install did_multiplegt_dyn, replace'
capture which did_multiplegt_dyn
if _rc != 0 {
    display as error "FATAL: did_multiplegt_dyn not found on the ado path."
    display as error "       sysdir personal = `c(sysdir_personal)'"
    display as error "       Install once on the login node: ssc install did_multiplegt_dyn, replace"
    exit 199
}

use "${int_data}/tweets_by_rubric2_azver.dta", clear

egen stateid       = group(STATE_UT)
egen politicianid  = group(Politician_Name)
egen monthyear     = group(year month)

local graphopts xlabel(-5(5)5, labsize(2)) yline(0, lc(red)) ///
    xline(0, lc(gray) lp(dash)) legend(off) xtitle(Time Relative to Switch)

display as text _newline "=== ${job_name}: $S_DATE $S_TIME ==="
display as text "outcomes: ${outcome_list}"

local n_ok   = 0
local n_skip = 0
local n_fail = 0

foreach outcome of global outcome_list {
    capture confirm variable `outcome'
    if _rc != 0 {
        display as error "[skip] `outcome' not in dataset"
        local n_skip = `n_skip' + 1
        continue
    }

    display as text _newline ">>> event study: `outcome'"

    capture noisily did_multiplegt_dyn `outcome' politicianid monthyear elected, ///
        effects(5) placebo(5) cluster(stateid) switchers(out) graph_off ///
        graphoptions(`graphopts' ytitle(Effect on Tweets))

    if _rc != 0 {
        display as error "[fail] did_multiplegt_dyn errored on `outcome' (rc=`=_rc')"
        local n_fail = `n_fail' + 1
        continue
    }

    capture estimates save "${figures}/`outcome'.ster", replace
    capture graph export   "${figures}/`outcome'.png",   replace width(1200)
    display as result "  -> ${figures}/`outcome'.png"
    local n_ok = `n_ok' + 1
}

display as text _newline "=== ${job_name} DONE  ok=`n_ok' skip=`n_skip' fail=`n_fail' ==="

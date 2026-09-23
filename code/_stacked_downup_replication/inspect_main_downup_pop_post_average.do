********************************************************************************
* Inspect the main downup_ac_pop event study and average its six post periods.
********************************************************************************

version 17
clear all
set more off

local repo : environment FARMS_LOCAL_REPO
if "`repo'" == "" {
    local repo "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms"
}
local code   "`repo'/code/_stacked_downup_replication"
local tables "`repo'/tables"
local logdir "`code'/logs"

capture log close postavg
log using "`logdir'/main_downup_ac_pop_post_average.log", ///
    text replace name(postavg)

adopath ++ "`code'"
estimates clear
estread using "`tables'/stacked_event_study_pop_5pre_rural.ster"
estimates restore evreg1

display as text "Main downup_ac_pop event study: evreg1"
display as text "Omitted event period: 0"
display as text "Six post-treatment periods: +1 through +6"

tempname output
file open `output' using ///
    "`tables'/main_downup_ac_pop_post_coefficients.csv", ///
    write text replace
file write `output' "relative_period,coefficient,se,pvalue,ci95_lower,ci95_upper" _n

foreach period of numlist -5/-1 1/6 {
    local category = `period' + 6
    local term "`category'.relative_year_bin_aux#1.treat"
    quietly lincom _b[`term']
    display as result ///
        "EVENT `period': b=" %12.6f r(estimate) ///
        "  SE=" %12.6f r(se) ///
        "  p=" %9.6f r(p) ///
        "  95% CI=[" %12.6f r(lb) ", " %12.6f r(ub) "]"
    file write `output' ///
        "`period'," %18.10f (r(estimate)) "," %18.10f (r(se)) "," ///
        %18.10f (r(p)) "," %18.10f (r(lb)) "," %18.10f (r(ub)) _n
}

lincom ( ///
    _b[7.relative_year_bin_aux#1.treat]  + ///
    _b[8.relative_year_bin_aux#1.treat]  + ///
    _b[9.relative_year_bin_aux#1.treat]  + ///
    _b[10.relative_year_bin_aux#1.treat] + ///
    _b[11.relative_year_bin_aux#1.treat] + ///
    _b[12.relative_year_bin_aux#1.treat] ///
    ) / 6

display as result ///
    "AVERAGE POST (+1 to +6): b=" %12.6f r(estimate) ///
    "  SE=" %12.6f r(se) ///
    "  p=" %9.6f r(p) ///
    "  95% CI=[" %12.6f r(lb) ", " %12.6f r(ub) "]"

file write `output' ///
    "average_1_to_6," %18.10f (r(estimate)) "," %18.10f (r(se)) "," ///
    %18.10f (r(p)) "," %18.10f (r(lb)) "," %18.10f (r(ub)) _n
file close `output'

log close postavg

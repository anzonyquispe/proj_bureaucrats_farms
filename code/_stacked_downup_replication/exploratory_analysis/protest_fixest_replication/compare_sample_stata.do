********************************************************************************
* Cross-software audit: run the R/fixest validation sample in Stata.
* The compact CSV is generated from the exact R estimation cache.
********************************************************************************

version 18
clear all
set more off

args sample_csv output_log
if "`sample_csv'" == "" {
    local sample_csv "C:/Users/eunic/OneDrive/Documents/protest_fixest_stata_sample.csv"
}
if "`output_log'" == "" {
    local output_log "C:/Users/eunic/OneDrive/Documents/protest_fixest_stata_comparison.log"
}

capture log close _all
log using "`output_log'", text replace
import delimited using "`sample_csv'", clear varnames(1)

reghdfe countk ///
    ib0.post##ib0.treat##ib0.downup_ac_pop ///
    wind_direction av_wind_speed, ///
    absorb(grid_cohort relativeyear_cohort province_election ///
           province_cohort#c.monthyear) ///
    vce(cluster ac_elec_yr)

lincom 1.post#1.downup_ac_pop
lincom 1.post#1.treat + 1.post#1.downup_ac_pop + ///
       1.treat#1.downup_ac_pop + 1.post#1.treat#1.downup_ac_pop
lincom 1.post#1.treat + 1.treat#1.downup_ac_pop + ///
       1.post#1.treat#1.downup_ac_pop

log close
exit, clear

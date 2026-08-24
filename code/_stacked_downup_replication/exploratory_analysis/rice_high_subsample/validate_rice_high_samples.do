********************************************************************************
* Local/cluster validation of the exploratory rice-high restriction.
********************************************************************************

version 17
clear all
set more off

if "$root" == "" {
    global root "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
    global code "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"
}
global int_data "${root}/data_output/intermediate"
global analysis_subsample "rice_high"

local files ///
    combined_dt_sample.csv ///
    combined_dt_pop_sample.csv ///
    politicians_characteristics_byprov_sample.csv ///
    stacked_data_protest5km_election_sameterm_sample.csv ///
    stacked_downup_13kmpl_sample.csv ///
    stacked_downup_neigh_sample.csv

foreach file of local files {
    import delimited using "${int_data}/`file'", clear varnames(1)
    do "${code}/exploratory_analysis/rice_high_subsample/_apply_rice_high_subsample.do"
    assert rice_prod_aclvl_ahigh == 1
    quietly count
    assert r(N) > 0
    display as result "PASS: `file' | rice-high rows=" r(N)
}

display as result "ALL RICE-HIGH SAMPLE INPUTS PASSED"

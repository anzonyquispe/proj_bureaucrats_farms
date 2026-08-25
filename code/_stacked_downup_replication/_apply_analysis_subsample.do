********************************************************************************
* Apply the production analysis-subsample selection after the stacked dataset
* and required native fields are loaded, but before any common-sample model.
*
* $analysis_subsample == ""          : retain the complete analysis sample
* $analysis_subsample == "rice_high" : retain above-median AC rice production
********************************************************************************

if "$analysis_subsample" == "rice_high" {
    capture confirm variable rice_prod_aclvl_ahigh
    if _rc {
        display as error ///
            "rice_prod_aclvl_ahigh is missing from the stacked dataset. " ///
            "Regenerate the stacked inputs from 0_master_dataset."
        exit 111
    }

    assert inlist(rice_prod_aclvl_ahigh, 0, 1)
    quietly count
    local subsample_before = r(N)
    keep if rice_prod_aclvl_ahigh == 1
    quietly count
    local subsample_after = r(N)
    if `subsample_after' == 0 {
        display as error "The rice-high restriction removed every row."
        exit 2000
    }
    display as result "ANALYSIS SAMPLE: rice_prod_aclvl_ahigh == 1"
    display as result "Rows retained: `subsample_after' of `subsample_before'"
}

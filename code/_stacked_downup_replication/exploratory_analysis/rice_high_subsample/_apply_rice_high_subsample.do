********************************************************************************
* Optional exploratory restriction: ACs with above-median rice production.
*
* Called after an analysis dataset and its required merge fields are loaded,
* but before the first regression/common-sample regression.  It is inert unless
* $analysis_subsample is "rice_high".
********************************************************************************

if "$analysis_subsample" == "rice_high" {
    capture confirm variable rice_prod_aclvl_ahigh
    if _rc {
        display as error ///
            "rice_prod_aclvl_ahigh is missing from the stacked dataset. " ///
            "Regenerate it from 0_master_dataset with the data-generation pipeline."
        exit 111
    }

    assert inlist(rice_prod_aclvl_ahigh, 0, 1)
    quietly count
    local rice_before = r(N)
    keep if rice_prod_aclvl_ahigh == 1
    quietly count
    local rice_after = r(N)
    if `rice_after' == 0 {
        display as error "The rice-high exploratory restriction removed every row."
        exit 2000
    }
    display as result "EXPLORATORY SAMPLE: rice_prod_aclvl_ahigh == 1"
    display as result "Rows retained: `rice_after' of `rice_before'"
}

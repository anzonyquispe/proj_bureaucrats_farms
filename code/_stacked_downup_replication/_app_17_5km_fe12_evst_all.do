********************************************************************************
* Canonical protest event study: exact FE3 implementation of the RA's
* _app_21_5km_allfe_same_term.do.
*
* Authoritative input: stacked_data_protest5km_election_sameterm.csv.
* Controls are pooled exactly as supplied by that stack. There is no
* control_type filter and no moderator/heterogeneity regression in this file.
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    * Standalone defaults for the five sbatch-array parameters:
    * location, sample, is_rural_var, fe_list, and ster_suffix.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "3"
    global ster_suffix  ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
    global code_shell "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
    global code_dbox  "/Users/anzony.quisperojas/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"

    if "$location" == "dbox" {
        global root "$dbox"
        global code "$code_dbox"
    }
    else {
        global root "$shell"
        global code "$code_shell"
    }
    quietly do "${code}/estsave_csv.ado"
}

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"

local protest_input ///
    "${int_data}/stacked_data_protest5km_election_sameterm${sample}.csv"
confirm file "`protest_input'"
display as text "RA same-term protest input: `protest_input'"
import delimited using "`protest_input'", clear varnames(1)

* Match the reference dofile's cohort and election-term checks.
confirm variable cohort_id
confirm variable cohort_election_year
confirm variable cohort_term_start
assert monthyear >= cohort_term_start
assert cohort_term_start <= cohort
bysort cohort_id: assert cohort_election_year == cohort_election_year[1]

capture confirm variable relative_year_bin
if _rc {
    confirm variable relative_year
    rename relative_year relative_year_bin
}
assert relative_year_bin == floor((monthyear - cohort) / 12)

* Use rice_moderators.dta as both the sample definition and authoritative source
* for the above-median rice-production indicator, exactly as in the reference.
capture drop rice_prod_aclvl_ahigh
merge m:1 unique_small_grid_id ac_uq_id using ///
    "${int_data}/rice_moderators.dta", ///
    keepusing(rice_prod_aclvl_ahigh)
keep if _merge == 3
drop _merge
assert inlist(rice_prod_aclvl_ahigh, 0, 1)

merge m:1 unique_small_grid_id using ///
    "${int_data}/ghs_grid_classification_2000.dta", ///
    keepusing(is_rural)
keep if _merge == 3
drop _merge
keep if ${is_rural_var} == 1
display as text "Observations after rice and rural filters: " _N

* The reference removes only relative year -5. It does not impose an August
* 2022 cutoff or truncate the remaining government-term event-time support.
count if relative_year_bin == -5
display as text "Observations dropped at relative_year_bin == -5: " r(N)
drop if relative_year_bin == -5

foreach v of varlist election_year yeargov {
    capture confirm numeric variable `v'
    if _rc destring `v', replace
}
recast int election_year, force
recast byte yeargov, force

egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort_id)
egen monthyearco                 = group(month year cohort_id)
egen province_cohort             = group(cohort_id province)
egen ac_elec_yr                  = group(ac_uq_id cohort_election_year cohort_id)
egen relativeyear_cohort         = group(relative_year_bin cohort_id)

* Retain grid-cohort units observed on both sides of the protest switch.
bysort unique_small_grid_id_cohort: egen byte has_pre  = max(relative_year_bin < 0)
bysort unique_small_grid_id_cohort: egen byte has_post = max(relative_year_bin >= 0)
egen byte unit_tag = tag(unique_small_grid_id_cohort)
quietly count if unit_tag
local all_units = r(N)
quietly count if unit_tag & has_pre == 1 & has_post == 1
local balanced_units = r(N)
display as text "Grid-cohort units with pre and post: `balanced_units' of `all_units'"
drop unit_tag
keep if has_pre == 1 & has_post == 1
drop has_pre has_post
display as text "Canonical protest estimation observations: " _N

quietly summarize relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin - `rmin' + 1
local base = -1 - `rmin' + 1

capture drop countk
gen countk = count * 1000
local dep_var countk
local filter1 "1"

* Selected specification from the RA's five-specification comparison.
local fe3 "unique_small_grid_id_cohort province_cohort#c.monthyear"

* Preserve the project-standard moderator structure while estimating only the
* RA's unmoderated event study. Because moderator is identically zero, the
* estimable event-time x treat coefficients are identical to the RA's RHS.
gen byte moderator = 0
* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
local moderators_list moderator

egen byte tag_ac = tag(ac_uq_id)
quietly count if tag_ac
local numacs = r(N)
drop tag_ac

est clear
local i = 1
local estimate_names ""
if trim("$fe_list") != "3" {
    display as error "Canonical protest event study requires fe_list=3."
    exit 198
}
foreach fe of numlist $fe_list {
    local fespec `fe`fe''
    display _newline as text "FE`fe': `fespec' + relativeyear_cohort"

    foreach mod of local moderators_list {
        replace moderator = `mod'
        local rhs ///
            "ib`base'.relative_year_bin_aux##ib0.treat##ib0.`mod' wind_direction av_wind_speed"

        quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & `filter1'
        local ymean = r(mean)
        quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1 & `filter1'
        local ymean2 = r(mean)
        quietly summarize `dep_var' if treat == 0 & relative_year_bin <= -1 & `filter1'
        local ra_ymean = r(mean)
        if abs(`ra_ymean' - 139.86196) > .001 {
            display as error "RA replication failed: untreated pre-mean=" ///
                `ra_ymean' ", expected 139.86196."
            exit 459
        }

        reghdfejl `dep_var' `rhs' if `filter1', ///
            absorb(`fespec' relativeyear_cohort) ///
            vce(cluster ac_elec_yr)

        * Exact replication audit against the RA's completed FE3 log. These
        * checks detect any change in the input, sample construction, FE,
        * clustering, or event-time coefficients.
        if e(N) != 67728314 {
            display as error "RA replication failed: N=" e(N) ///
                ", expected 67728314."
            exit 459
        }
        if e(N_clust) != 12096 {
            display as error "RA replication failed: clusters=" e(N_clust) ///
                ", expected 12096."
            exit 459
        }
        local audit_terms "1bn.relative_year_bin_aux#1.treat 2.relative_year_bin_aux#1.treat 3.relative_year_bin_aux#1.treat 5.relative_year_bin_aux#1.treat 6.relative_year_bin_aux#1.treat 7.relative_year_bin_aux#1.treat 8.relative_year_bin_aux#1.treat 9.relative_year_bin_aux#1.treat"
        local audit_beta "-42.01641 -8.181174 -20.40768 56.44675 164.7035 64.44406 69.70303 82.60937"
        local audit_se   "13.70218 10.15766 10.99382 10.52979 28.49049 12.78092 13.62757 19.89362"
        local audit_n : word count `audit_terms'
        forvalues a = 1/`audit_n' {
            local term : word `a' of `audit_terms'
            local expected_beta : word `a' of `audit_beta'
            local expected_se : word `a' of `audit_se'
            if abs(_b[`term'] - `expected_beta') > .001 {
                display as error "RA replication failed for event coefficient `term'."
                exit 459
            }
            if abs(_se[`term'] - `expected_se') > .001 {
                display as error "RA replication failed for event SE `term'."
                exit 459
            }
        }
        display as result "PASS: FE3 sample, coefficients, and SEs match the RA benchmark."

        estadd scalar ymean  = `ymean'
        estadd scalar ymean2 = `ymean2'
        estadd scalar ra_ymean = `ra_ymean'
        estadd scalar acq    = `numacs'
        estadd local smpl "Rural"
        estadd local fespec "FE`fe': `fespec' relativeyear_cohort"
        estadd local mod "`mod'"
        estadd local controls "pooled"

        local estname evreg`i'
        local estimate_names "`estimate_names' `estname'"
        local i = `i' + 1
        est store `estname'
    }
}

local outbase ///
    "${tables}/_app_17_5km_fe12_evst_all${sample}_rural${ster_suffix}"
estwrite `estimate_names' using "`outbase'.ster", replace
estsave_csv `estimate_names' using "`outbase'.csv", replace
confirm file "`outbase'.ster"
confirm file "`outbase'.csv"
confirm file "`outbase'_scalars.csv"
display as result "Saved canonical RA-matched FE3 protest results: `outbase'.ster and .csv"

********************************************************************************

********************************************************************************
* _app_main_did_treat_definition_rural.do
* Replicates _app_main_did_treat_definition.R - RURAL GRIDS ONLY
* Different treatment definitions for downup
********************************************************************************

********************************************************************************
* Setup - Only set globals if running standalone (not from master)
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    * Set toggles for standalone run
    global location "shell"
    global sample ""
    global is_rural_var "is_rural"
    global fe_list "1/7"
    global ster_suffix ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"

    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }
}

global int_farms "${root}/data_output/intermediate"
global table_farms "${code}/../../tables"
global figure_farms "${code}/../../figures"

********************************************************************************
* Import Data
********************************************************************************

* Getting downup_dummy & mean_brigthness
import delimited "${root}/data_output/intermediate/combined_dt_pop${sample}.csv", clear
keep if inrange(relative_monthyear, -5, 6)
display as text "Final event-study sample: relative_monthyear in [-5, 6]"

preserve
		import delimited using "${root}/data_output/intermediate/0_master_dataset${sample}.csv", ///
    clear varnames(1)
		keep ac_uq_id unique_small_grid_id downup_ac down_percent_pop downup_diff_percent_pop downwind_pop_ac_nosmall upwind_pop_ac_nosmall downup_1sd_pop year month
		tempfile dta
		save `dta'
	restore
	
	merge m:1 unique_small_grid_id month year using `dta', keep(3) nogen


* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge


* Total POP
merge m:1 ac_uq_id using "${root}/data_output/intermediate/AC_total_pop.dta" , keep(3) nogen


* Keep only rural grids
keep if ${is_rural_var} == 1

display "Observations after rural filter: " _N

* Do not drop grids that intersect more than one assembly constituency.
* merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/grids_with_more_1_ac.dta"
* drop if dpl_ac == 1
* drop _merge


* Merge rice moderators if not already present
capture confirm variable rice_area_aclvl_ahigh
if _rc {
    display "Merging rice moderators..."
    merge m:1 unique_small_grid_id ac_uq_id using "${root}/data_output/intermediate/rice_moderators.dta", nogen keep(3)
}



* Create count in thousands
capture drop countk
gen countk = count * 1000

* Filter data: year < 2022 or (year == 2022 & month <= 8)
keep if year < 2022 | (year == 2022 & month <= 8)

********************************************************************************
* Create treatment variables
********************************************************************************

* Total area
// gen total_area = downwind_pop_ac_nosmall + upwind_pop_ac_nosmall

* Difference: downwind - upwind and its one-standard-deviation threshold.
gen downup_diff = downwind_pop_ac_nosmall - upwind_pop_ac_nosmall
summarize downup_diff
local sd_val = r(sd)


// gen downup_1sd = .
// replace downup_1sd = 1 if downup_diff > `sd_val' & !missing(downup_diff)
// replace downup_1sd = 0 if downup_diff <= `sd_val' & !missing(downup_diff)

* Downwind percentage over total
gen down_percent = (downwind_pop_ac_nosmall  * 100) / total_pop_ac_nosmall

********************************************************************************
* Encode IDs
********************************************************************************

capture confirm numeric variable unique_small_grid_id
if _rc {
    encode unique_small_grid_id, gen(grid_id)
}
else {
    gen grid_id = unique_small_grid_id
}

capture confirm numeric variable ac_uq_id
if _rc {
    encode ac_uq_id, gen(ac_id)
}
else {
    gen ac_id = ac_uq_id
}

* Create cluster variable
egen cluster_acmonth = group(ac_id monthyear)


********************************************************************************
* Run Regressions
********************************************************************************

global controls av_wind_speed wind_direction

* Eq1: downup_ac_pop (exclude grid 116147 as in R code)
do "${code}/exploratory_analysis/rice_high_subsample/_apply_rice_high_subsample.do"

reghdfejl countk downup_ac_pop $controls if grid_id != 116147, ///
    absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)

gen esample = e(sample)

{
********************************************************************************
* Calculate Mean DV for each treatment definition
********************************************************************************

* Project-standard treated-group pre-treatment means and AC count.
egen tag_ac = tag(ac_id) if esample == 1
count if tag_ac == 1
local numacs = r(N)
gen relative_year_bin = floor(relative_monthyear / 12)
gen moderator = rice_prod_aclvl_ahigh
quietly summarize countk if treat == 1 & relative_year_bin <= -1 & esample == 1
local meandv = r(mean)
quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1 & esample == 1
local meandv2 = r(mean)
}

estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
est store eq1

* Eq2: downup_ac
reghdfejl countk downup_ac $controls if  esample == 1, ///
    absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
est store eq2

* Eq3: downup_1sd
reghdfejl countk downup_1sd_pop $controls if  esample == 1, ///
    absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
est store eq3

* Eq4: down_percent
reghdfejl countk down_percent_pop $controls if  esample == 1, ///
    absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
est store eq4

* Eq5: downup_diff_percent
reghdfejl countk downup_diff_percent_pop $controls if  esample == 1, ///
    absorb(grid_id ac_id#monthyear) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
est store eq5


* Eq6: down_percent
reghdfejl countk down_percent $controls if  esample == 1, ///
    absorb(grid_id#i.cohort ac_id#monthyear#i.cohort) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
est store eq6

* Eq7: X Rice
reghdfejl countk downup_ac_pop##ib0.rice_prod_aclvl_ahigh $controls if  esample == 1, ///
    absorb(grid_id#i.cohort ac_id#monthyear#i.cohort) cluster(grid_id cluster_acmonth)
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
est store eq7

********************************************************************************
* Save ster file
********************************************************************************

estwrite eq* using ///
    "${code}/../../tables/_app_6_main_did_treat_definition${sample}_rural_acpop${ster_suffix}.ster", replace

display "Ster: ${code}/../../tables/_app_6_main_did_treat_definition${sample}_rural_acpop${ster_suffix}.ster"

********************************************************************************

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

* Freeze the observation sample to specification 4 of the main population DiD.
import delimited ///
    "${root}/data_output/intermediate/main_downup_ac_pop_esample${sample}.csv", ///
    clear varnames(1)
local common_n = _N
display as text "Loaded canonical main specification-4 sample: `common_n' rows"

preserve
		import delimited using "${root}/data_output/intermediate/0_master_dataset${sample}.csv", ///
    clear varnames(1)
		keep ac_uq_id unique_small_grid_id downup_ac down_percent_pop downup_diff_percent_pop downwind_pop_ac_nosmall upwind_pop_ac_nosmall downup_1sd_pop year month
		tempfile dta
		save `dta'
	restore
	
	merge m:1 unique_small_grid_id month year using `dta', keep(master match)
	assert _merge == 3
	drop _merge


* Total POP
merge m:1 ac_uq_id using ///
    "${root}/data_output/intermediate/AC_total_pop.dta", ///
    keep(master match)
assert _merge == 3
drop _merge

assert _N == `common_n'

confirm variable rice_prod_aclvl_ahigh
assert inlist(rice_prod_aclvl_ahigh, 0, 1)
assert inlist(downup_ac, 0, 1) if !missing(downup_ac)
assert inlist(downup_1sd_pop, 0, 1) if !missing(downup_1sd_pop)



* Create count in thousands
capture drop countk
gen countk = count * 1000

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

capture drop grid_id ac_id
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

* Eq1: population Down > Up on the canonical main sample.
reghdfejl countk downup_ac_pop $controls, ///
    absorb(grid_id#cohort ac_id#monthyear#cohort) cluster(grid_id cluster_acmonth)
assert e(N) == `common_n'
gen byte esample = e(sample)

{
********************************************************************************
* Calculate Mean DV for each treatment definition
********************************************************************************

* Project-standard treated-group pre-treatment means and AC count.
egen tag_ac = tag(ac_id) if esample == 1
count if tag_ac == 1
local numacs = r(N)
gen moderator = rice_prod_aclvl_ahigh
quietly summarize countk if treat == 1 & relative_monthyear <= -1 & esample == 1
local meandv1 = r(mean)
quietly summarize countk if treat == 1 & relative_monthyear <= -1 & moderator == 1 & esample == 1
local meandv1_mod = r(mean)

* Binary alternatives use their own ever-treated definition. The reported
* outcome mean is among grids that are ever treated while treatment is zero.
bysort unique_small_grid_id: egen byte ever_downup_ac = max(downup_ac)
quietly summarize countk if ever_downup_ac == 1 & downup_ac == 0 & esample == 1
local meandv2 = r(mean)
quietly summarize countk if ever_downup_ac == 1 & downup_ac == 0 & moderator == 1 & esample == 1
local meandv2_mod = r(mean)

bysort unique_small_grid_id: egen byte ever_downup_1sd_pop = max(downup_1sd_pop)
quietly summarize countk if ever_downup_1sd_pop == 1 & downup_1sd_pop == 0 & esample == 1
local meandv3 = r(mean)
quietly summarize countk if ever_downup_1sd_pop == 1 & downup_1sd_pop == 0 & moderator == 1 & esample == 1
local meandv3_mod = r(mean)
}

estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv1'
estadd scalar ymean2 = `meandv1_mod'
estadd scalar acq = `numacs'
est store eq1

* Eq2: downup_ac
reghdfejl countk downup_ac $controls if  esample == 1, ///
    absorb(grid_id#cohort ac_id#monthyear#cohort) cluster(grid_id cluster_acmonth)
assert e(N) == `common_n'
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv2'
estadd scalar ymean2 = `meandv2_mod'
estadd scalar acq = `numacs'
est store eq2

* Eq3: downup_1sd
reghdfejl countk downup_1sd_pop $controls if  esample == 1, ///
    absorb(grid_id#cohort ac_id#monthyear#cohort) cluster(grid_id cluster_acmonth)
assert e(N) == `common_n'
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv3'
estadd scalar ymean2 = `meandv3_mod'
estadd scalar acq = `numacs'
est store eq3

* Eq4: down_percent
reghdfejl countk down_percent_pop $controls if  esample == 1, ///
    absorb(grid_id#cohort ac_id#monthyear#cohort) cluster(grid_id cluster_acmonth)
assert e(N) == `common_n'
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv1'
estadd scalar ymean2 = `meandv1_mod'
estadd scalar acq = `numacs'
est store eq4

* Eq5: downup_diff_percent
reghdfejl countk downup_diff_percent_pop $controls if  esample == 1, ///
    absorb(grid_id#cohort ac_id#monthyear#cohort) cluster(grid_id cluster_acmonth)
assert e(N) == `common_n'
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv1'
estadd scalar ymean2 = `meandv1_mod'
estadd scalar acq = `numacs'
est store eq5


* Eq6: down_percent
reghdfejl countk down_percent $controls if  esample == 1, ///
    absorb(grid_id#cohort ac_id#monthyear#cohort) cluster(grid_id cluster_acmonth)
assert e(N) == `common_n'
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv1'
estadd scalar ymean2 = `meandv1_mod'
estadd scalar acq = `numacs'
est store eq6

* Eq7: X Rice
reghdfejl countk downup_ac_pop##ib0.rice_prod_aclvl_ahigh $controls if  esample == 1, ///
    absorb(grid_id#cohort ac_id#monthyear#cohort) cluster(grid_id cluster_acmonth)
assert e(N) == `common_n'
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv1'
estadd scalar ymean2 = `meandv1_mod'
estadd scalar acq = `numacs'
est store eq7

********************************************************************************
* Save ster file
********************************************************************************

estwrite eq* using ///
    "${code}/../../tables/_app_6_main_did_treat_definition${sample}_rural_acpop${ster_suffix}.ster", replace

display "Ster: ${code}/../../tables/_app_6_main_did_treat_definition${sample}_rural_acpop${ster_suffix}.ster"

********************************************************************************

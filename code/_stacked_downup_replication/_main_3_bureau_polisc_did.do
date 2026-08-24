********************************************************************************
* _main_bureau_polisc_did_rural.do
* Replicates analysis from _main_bureau_polisc_did.R - RURAL GRIDS ONLY
* Generates DiD table with bureaucrat and politician downup treatments
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
    global fe_list "1/4"
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
		keep ac_uq_id unique_small_grid_id year month downup_dummy distr_id mean_brightness

		tempfile dta
		save `dta'
	restore
	
	merge m:1 unique_small_grid_id month year using `dta', keep(3) nogen



* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge

* Keep only rural grids
keep if ${is_rural_var} == 1

display "Observations after rural filter: " _N


confirm variable rice_prod_aclvl_ahigh
assert inlist(rice_prod_aclvl_ahigh, 0, 1)

* Create count in thousands
capture drop countk
gen countk = count * 1000

* Filter data: year < 2022 or (year == 2022 & month <= 8)
keep if year < 2022 | (year == 2022 & month <= 8)

* Sort data
sort unique_small_grid_id monthyear

********************************************************************************
* Create interaction variable
********************************************************************************

gen downup_interaction = downup_ac_pop * downup_dummy

********************************************************************************
* Encode string IDs if necessary
********************************************************************************

* Check if variables need encoding
capture confirm numeric variable unique_small_grid_id
if _rc {
    encode unique_small_grid_id, gen(grid_id)
}
else {
    gen grid_id = unique_small_grid_id
}

capture confirm numeric variable distr_id
if _rc {
    encode distr_id, gen(district_id)
}
else {
    gen district_id = distr_id
}

capture confirm numeric variable ac_uq_id
if _rc {
    encode ac_uq_id, gen(assembly_id)
}
else {
    gen assembly_id = ac_uq_id
}

capture confirm numeric variable ac_uq_id
if _rc {
    encode ac_uq_id, gen(ac_id)
}
else {
    gen ac_id = ac_uq_id
}

* Project-standard event-time and moderator variables.
gen relative_year_bin = floor(relative_monthyear / 12)
gen moderator = downup_dummy
do "${code}/exploratory_analysis/rice_high_subsample/_apply_rice_high_subsample.do"

********************************************************************************
* DiD Regressions
********************************************************************************

* FE
global setfe ac_id#cohort ac_id#monthyear#cohort

* Controls
global controls av_wind_speed wind_direction

* Cluster variables (stacked: interact with cohort)
global cluster unique_small_grid_id#cohort district_id#cohort#monthyear


********************************************************************************
* Anchor every column and every footer statistic to the final specification.
*
* Run the final grid x cohort + district x month-year x cohort regression first.
* This is the specification that previously dropped an additional 240 rows.
********************************************************************************

quietly reghdfejl countk downup_dummy downup_ac_pop downup_interaction $controls, ///
    absorb(grid_id#cohort district_id#monthyear#cohort) ///
    cluster($cluster)
gen byte common_sample = e(sample)
quietly count if common_sample
local common_n = r(N)
assert `common_n' > 0
keep if common_sample
drop common_sample

* All table statistics are now calculated on the anchored estimation sample.
egen tag_assembly = tag(assembly_id)
quietly count if tag_assembly == 1
local numacs = r(N)

egen tag_district = tag(district_id)
quietly count if tag_district == 1
local numdist = r(N)

quietly summarize countk if treat == 1 & relative_year_bin <= -1
local meandv = r(mean)
quietly summarize countk if treat == 1 & relative_year_bin <= -1 & moderator == 1
local meandv2 = r(mean)

display as text "Anchored common sample: `common_n' observations"
display as text "Anchored AC count: `numacs'"
display as text "Anchored district count: `numdist'"
display as text "Anchored treated pre-period mean: `meandv'"

* Specification 1: AC x cohort + MonthYear x cohort FE
reghdfejl countk downup_dummy downup_ac_pop downup_interaction $controls, ///
    absorb(assembly_id#cohort monthyear#cohort) ///
    cluster($cluster)
assert e(N) == `common_n'
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
estadd scalar nacs = `numacs'
estadd scalar ndists = `numdist'
estadd local monthyearfe "Y"
estadd local acfe "Y"
estadd local acmonthfe "N"
estadd local distmonthfe "N"
estadd local gridfe "N"
estimates store eq1

* Specification 2: Grid x cohort + MonthYear x cohort FE
reghdfejl countk downup_dummy downup_ac_pop downup_interaction $controls, ///
    absorb(grid_id#cohort monthyear#cohort) ///
    cluster($cluster)
assert e(N) == `common_n'
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
estadd scalar nacs = `numacs'
estadd scalar ndists = `numdist'
estadd local monthyearfe "Y"
estadd local acfe "N"
estadd local acmonthfe "N"
estadd local distmonthfe "N"
estadd local gridfe "Y"
estimates store eq2

* Specification 3: Grid x cohort + AC x MonthYear x cohort FE
reghdfejl countk downup_dummy downup_ac_pop downup_interaction $controls, ///
    absorb(grid_id#cohort assembly_id#monthyear#cohort) ///
    cluster($cluster)
assert e(N) == `common_n'
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
estadd scalar nacs = `numacs'
estadd scalar ndists = `numdist'
estadd local monthyearfe "N"
estadd local acfe "N"
estadd local acmonthfe "Y"
estadd local distmonthfe "N"
estadd local gridfe "Y"
estimates store eq3

* Specification 4: Grid x cohort + District x MonthYear x cohort FE
reghdfejl countk downup_dummy downup_ac_pop downup_interaction $controls, ///
    absorb(grid_id#cohort district_id#monthyear#cohort) ///
    cluster($cluster)
assert e(N) == `common_n'
estadd scalar ymean = `meandv'
estadd scalar ymean2 = `meandv2'
estadd scalar acq = `numacs'
estadd scalar nacs = `numacs'
estadd scalar ndists = `numdist'
estadd local monthyearfe "N"
estadd local acfe "N"
estadd local acmonthfe "N"
estadd local distmonthfe "Y"
estadd local gridfe "Y"
estimates store eq4


********************************************************************************
* Save estimates
********************************************************************************

estwrite eq1 eq2 eq3 eq4 using ///
    "${table_farms}/_main_3_bureau_polisc_did${sample}_rural_stacked${ster_suffix}.ster", replace

display "Estimates saved to: ${table_farms}/_main_3_bureau_polisc_did${sample}_rural_stacked${ster_suffix}.ster"

********************************************************************************

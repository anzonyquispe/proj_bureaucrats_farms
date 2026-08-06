********************************************************************************
* _app_main_did_downup_area_ac_dv_rural.do
* Replicates _app_main_did_downup_area_ac_dv.R - RURAL GRIDS ONLY
* Different dependent variables: Any Fire, Log Fires, Mean Brightness
********************************************************************************

********************************************************************************
* Setup - Only set globals if running standalone (not from master)
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    global location "shell"
    global sample ""
    global is_rural_var "is_rural"
    global fe_list "1/3"
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

cd "${root}"
global int_farms "${root}/data_output/intermediate"
global table_farms "${code}/../../tables"
global figure_farms "${code}/../../figures"
********************************************************************************
* Import Data
********************************************************************************

* The new stack is CSV and already retains mean_brightness.
import delimited "${root}/data_output/intermediate/combined_dt_pop${sample}.csv", clear


* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge

* Keep only rural grids
keep if ${is_rural_var} == 1

display "Observations after rural filter: " _N

* Do not drop grids that intersect more than one assembly constituency.
* merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/grids_with_more_1_ac.dta"
* drop if dpl_ac == 1
* drop _merge

* Create count in thousands
capture drop countk
gen countk = count * 1000

* Filter data: year < 2022 or (year == 2022 & month <= 8)
keep if year < 2022 | (year == 2022 & month <= 8)

********************************************************************************
* Create dependent variables
********************************************************************************

* Any fire (binary)
gen anyfire = (countk > 0)

* Log fires
gen logfire = ln(count + 1)

* Mean brightness - replace missing with 0
replace mean_brightness = 0 if missing(mean_brightness)

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



* Count unique ACs
egen tag_ac = tag(ac_id)
count if tag_ac == 1
local numacs = r(N)

********************************************************************************
* Project-standard treated-group pre-treatment means for each dependent variable.
********************************************************************************
gen relative_year_bin = floor(relative_monthyear / 12)
gen moderator = 0
quietly summarize anyfire if treat == 1 & relative_year_bin <= -1
local meandv1 = r(mean)
quietly summarize anyfire if treat == 1 & relative_year_bin <= -1 & moderator == 1
local meandv1_mod = r(mean)
quietly summarize logfire if treat == 1 & relative_year_bin <= -1
local meandv2 = r(mean)
quietly summarize logfire if treat == 1 & relative_year_bin <= -1 & moderator == 1
local meandv2_mod = r(mean)
quietly summarize mean_brightness if treat == 1 & relative_year_bin <= -1
local meandv3 = r(mean)
quietly summarize mean_brightness if treat == 1 & relative_year_bin <= -1 & moderator == 1
local meandv3_mod = r(mean)

********************************************************************************
* Run Regressions
********************************************************************************

* FE
global setfe grid_id#cohort ac_id#monthyear#cohort

* Controls
global controls av_wind_speed wind_direction

* Cluster variables
global cluster ac_uq_id#cohort#monthyear unique_small_grid_id#cohort



* Eq1: Any Fire
reghdfejl anyfire downup_ac_pop $controls , ///
    absorb($setfe ) cluster($cluster )
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv1'
estadd scalar ymean2 = `meandv1_mod'
estadd scalar acq = `numacs'
est store eq1

* Eq2: Log Fires
reghdfejl logfire downup_ac_pop $controls , ///
    absorb($setfe ) cluster($cluster )
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv2'
estadd scalar ymean2 = `meandv2_mod'
estadd scalar acq = `numacs'
est store eq2

* Eq3: Mean Brightness
reghdfejl mean_brightness downup_ac_pop $controls , ///
    absorb($setfe ) cluster($cluster )
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv3'
estadd scalar ymean2 = `meandv3_mod'
estadd scalar acq = `numacs'
est store eq3

********************************************************************************
* Save ster file
********************************************************************************

estwrite eq* using ///
    "${code}/../../tables/_app_7_main_did_downup_area_ac_dv${sample}_rural_stacked${ster_suffix}.ster", replace

display "Ster: ${code}/../../tables/_app_7_main_did_downup_area_ac_dv${sample}_rural_stacked${ster_suffix}.ster"

********************************************************************************

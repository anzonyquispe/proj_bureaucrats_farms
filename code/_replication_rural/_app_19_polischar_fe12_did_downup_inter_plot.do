********************************************************************************
* _app_19_polischar_fe12_did_downup_inter_plot_rural.do
* Politician characteristics DiD with downup interaction for plotting - RURAL GRIDS ONLY
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

*-------------------------------------------------------------------------------
*						Importing Data
*-------------------------------------------------------------------------------

// Importing data from csv
import delimited using "${root}/data_output/intermediate/politicians_characteristics${sample}.csv", ///
    clear varnames(1)

merge m:1 unique_small_grid_id ac_uq_id using  "${root}/data_output/intermediate/rice_moderators.dta"
keep if _merge == 3

* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge

* Keep only rural grids
keep if is_rural == 1

display "Observations after rural filter: " _N

* Drop grids with more than 1 ac
merge m:1 unique_small_grid_id using "data_output/intermediate/grids_with_more_1_ac.dta"
drop if dpl_ac ==1
drop _merge

// Date
gen date_ym = ym(year,month)

// Generation of Fixed Effects
egen unique_small_grid_id_cohort = group(unique_small_grid_id cohort)
egen monthyearco = group(month year cohort)
egen ac_elec_yr = group(ac_uq_id election_year cohort)
egen province_cohort = group(cohort province)

// Government year
bys ac_uq_id election_year: egen min_monthyear = min(date_ym)
gen gov_year = date_ym - min_monthyear
replace gov_year = gov_year / 12
// g yeargov = int(gov_year + 1)


// Generation of Relative Years
sum relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin -  `rmin' + 1
local base = -1 - `rmin' +1
dis `base'
g post_ = (relative_year_bin>=0)

// Generating Ever treated cells
bys unique_small_grid_id: egen TREAT_down = max(downup_ac)
gen moderator = 0

*-------------------------------------
* 1. Dep var and RHS
*-------------------------------------
gen countk = count*1000
local dep_var countk

*-------------------------------------
* 2. Set of FE
*-------------------------------------

local rhs "ib0.post_##ib0.treat##ib0.downup_ac wind_direction av_wind_speed"

* FE specifications
local fe12 "unique_small_grid_id_cohort province_cohort#election_year province_cohort#c.monthyear "

* Statistics
quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1
local ymean_fmt = string(r(mean), "%9.3f")
unique ac_uq_id
local numacs = r(unique)

********************************************************************************
* Run Regressions
********************************************************************************

reghdfejl `dep_var' `rhs', absorb(`fe12') cluster(ac_area_tr)
est store evreg1 
  
estwrite evreg* using "${root}/tex/paper/tables/_app_19_polischar_fe12_did_downup_inter_plot${sample}_rural.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_19_polischar_fe12_did_downup_inter_plot${sample}_rural.ster"

********************************************************************************


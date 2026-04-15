********************************************************************************
* _app_19_polischar_did_downup_inter_plot_rural.do
* Politician characteristics DiD with downup interaction - RURAL GRIDS ONLY
* Loops over 32 fixed-effects specifications.
* No moderator loop: the downup_ac interaction is the core spec, not a swappable
* moderator (moderator heterogeneity is deferred until FE selection is done).
********************************************************************************

********************************************************************************
* Setup - Only set globals if running standalone (not from master)
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    * Defaults for standalone runs. When launched from an sbatch array these
    * globals are set by the caller and this whole block is skipped.
    * Five parameters are expected to be set by the sbatch array:
    *   location     : "shell" | "dbox"
    *   sample       : ""      | "_sample"
    *   is_rural_var : "is_rural_area" | "is_rural_farzad"
    *   fe_list      : any Stata numlist of FE indices (e.g. "1/32", "12 13 19")
    *   ster_suffix  : suffix appended to the output ster filename (default "")
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural_area"
    global fe_list      "1/32"
    global ster_suffix  ""

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
*                       Importing Data
*-------------------------------------------------------------------------------

// Importing data from csv
import delimited using "${root}/data_output/intermediate/politicians_characteristics${sample}.csv", ///
    clear varnames(1)

merge m:1 unique_small_grid_id ac_uq_id using  "${root}/data_output/intermediate/rice_moderators.dta"
keep if _merge == 3
drop _merge

* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural_area is_rural_farzad)
keep if _merge == 3
drop _merge

* Keep only rural grids (variable chosen via ${is_rural_var})
keep if ${is_rural_var} == 1

display "Observations after rural filter: " _N

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
g yeargov = int(gov_year + 1)

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
local rhs "ib0.post_##ib0.treat##ib0.downup_ac wind_direction av_wind_speed"

*-------------------------------------
* 2. Define 32 FE specifications
*-------------------------------------
local fe1  "unique_small_grid_id_cohort "
local fe2  "unique_small_grid_id_cohort  monthyearco "
local fe3  "unique_small_grid_id_cohort  province_cohort#c.monthyear "
local fe4  "unique_small_grid_id_cohort  yeargov "
local fe5  "unique_small_grid_id_cohort  province_cohort#election_year "
local fe6  "unique_small_grid_id_cohort  province_cohort#election_year#yeargov "
local fe7  "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear "
local fe8  "unique_small_grid_id_cohort  monthyearco  yeargov "
local fe9  "unique_small_grid_id_cohort  monthyearco  province_cohort#election_year "
local fe10 "unique_small_grid_id_cohort  monthyearco  province_cohort#election_year#yeargov "
local fe11 "unique_small_grid_id_cohort  province_cohort#c.monthyear  yeargov "
local fe12 "unique_small_grid_id_cohort  province_cohort#c.monthyear  province_cohort#election_year "
local fe13 "unique_small_grid_id_cohort  province_cohort#c.monthyear  province_cohort#election_year#yeargov "
local fe14 "unique_small_grid_id_cohort  yeargov  province_cohort#election_year "
local fe15 "unique_small_grid_id_cohort  yeargov  province_cohort#election_year#yeargov "
local fe16 "unique_small_grid_id_cohort  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe17 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  yeargov "
local fe18 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  province_cohort#election_year "
local fe19 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  province_cohort#election_year#yeargov "
local fe20 "unique_small_grid_id_cohort  monthyearco  yeargov  province_cohort#election_year "
local fe21 "unique_small_grid_id_cohort  monthyearco  yeargov  province_cohort#election_year#yeargov "
local fe22 "unique_small_grid_id_cohort  monthyearco  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe23 "unique_small_grid_id_cohort  province_cohort#c.monthyear  yeargov  province_cohort#election_year "
local fe24 "unique_small_grid_id_cohort  province_cohort#c.monthyear  yeargov  province_cohort#election_year#yeargov "
local fe25 "unique_small_grid_id_cohort  province_cohort#c.monthyear  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe26 "unique_small_grid_id_cohort  yeargov  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe27 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  yeargov  province_cohort#election_year "
local fe28 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  yeargov  province_cohort#election_year#yeargov "
local fe29 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe30 "unique_small_grid_id_cohort  monthyearco  yeargov  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe31 "unique_small_grid_id_cohort  province_cohort#c.monthyear  yeargov  province_cohort#election_year  province_cohort#election_year#yeargov "
local fe32 "unique_small_grid_id_cohort  monthyearco  province_cohort#c.monthyear  yeargov  province_cohort#election_year  province_cohort#election_year#yeargov "

********************************************************************************
* Statistics
********************************************************************************

* Mean of dep var for treated units, pre-treatment (all)
quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1
local ymean = r(mean)

* Mean of dep var for treated units, pre-treatment, moderator == 1
quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1
local ymean2 = r(mean)

unique ac_uq_id
local numacs = r(unique)

********************************************************************************
* Loop over FE specifications
********************************************************************************

local i = 1

foreach fe of numlist $fe_list {

    * Select FE spec
    local fespec `fe`fe''

    * Run regression with clustering
    reghdfejl `dep_var' `rhs', absorb(`fespec') cluster(ac_elec_yr)

    * Accumulate scalars and labels, then store the estimate
    estadd scalar ymean  = `ymean'
    estadd scalar ymean2 = `ymean2'
    estadd scalar acq    = `numacs'
    estadd local  smpl   "Rural"
    estadd local  fespec "fe`fe'"

    est store evreg`i'

    local i = `i' + 1
    display("`i'")
}

estwrite evreg* using "${root}/tex/paper/tables/_app_19_polischar_did_downup_inter_plot${sample}_rural${ster_suffix}.ster", replace

display "Ster: ${root}/tex/paper/tables/_app_19_polischar_did_downup_inter_plot${sample}_rural${ster_suffix}.ster"

********************************************************************************

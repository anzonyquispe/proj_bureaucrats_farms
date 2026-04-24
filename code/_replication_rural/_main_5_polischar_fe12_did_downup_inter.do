********************************************************************************
* _main_5_polischar_fe12_did_downup_inter_rural.do
* Politician characteristics DiD with downup interaction - RURAL GRIDS ONLY
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
drop _merge

* Merge with rural classification
merge m:1 unique_small_grid_id using "${root}/data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge

* Keep only rural grids
keep if is_rural == 1

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
local rhs "ib0.post_##ib0.treat##ib0.moderator wind_direction av_wind_speed "



*-------------------------------------
* 2. Set of FE
*-------------------------------------

* FE specifications
local fe1 "unique_small_grid_id_cohort relative_year_bin"
local fe2 "unique_small_grid_id_cohort relative_year_bin province_cohort#election_year"
local fe3 "unique_small_grid_id_cohort relative_year_bin province_cohort#election_year province_cohort#c.monthyear "

*-------------------------------------
* 3. Define filters
*-------------------------------------
local filter1 "1"   // all sample

// Moderator variables
local moderators_list moderator downup_ac



*-------------------------------------
* 4. Loop over filters × outcomes
*-------------------------------------

local i = 1
foreach mod of local moderators_list{

	replace moderator = `mod'

	* Select filter condition
	local fcond `filter1'
	* Compute mean of dep var where untreated (pr_cl_tr==0)
	quietly summarize `dep_var' if `fcond' & treat==1 & relative_year_bin < 0
	local ymean = r(mean)

	quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & `mod' == 1
	local ymean2 = cond(r(N) == 0, string(`ymean', "%9.3f" ), string(r(mean), "%9.3f"))
	
	quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & `mod' == 0
	local ymean3 = cond(r(N) == 0, string(`ymean', "%9.3f" ), string(r(mean), "%9.3f"))

	* Count number of unique ACs in subsample
	unique ac_uq_id if `fcond'
	local numacs = r(unique)

	* Select FE spec
	forvalues feval = 1/3 {

		local fespec `fe`feval''

		* Run regression with clustering
		reghdfejl `dep_var' `rhs' if `fcond', absorb(`fespec') vce(cluster ac_elec_yr)

		* Store coefficient + SE of main var
		estadd scalar ymean `ymean'
		estadd local ymean2 "`ymean2'"
		estadd local ymean3 "`ymean3'"
		estadd scalar acq `numacs'
		estadd local gridfe "Y"
		estadd local time "Y"
        estadd local electionfe = cond(`feval' >= 2, "Y", "N")
        estadd local provtrendfe = cond(`feval' == 3, "Y", "N")
		est store evreg`i'

		local i = `i' + 1
		display("`i'")
	}
}

estwrite evreg* using "${root}/tex/paper/tables/_main_5_polischar_fe12_did_downup_inter${sample}_rural.ster", replace

display "Ster: ${root}/tex/paper/tables/_main_5_polischar_fe12_did_downup_inter${sample}_rural.ster"

********************************************************************************


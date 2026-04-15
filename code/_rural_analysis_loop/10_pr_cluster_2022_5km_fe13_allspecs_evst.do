cd "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
import delimited using "/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate/stacked_data_protest.csv", ///
    clear varnames(1)

merge m:1 unique_small_grid_id ac_uq_id using  "data_output/intermediate/rice_moderators.dta"

gen provsel = 0
replace provsel = 1 if province == "Punjab_IND" | province == "Haryana"
sum relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin -  `rmin' + 1
local base = -1 - `rmin' +1

*-------------------------------------
* 1. Dep var and RHS
*-------------------------------------
// gen countk = count*1000
local dep_var countk
local rhs "ib`base'.relative_year_bin_aux##ib0.treat##ib0.moderator wind_direction av_wind_speed"

*-------------------------------------
* 2. Define FE specifications
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

*-------------------------------------
* 3. Define filters
*-------------------------------------
local filter1 "1"   // all sample

local moderators_list moderator downup_ac rice_area_aclvl_ahigh  rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh


*-------------------------------------
* 4. Loop over filters × FEs
*-------------------------------------
gen moderator = 0
local i = 1

foreach mod of local moderators_list{
	
	replace moderator = `mod'

	foreach f of numlist 1/1 {
	
	* Select filter condition
	local fcond `filter`f''
	* Compute mean of dep var where untreated (pr_cl_tr==0)
	quietly summarize `dep_var' if `fcond' & treat==0 & relative_year_bin <= -1
	local ymean = r(mean)

	quietly summarize `dep_var' if `fcond' & treat==0 & relative_year_bin <= -1 & moderator == 0
	local ymean2 = r(mean)
	
	
	* Count number of unique ACs in subsample
	unique ac_uq_id if `fcond'
	local numacs = r(unique)
	
    foreach fe of numlist 1/1 {
        
        * Select FE spec
        local fespec `fe13'

        * Run regression with clustering
        reghdfejl `dep_var' `rhs' if `fcond', absorb(`fespec') vce(cluster ac_area_tr)

        * Store coefficient + SE of main var
        est store evreg`i'
		estadd local ymean `ymean'
		estadd local ymean2 `ymean2'
		estadd local acq `numacs'
		
		local i = `i' + 1
		display("`i'")
		}

	}
}

estwrite evreg* using  "/groups/sgulzar/sa_fires/proj_bureaucrats_farms/tex/paper/figures/10_pr_cluster_2022_5km_fe13_allspecs_evst.ster", replace

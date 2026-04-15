*-------------------------------------------------------------------------------

clear all
global dbox "C:\Users\rjbar\Dropbox\sa_fires\proj_bureaucrats_farms"
global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
//cd ${shell}

*-------------------------------------------------------------------------------


*-------------------------------------------------------------------------------
*						Importing Data
*-------------------------------------------------------------------------------

// import delimited using "data_output/intermediate/0_master_merge_data_gen.csv", ///
//     clear varnames(1)
// keep unique_small_grid_id ac_uq_id rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh
// duplicates drop
// save "data_output/intermediate/rice_moderators.dta", replace



// Importing data from csv
import delimited using "${shell}/data_output/intermediate/politicians_characteristics.csv", ///
    clear varnames(1)
	
merge m:1 unique_small_grid_id ac_uq_id using  "${shell}/data_output/intermediate/rice_moderators.dta"
keep if _merge == 3

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


*-------------------------------------
* 1. Dep var and RHS
*-------------------------------------
gen countk = count*1000
local dep_var countk
local rhs "ib`base'.relative_year_bin_aux##ib0.treat wind_direction av_wind_speed "

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
// local filter2 "moderator == 0"
// local filter3 "moderator == 1"
  
/// Define moderators
local moderators_list yeargov
*-------------------------------------
* 4. Loop over filters × FEs
*-------------------------------------
drop _merge date_ym month year count self_prof self_ass_agri prof_assets date cohort province relative_month rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh relative_year_bin min_monthyear gov_year
compress

local i = 1
foreach f of numlist 1/1 {
    
    * Select filter condition
    local fcond `filter`f''
    * Compute mean of dep var where untreated (pr_cl_tr==0)
    quietly summarize `dep_var' if `fcond' & treat==0 & relative_year_bin < 0
    local ymean = r(mean)
    
    
    * Count number of unique ACs in subsample
    unique ac_uq_id if `fcond'
    local numacs = r(unique)
    
    foreach fe of numlist 1/32 {
        
        * Select FE spec
        local fespec `fe`fe''

        * Run regression with clustering
        reghdfejl `dep_var' `rhs' if `fcond', absorb(`fespec') vce(cluster ac_elec_yr)

        * Store coefficient + SE of main var
        est store evreg`i'
        estadd local ymean `ymean'
        estadd local acq `numacs'
        
        local i = `i' + 1
        display("`i'")
    }

}



	
estwrite evreg* using  "${shell}//tex//paper//tables//8_polischar_allagain.ster", replace   


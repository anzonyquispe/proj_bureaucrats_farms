********************************************************************************
* Build action_final.dta: the AC-month panel behind the DISHA appendix tables.
*
* Collapses the grid-month merge panel to assembly constituency x month-year,
* then attaches court cases (fir_nature), DISHA meeting documents and AC
* population.
*
* Starting panel
* --------------
* This used to open data_output/intermediate/iv_tmp.dta, a Stata cache written
* by annalisa_iv_analysis.do, which lives only in Dropbox and whose generating
* block is commented out. The cache is kept as a fast path, but the recipe is
* reproduced here so the chain can be rebuilt from the canonical CSV. Set
*     global disha_rebuild "1"
* to ignore the cache and rebuild it.
*
* The commented recipe in annalisa_iv_analysis.do also applies
* ``replace count = count * 1000``. The saved iv_tmp.dta does NOT carry that:
* its count averages 0.136 with a maximum of 96, i.e. raw detections. Scaling
* here would double-apply it, because _app_disha.do builds countk itself.
* The multiplication is therefore deliberately left out.
*
* carryforward, unique and zscore were user-written commands; each has been
* replaced with base Stata so the chain runs on a bare install.
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    * Standalone defaults for the five sbatch-array parameters. The DISHA
    * tables are a single specification, so fe_list and ster_suffix are inert
    * here; they stay for consistency with the other analysis dofiles.
    global location     "shell"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1"
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
}

global int_data "${root}/data_output/intermediate"
global tables   "${code}/../../tables"

* The DISHA meeting documents sit in the shared sa_fires tree, beside the
* project rather than inside it. Override $disha_data to point elsewhere.
if "$disha_data" == "" {
    global disha_data "${root}/../sa_fires/data/DISHA/DISHA_Meetings"
}

********************************************************************************
* 1. Starting panel: the cached extract, or a rebuild from the master merge
********************************************************************************

local cache "${int_data}/iv_tmp${sample}.dta"
capture confirm file "`cache'"
local have_cache = (_rc == 0)

if `have_cache' & "$disha_rebuild" != "1" {
    use "`cache'", clear
    display as result "DISHA panel: reusing `cache'"
}
else {
    display as result "DISHA panel: rebuilding from 0_master_merge_data_gen${sample}.csv"
    import delimited using "${int_data}/0_master_merge_data_gen${sample}.csv", ///
        clear varnames(1)
    keep if year < 2022 | (year == 2022 & month <= 8)

    * Districts spanned by each AC. Formerly: unique distr_id, gen(split) by(ac_uq_id)
    bysort ac_uq_id distr_id: gen byte _first_in_district = (_n == 1)
    bysort ac_uq_id: egen split = total(_first_in_district)
    drop _first_in_district

    save "`cache'", replace
}

confirm variable count ac_uq_id distr_id district month year monthyear split

* Guard against the double-scaling described in the header.
quietly summarize count, detail
if r(max) > 1000 {
    display as error "count looks pre-scaled (max = " r(max) "); countk would be wrong."
    exit 459
}

********************************************************************************
* 2. Grid-level merges
********************************************************************************

merge m:1 unique_small_grid_id month year ///
    using "${int_data}/_6_ac_downup_grids_test.dta"
keep if _merge == 3
drop _merge

merge m:1 unique_small_grid_id ///
    using "${int_data}/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge

gen x = 1

* Fires in the same grid-month one year earlier.
preserve
    keep unique_small_grid_id count month year
    rename count count_prev_year
    replace year = year + 1
    tempfile prev_year
    save `prev_year'
restore

merge m:1 unique_small_grid_id month year using `prev_year'
drop if _merge == 2
drop _merge

gen any_fire = count > 0 & count != .
gen any_downwind = any_fire * downwind_pop_ac_nosmall
gen count_downwind = count * downwind_pop_ac_nosmall
gen downwind_downup = downwind_pop_ac_nosmall * downup_ac_pop

gen count_rural = count * is_rural
gen downwind_rural = downwind_pop_ac_nosmall * is_rural
gen count_downwind_rural = count_rural * downwind_pop_ac_nosmall
gen any_downwind_rural = any_downwind * is_rural

gen any_fire_prev_year = count_prev_year > 0 & count_prev_year != .
gen any_downwind_prev_year = any_fire_prev_year * downwind_pop_ac_nosmall
gen count_downwind_prev_year = count_prev_year * downwind_pop_ac_nosmall

gen count_rural_prev_year = count_prev_year * is_rural
gen count_downwind_rural_prev_year = count_rural_prev_year * downwind_pop_ac_nosmall
gen any_downwind_rural_prev_year = any_downwind_prev_year * is_rural
gen count_downwup_rural_prev_year = count_rural_prev_year * downup_ac_pop * is_rural

gen downwind_pop_ac_nosmall_rural = downwind_pop_ac_nosmall * is_rural
gen downup_ac_pop_rural = downup_ac_pop * is_rural

gen downwind_rice = downwind_pop_ac_nosmall * rice_prod_aclvl_ahigh
gen downwind_rice_rural = downwind_pop_ac_nosmall * rice_prod_aclvl_ahigh * is_rural

********************************************************************************
* 3. Collapse to AC x month-year
********************************************************************************

collapse (rawsum) downup_ac_pop downup_ac_pop_rural rice_prod_aclvl_ahigh ///
        count_rural count tot_grids = x is_rural downwind_pop_ac_nosmall ///
        upwind_pop_ac_nosmall count_downwind any_downwind downwind_rural ///
        downwind_downup count_downwind_rural any_downwind_rural *_prev_year ///
        downwind_pop_ac_nosmall_rural ///
    (mean) count_avg = count avg_wind_direction = wind_direction ///
        av_av_wind_speed = av_wind_speed ///
    (firstnm) wind_direction av_wind_speed split district* distr_id month year ///
        province self_profession p_name, ///
    by(ac_uq_id monthyear)

assert split != .
* Keep the ACs that sit inside a single district; the court and DISHA data are
* reported by district, so an AC spanning several cannot be matched to one.
keep if split == 1

********************************************************************************
* 4. Court cases
********************************************************************************

preserve
    collapse (rawsum) tot_grids_distr = tot_grids, by(distr_id monthyear)
    tempfile district_grids
    save `district_grids'
restore

merge m:1 distr_id monthyear using `district_grids', nogen

merge m:1 district month year using "${int_data}/fir_nature", gen(mfir)
replace fir = 0 if fir == .

********************************************************************************
* 5. DISHA meeting documents
********************************************************************************

preserve
    import delimited using "${disha_data}/documents_district_panel.csv", clear

    drop if year < 2012 | (year == 2012 & month < 9) | ///
        (year == 2022 & month > 8) | year > 2022

    * District names as spelled in the fire panel.
    replace district = "Bara Banki" if district == "Barabanki"
    replace district = "Kaimur (bhabua)" if district == "Kaimur"
    replace district = "Sri Muktsar Sahib" if district == "Muktsar"
    replace district = "Shrawasti" if district == "Shravasti"
    replace district = "Prayagraj" if district == "Allahabad"
    replace district = "Purba Champaran" if district == "East" & state == "BIHAR"
    replace district = "Kanpur Nagar" if district == "Kanpur"

    tempfile disha
    save `disha'
restore

merge m:1 district month year using `disha', gen(mdisha2)
drop if mdisha2 == 2

rename topic_primary_environment_pollut environment_pollution

* A district-month with no document is a zero, not a missing value.
foreach var of varlist number_docs* topic_primary_agriculture* environment_pollution* {
    replace `var' = 0 if `var' == .
}

gen qtr = qofd(dofm(monthyear))
format qtr %tq

replace number_docs = 0 if number_docs == .

bysort ac_uq_id qtr: egen number_docs_qtr = max(number_docs)

* A district enters the DISHA sample from its first month with any document.
gen tmp_mp = monthyear if number_docs_qtr != 0
replace tmp_mp = 30000 if tmp_mp == .
bysort district (monthyear): egen min_my = min(tmp_mp)
gen byte disha_sample = (monthyear >= min_my)

merge m:1 ac_uq_id using "${int_data}/AC_total_pop.dta"
* Drops ACs present only in the population file, and units left without an AC
* by the earlier merges.
keep if _merge == 3
drop _merge

compress
save "${int_data}/action_final${sample}.dta", replace

display as result "Generated: ${int_data}/action_final${sample}.dta"

********************************************************************************

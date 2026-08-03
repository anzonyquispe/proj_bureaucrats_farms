********************************************************************************
* Translation of app_5km_descriptive.ipynb to Stata
********************************************************************************

clear all
set more off

********************************************************************************
******************** Setting working directory *********************************

local dbox_root   "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires"
local shell_root  "/groups/sgulzar/sa_fires"
local root        "`shell_root'"
local int_farms   "`root'/proj_bureaucrats_farms/data_output/intermediate"
local table_farms "`root'/proj_bureaucrats_farms/tex/paper/tables"
local figure_farms "`root'/proj_bureaucrats_farms/tex/paper/figures"

********************************************************************************
************************** Import Data *****************************************

* 1. Read stacked protest data
import delimited using "`int_farms'/stacked_data_protest.csv", clear case(preserve)

* import delimited sanitizes names: "count.k" -> count_k (or countk),
* "legis.govyear" -> legis_govyear, etc. Standardize the count variable:
capture confirm variable countk
if _rc {
    capture rename count_k countk
}

* Left join with GHS grid classification, then keep rural only
merge m:1 unique_small_grid_id using "`int_farms'/ghs_grid_classification_2000.dta", ///
    keep(master match) nogenerate
keep if is_rural == 1

d*

* Group identifiers (equivalent to pandas groupby().ngroup())
confirm variable province

egen legis_govyear = group(province election_year)

* Fill missing fire counts with zero
* Create count in thousands if not exists
capture confirm variable countk
if _rc {
    gen countk = count * 1000
}

replace countk = 0 if missing(countk)

describe, simple

* Merge rice moderators
merge m:1 unique_small_grid_id ac_uq_id using "`int_farms'/rice_moderators.dta", ///
    keep(master match) nogenerate

* Post and treatment interaction
capture drop post
gen post = relative_year_bin >= 0 if !missing(relative_year_bin)
gen protest = post * treat

* Check Sampli
egen ac_elec_yr = group(ac_uq_id election_year cohort)

sum relative_year_bin
local rmin = r(min)
gen relative_year_bin_aux = relative_year_bin -  `rmin' + 1


qui reghdfejl countk ib0.post##ib0.treat wind_direction av_wind_speed , ///
				absorb(unique_small_grid_id_cohort relative_year_bin province_cohort#election_year province_cohort#c.monthyear) ///
				cluster(ac_area_tr)

gen sampli = e(sample)
keep if sampli == 1

********************************************************************************
********************* Descriptive statistics ***********************************

* Variables in table order (legis.govyear -> legis_govyear in Stata)
local colsel unique_small_grid_id year month ac_uq_id prov ac_area_tr ///
             cohort legis_govyear relative_year_bin protest countk ///
             rice_prod_aclvl_ahigh

* Continuous variables: report mean/sd/min/max; others: only N and unique
local contvars countk rice_prod_aclvl_ahigh protest relative_year_bin

* Readable labels
local lab_unique_small_grid_id  "Grid ID"
local lab_year                  "Year"
local lab_month                 "Month"
local lab_relative_year_bin     "Relative year"
local lab_ac_uq_id              "Assembly Constituency (AC)"
local lab_prov                  "Province"
local lab_ac_area_tr            "Protest Area"
local lab_cohort                "Cohort"
local lab_protest               "Protest"
local lab_countk                "Number of Fires"
local lab_legis_govyear         "Legislature"
local lab_rice_prod_aclvl_ahigh "High Rice production (AC level)"

* Number formatting: 3 decimals, comma thousands separator, trailing zeros trimmed
capture program drop fmt_num
program define fmt_num, rclass
    args x
    if missing(`x') {
        return local out ""
        exit
    }
    local out : display %15.3fc `x'
    local out = strtrim("`out'")
    * strip trailing zeros and a trailing decimal point (".000" -> "", ".500" -> ".5")
    while substr("`out'", -1, 1) == "0" & strpos("`out'", ".") > 0 {
        local out = substr("`out'", 1, strlen("`out'") - 1)
    }
    if substr("`out'", -1, 1) == "." {
        local out = substr("`out'", 1, strlen("`out'") - 1)
    }
    return local out "`out'"
end

capture program drop fmt_int
program define fmt_int, rclass
    args x
    if missing(`x') {
        return local out ""
        exit
    }
    local out : display %20.0fc `x'
    return local out = strtrim("`out'")
end

* --- Write .tex table ---
capture file close texout
file open texout using "`table_farms'/_protest_stacked_descriptive_stata.tex", write replace

file write texout "\begin{table}[!h]" _n
file write texout "\centering" _n
file write texout "\caption{Descriptive statistics}" _n
file write texout "\label{app_desc_10_5km_protest}" _n
file write texout "\begin{tabular}{lrrrrrr}" _n
file write texout "\toprule" _n
file write texout " & Mean & SD & Min & Max & Observations & Unique Obs.\\\\" _n
file write texout "\midrule" _n

foreach v of local colsel {

    * N (non-missing) and unique count
    quietly count if !missing(`v') 
    local Nval = r(N)
    quietly distinct `v'          // requires: ssc install distinct
    local uval = r(ndistinct)

    fmt_int `Nval'
    local Nfmt "`r(out)'"
    fmt_int `uval'
    local ufmt "`r(out)'"

    * Continuous stats only for selected variables
    local meanfmt ""
    local sdfmt   ""
    local minfmt  ""
    local maxfmt  ""
    if strpos(" `contvars' ", " `v' ") > 0 {
        quietly summarize `v' 
        fmt_num `r(mean)'
        local meanfmt "`r(out)'"
        fmt_num `r(sd)'
        local sdfmt "`r(out)'"
        fmt_num `r(min)'
        local minfmt "`r(out)'"
        fmt_num `r(max)'
        local maxfmt "`r(out)'"
    }

    local vlabel "`lab_`v''"
    file write texout "`vlabel' & `meanfmt' & `sdfmt' & `minfmt' & `maxfmt' & `Nfmt' & `ufmt'\\\\" _n
}

file write texout "\bottomrule" _n
file write texout "\end{tabular}" _n
file write texout "\end{table}" _n
file close texout

display as result "Table written to `table_farms'/_protest_stacked_descriptive_stata.tex"

********************************************************************************

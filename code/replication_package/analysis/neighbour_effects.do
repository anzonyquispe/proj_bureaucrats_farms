********************************************************************************
* Neighbour-border analysis for figures/neighbor_output.pdf
********************************************************************************

if "$root" == "" {
    global location "shell"
    global sample ""
    global is_rural_var "is_rural_area"
    global fe_list "1/3"
    global ster_suffix ""
    do "config.do"
}

import delimited "${int_data}/stacked_downup_neigh.csv", clear varnames(1)

merge m:1 unique_small_grid_id using "${int_data}/ghs_grid_classification_2000.dta", ///
    keepusing(is_rural_area is_rural_farzad)
keep if _merge == 3
drop _merge
keep if ${is_rural_var} == 1
keep if year < 2022 | (year == 2022 & month <= 8)

replace count = count * 1000
global cluster ac_uq_id#month#year unique_small_grid_id

unique ac_uq_id
local numacs = r(unique)

reghdfejl count b5.dist_q##b0.downwind_neighbours, ///
    absorb(ac_uq_id#ac_uq_id_neighbor#month#year#cohort ///
           unique_small_grid_id#cohort) ///
    cluster($cluster)
estadd scalar acq = `numacs'
estadd local smpl "Rural"
est store reg1

estwrite reg1 using "${tables}/main_figure4_neighbour${sample}_rural${ster_suffix}.ster", replace

********************************************************************************

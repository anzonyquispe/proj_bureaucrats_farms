cd "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
import delimited "data_output/intermediate/stacked_downup_neigh.csv"

merge m:1 unique_small_grid_id using "data_output/intermediate/ghs_grid_classification_2000.dta", keepusing(is_rural)
keep if _merge == 3
drop _merge


global cluster ac_uq_id#month#year unique_small_grid_id 
keep if year < 2022 | ( year == 2022 & month <=8)
replace count = count * 1000


reghdfejl count b5.dist_q##b0.downwind_neighbours, abs(ac_uq_id#ac_uq_id_neighbor#month#year#cohort unique_pair#cohort ) cluster($cluster)
est store reg1
estwrite using "tex/paper/tables/main_figure4_neighbour.ster"

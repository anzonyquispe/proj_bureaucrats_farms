cd "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"

import delimited using "data_output/intermediate/stacked_data_protest.csv", ///
    clear varnames(1)

compress
save "data_output/intermediate/stacked_data_protest.dta", replace

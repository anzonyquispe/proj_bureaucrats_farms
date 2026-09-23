version 17
set more off

args location sample is_rural_var root code
if "`sample'" == "none" local sample ""

global location "`location'"
global sample "`sample'"
global is_rural_var "`is_rural_var'"
global fe_list "1/3"
global ster_suffix ""
global root "`root'"
global code "`code'"
global python "python3"

do "config.do"
adopath ++ "${code}/tools"
quietly do "${code}/tools/estload_csv.ado"

do "${code}/generate_interaction_plots.do"
do "${code}/generate_neighbour_plot.do"
do "${code}/generate_tables.do"


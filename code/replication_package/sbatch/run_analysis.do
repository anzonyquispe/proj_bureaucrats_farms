version 17
set more off

args analysis location sample is_rural_var fe_list ster_suffix root code
if "`sample'" == "none" local sample ""
if "`ster_suffix'" == "none" local ster_suffix ""

global location "`location'"
global sample "`sample'"
global is_rural_var "`is_rural_var'"
global fe_list "`fe_list'"
global ster_suffix "`ster_suffix'"
global root "`root'"
global code "`code'"
global python "python3"

do "config.do"
adopath ++ "${code}/tools"
quietly do "${code}/tools/estsave_csv.ado"
quietly do "${code}/tools/estload_csv.ado"
display "Array analysis: `analysis'"
do "${code}/analysis/`analysis'"

version 17
set more off

args root code location sample is_rural_var fe_list
if "`sample'" == "none" local sample ""

global root "`root'"
global code "`code'"
global python "python3"
global location "`location'"
global sample "`sample'"
global is_rural_var "`is_rural_var'"
global fe_list "`fe_list'"
global ster_suffix ""

do "${code}/master.do"


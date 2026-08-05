********************************************************************************
* Argument bridge used by _master_replication.sbatch
********************************************************************************

version 17
set more off

args root code location sample is_rural_var fe_list ster_suffix

if "`sample'" == "none" local sample ""
if "`ster_suffix'" == "none" local ster_suffix ""

global root "`root'"
global code "`code'"
global location "`location'"
global sample "`sample'"
global is_rural_var "`is_rural_var'"
global fe_list "`fe_list'"
global ster_suffix "`ster_suffix'"

do "${code}/_master_replication.do"

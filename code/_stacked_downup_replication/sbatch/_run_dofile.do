********************************************************************************
* Argument bridge: one invocation runs exactly one result-generating dofile.
********************************************************************************

version 17
set more off

args dofile root code location sample is_rural_var fe_list ster_suffix ///
    downup_var stacked_file did_output

if "`sample'" == "none" local sample ""
if "`ster_suffix'" == "none" local ster_suffix ""
if "`downup_var'" == "none" local downup_var ""
if "`stacked_file'" == "none" local stacked_file ""
if "`did_output'" == "none" local did_output ""

global root          "`root'"
global code          "`code'"
global location      "`location'"
global sample        "`sample'"
global is_rural_var  "`is_rural_var'"
global fe_list       "`fe_list'"
global ster_suffix   "`ster_suffix'"
global downup_var    "`downup_var'"
global stacked_file  "`stacked_file'"
global did_output    "`did_output'"

global int_data    "${root}/data_output/intermediate"
global int_farms   "${int_data}"
global tables      "${root}/tex/paper/tables"
global table_farms "${tables}"
global figures     "${root}/tex/paper/figures"
global figure_farms "${figures}"

capture mkdir "${root}/tex"
capture mkdir "${root}/tex/paper"
capture mkdir "${tables}"
capture mkdir "${figures}"
capture mkdir "${code}/logs"

adopath ++ "${code}"
capture noisily do "${code}/estsave_csv.ado"
capture noisily do "${code}/estload_csv.ado"

display "============================================================"
display "Independent dofile job: `dofile'"
display "Data/output root: ${root}"
display "Code root: ${code}"
display "Sample: ${sample}; rural: ${is_rural_var}; FE: ${fe_list}"
display "Suffix: ${ster_suffix}; moderator: ${downup_var}"
display "============================================================"

do "${code}/`dofile'"

display as result "COMPLETED: `dofile' at $S_DATE $S_TIME"


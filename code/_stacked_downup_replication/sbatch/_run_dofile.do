********************************************************************************
* Environment bridge: one invocation runs exactly one result-generating dofile.
********************************************************************************

version 17
set more off

local dofile        : environment FARMS_DOFILE
local root          : environment FARMS_ROOT
local code          : environment FARMS_CODE
local location      : environment FARMS_LOCATION
local sample        : environment FARMS_SAMPLE
local is_rural_var  : environment FARMS_RURAL_VAR
local fe_list       : environment FARMS_FE_LIST
local ster_suffix   : environment FARMS_STER_SUFFIX
local downup_var    : environment FARMS_DOWNUP_VAR
local stacked_file  : environment FARMS_STACKED_FILE
local did_output    : environment FARMS_DID_OUTPUT
local control_samples : environment FARMS_CONTROL_SAMPLES
local analysis_subsample : environment FARMS_ANALYSIS_SUBSAMPLE
local processors    : environment FARMS_CPUS

if "`processors'" == "" local processors "1"
set processors `processors'

if "`dofile'" == "" {
    display as error "FARMS_DOFILE is empty; use sbatch/run_dofile.sbatch."
    exit 198
}
if "`root'" == "" {
    display as error "FARMS_ROOT is empty; use sbatch/run_dofile.sbatch."
    exit 198
}
if "`code'" == "" {
    display as error "FARMS_CODE is empty; use sbatch/run_dofile.sbatch."
    exit 198
}

if "`sample'" == "none" local sample ""
if "`ster_suffix'" == "none" local ster_suffix ""
if "`downup_var'" == "none" local downup_var ""
if "`stacked_file'" == "none" local stacked_file ""
if "`did_output'" == "none" local did_output ""
if "`control_samples'" == "all" local control_samples ""
if "`analysis_subsample'" == "all" local analysis_subsample ""

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
global control_samples "`control_samples'"
global analysis_subsample "`analysis_subsample'"

global int_data    "${root}/data_output/intermediate"
global int_farms   "${int_data}"
global tables      "${code}/../../tables"
global table_farms "${tables}"
global figures     "${code}/../../figures"
global figure_farms "${figures}"

capture mkdir "${tables}"
capture mkdir "${figures}"
capture mkdir "${code}/logs"

adopath ++ "${code}"
capture noisily do "${code}/estsave_csv.ado"
capture noisily do "${code}/estload_csv.ado"

display "============================================================"
display "Independent dofile job: `dofile'"
display "Data root: ${root}"
display "Tables output: ${tables}"
display "Figures output: ${figures}"
display "Code root: ${code}"
display "Sample: ${sample}; rural: ${is_rural_var}; FE: ${fe_list}"
display "Suffix: ${ster_suffix}; moderator: ${downup_var}"
display "Control samples: ${control_samples}"
display "Analysis subsample: ${analysis_subsample}"
display "Stata processors: " c(processors)
display "============================================================"

do "${code}/`dofile'"

display as result "COMPLETED: `dofile' at $S_DATE $S_TIME"

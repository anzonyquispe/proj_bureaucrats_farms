********************************************************************************
* Local end-to-end smoke test using only *_sample analysis inputs.
********************************************************************************

version 17
clear all
set more off

global location     "dbox"
global sample       "_sample"
global is_rural_var "is_rural"
global fe_list      "1/4"
global ster_suffix  ""

global root "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
global code "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"

* The cluster uses reghdfejl. The local Stata installation has reghdfe but not
* the Julia-backed jl bridge, so alias only this smoke test to standard reghdfe.
capture program drop reghdfejl
program define reghdfejl, eclass
    reghdfe `0'
end

display as text "Running complete local sample replication"
display as text "Data root: ${root}"
display as text "Code root: ${code}"
display as text "Sample suffix: ${sample}"

do "${code}/_master_replication.do"

display as result "LOCAL SAMPLE REPLICATION COMPLETED"

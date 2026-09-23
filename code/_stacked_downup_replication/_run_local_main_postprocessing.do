********************************************************************************
* Environment-driven local post-processing bridge.
* FARMS_LOCAL_STAGE must be export, tables, or interactions. The launcher runs the
* export first, then runs tables and interaction figures in parallel with the
* four R event-study/HonestDiD processes.
********************************************************************************

version 17
clear all
set more off

local repo        : environment FARMS_LOCAL_REPO
local data_root   : environment FARMS_LOCAL_DATA_ROOT
local sample      : environment FARMS_LOCAL_SAMPLE
local suffix      : environment FARMS_LOCAL_SUFFIX
local stage       : environment FARMS_LOCAL_STAGE

if "`repo'" == "" {
    display as error "FARMS_LOCAL_REPO is required."
    exit 198
}
if "`data_root'" == "" local data_root "`repo'"
if "`sample'" == "none" local sample ""
if "`suffix'" == "none" local suffix ""
if !inlist("`stage'", "export", "tables", "interactions") {
    display as error "FARMS_LOCAL_STAGE must be export, tables, or interactions."
    exit 198
}

global location "dbox"
global root "`data_root'"
global repo "`repo'"
global code "${repo}/code/_stacked_downup_replication"
global tables "${repo}/tables"
global figures "${repo}/figures"
global sample "`sample'"
global ster_suffix "`suffix'"
global is_rural_var "is_rural"
global fe_list "1"
global production_only "1"

capture mkdir "${tables}"
capture mkdir "${figures}"
capture mkdir "${code}/logs"
adopath ++ "${code}"

capture log close _all
log using "${code}/logs/local_main_`stage'${sample}${ster_suffix}.stata.log", ///
    replace text name(mainpost)

display as text "Local stage: `stage'"
display as text "Sample suffix: ${sample}"
display as text "Output suffix: ${ster_suffix}"

if "`stage'" == "export" {
    do "${code}/_export_event_study_csv.do"
}
else if "`stage'" == "tables" {
    do "${code}/_generate_all_tables.do"
    do "${code}/_generate_interaction_plots.do"
}
else {
    do "${code}/_generate_interaction_plots.do"
}

display as result "LOCAL MAIN POST-PROCESSING STAGE COMPLETED: `stage'"
log close mainpost

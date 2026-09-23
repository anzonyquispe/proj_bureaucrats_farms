********************************************************************************
* Local-only export of all cohort-event-time event-study STER files to CSV.
* No regression or analysis dataset is loaded.
********************************************************************************
version 17
clear all
set more off

global repo "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms"
global code "${repo}/code/_stacked_downup_replication"
global tables "${repo}/tables/exploratory_analysis/cohort_eventtime_fe_sweep"

capture program drop estsave_csv
quietly do "${code}/estsave_csv.ado"

foreach analysis in politician protest {
    forvalues fe = 1/32 {
        local tag : display %02.0f `fe'
        local tag = strtrim("`tag'")
        if "`analysis'" == "politician" {
            local prefix "politician_byprov_cohorttime_fe`tag'"
        }
        else {
            local prefix "protest_never_cohorttime_fe`tag'"
        }
        local event "${tables}/`prefix'_event_rural_acpop_all"
        confirm file "`event'.ster"
        est clear
        estread using "`event'.ster"
        quietly estimates dir
        local names `r(names)'
        estsave_csv `names' using "`event'.csv", replace
        confirm file "`event'.csv"
        confirm file "`event'_scalars.csv"
        display as result "Exported `analysis' event CSV: FE `fe'"
    }
}

display as result "COMPLETED all 64 local event-study CSV exports"


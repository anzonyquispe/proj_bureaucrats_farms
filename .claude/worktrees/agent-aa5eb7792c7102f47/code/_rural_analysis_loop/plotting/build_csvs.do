*-------------------------------------------------------------------------------
* build_csvs.do
* Read every .ster needed by the full report (app16 and app17 event studies,
* both rural variants, all sets) and write one CSV per .ster to $csv_dir.
* Each CSV contains one row per (evreg, var) pair, carrying the coefficient,
* pre-treatment ymean, and full vcov submatrix -- the format consumed by the
* event-study R plotter.
*
* Required globals (set by run_report.sh):
*   $plot_dir : plotting/ folder
*   $tables   : directory holding .ster files
*   $csv_dir  : output directory for CSVs
*-------------------------------------------------------------------------------

clear all
set more off

foreach g in plot_dir tables csv_dir {
    if "${`g'}" == "" {
        display as error "build_csvs: missing global \${`g'}"
        exit 198
    }
}

qui do "${plot_dir}/tools/estsave_csv.ado"

*-- Must match sbatch_cluster/_generate_sbatch_files.sh --------------------------
local variants    area farzad
local app16_sets  set1 set2
local app17_sets  set1 set2 set3 set4

local app16_base "_app_16_polischar_evst_all_rural"
local app17_base "_app_17_5km_evst_all_rural"

program define _export_all_evregs
    args ster csv
    capture confirm file "`ster'"
    if _rc {
        display as error "MISSING: `ster'"
        exit 0
    }
    display _n "Reading `ster'"
    est clear
    estread using "`ster'"

    local estlist ""
    forvalues k = 1/200 {
        capture est dir evreg`k'
        if _rc == 0 local estlist "`estlist' evreg`k'"
    }
    if "`estlist'" == "" {
        display as error "  no evreg* estimates in `ster'"
        exit 0
    }
    display "  exporting:`estlist'"
    estsave_csv `estlist' using "`csv'", replace
end

*-- Run through every (variant, app, set) combination ---------------------------
foreach v of local variants {

    foreach s of local app16_sets {
        _export_all_evregs ///
            "${tables}/`app16_base'_`v'_`s'.ster" ///
            "${csv_dir}/`app16_base'_`v'_`s'.csv"
    }

    foreach s of local app17_sets {
        _export_all_evregs ///
            "${tables}/`app17_base'_`v'_`s'.ster" ///
            "${csv_dir}/`app17_base'_`v'_`s'.csv"
    }
}

display _n "All CSVs written to ${csv_dir}."

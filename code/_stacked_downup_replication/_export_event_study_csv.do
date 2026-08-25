********************************************************************************
* Export every event-study .ster result to the CSV format used by the R plots.
*
* This dofile is intentionally separate from estimation. It discovers all
* event-study .ster files in ${tables}, restores their explicitly stored
* estimate names, and passes that expanded name list to estsave_csv. The
* estsave_csv command does not accept wildcard names such as evreg*.
********************************************************************************

version 17
set more off

if "$root" == "" {
    clear all
    set more off
    global location "dbox"
    global sample ""
    global is_rural_var "is_rural"
    global fe_list "1"
    global ster_suffix ""
    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
    global code_shell "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
    global code_dbox "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"
    if "$location" == "dbox" {
        global root "$dbox"
        global code "$code_dbox"
    }
    else {
        global root "$shell"
        global code "$code_shell"
    }
}

global tables "${code}/../../tables"

* The common cluster bridge may already have defined the program. Dropping it
* makes this dofile safe both as a standalone local job and after another
* dofile has loaded the same ado in the current Stata session.
capture program drop estsave_csv
quietly do "${code}/estsave_csv.ado"

capture which estread
if _rc {
    display as error "estread is required to restore the .ster files."
    exit 199
}

local ster_files : dir "${tables}" files "*.ster"
local exported = 0
local failed = 0

foreach ster_file of local ster_files {
    * A sample smoke test must never rewrite production CSV/scalar outputs.
    local matches_sample = strpos("`ster_file'", "_sample") == 0
    if "$sample" != "" {
        local matches_sample = strpos("`ster_file'", "$sample") > 0
    }
    local matches_suffix = strpos("`ster_file'", "_rice_high") == 0
    if "$ster_suffix" != "" {
        local matches_suffix = strpos("`ster_file'", "$ster_suffix") > 0
    }
    local is_event = ///
        strpos("`ster_file'", "main_event_study") == 1 | ///
        strpos("`ster_file'", "stacked_event_study") == 1 | ///
        strpos("`ster_file'", "_app_16_polischar_fe12_evst_all") == 1 | ///
        strpos("`ster_file'", "_app_17_5km_fe12_evst_all") == 1

    * The production Windows bridge exports only the three selected main
    * results. Legacy standalone use may still export the wider event set.
    if "$production_only" == "1" {
        local is_event = ///
            strpos("`ster_file'", "stacked_event_study_5pre") == 1 | ///
            strpos("`ster_file'", "stacked_event_study_pop_5pre") == 1 | ///
            (strpos("`ster_file'", "_app_16_polischar_fe12_evst_all") == 1 & ///
             strpos("`ster_file'", "_rural_acpop") > 0) | ///
            strpos("`ster_file'", "_app_17_5km_fe12_evst_all") == 1
    }

    if `is_event' & `matches_sample' & `matches_suffix' {
        est clear
        capture noisily estread using "${tables}/`ster_file'"
        if _rc {
            display as error "Could not read: ${tables}/`ster_file'"
            local failed = `failed' + 1
        }
        else {
            quietly estimates dir
            local estimate_names `r(names)'
            if `"`estimate_names'"' == "" {
                display as error "No stored estimates found in: `ster_file'"
                local failed = `failed' + 1
            }
            else {
                local csv_file = subinstr("`ster_file'", ".ster", ".csv", .)
                capture noisily estsave_csv `estimate_names' using ///
                    "${tables}/`csv_file'", replace
                if _rc {
                    display as error "CSV export failed: `csv_file'"
                    local failed = `failed' + 1
                }
                else {
                    display as result "Exported: ${tables}/`csv_file'"
                    local exported = `exported' + 1
                }
            }
        }
    }
}

display as result "Event-study CSV files exported: `exported'"
if `failed' > 0 {
    display as error "Event-study CSV exports failed: `failed'"
    exit 459
}
if `exported' == 0 {
    display as error "No event-study .ster files were found in ${tables}."
    exit 601
}

********************************************************************************

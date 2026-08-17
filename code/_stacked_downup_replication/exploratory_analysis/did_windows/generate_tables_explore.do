********************************************************************************
* Render exploratory main-DiD tables for alternative relative-month windows.
*
* Inputs:  .ster files in tables/exploratory_analysis
* Outputs: .tex files in tables/exploratory_analysis
********************************************************************************

version 17
clear all
set more off

* Optional first argument: alternative input/output folder for local testing.
args tables_arg

local windows_code "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"
local cluster_code "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
global code "`windows_code'"
if "`c(os)'" != "Windows" {
    global code "`cluster_code'"
}

* REPLICATION_CODE wins on either OS so any user's checkout works unedited.
local env_code : environment REPLICATION_CODE
if "`env_code'" != "" {
    global code "`env_code'"
}

global tables "${code}/../../tables/exploratory_analysis"
if "`tables_arg'" != "" {
    global tables "`tables_arg'"
}
capture mkdir "${code}/../../tables"
capture mkdir "${tables}"
display as text "Exploratory table folder: ${tables}"

capture which estread
local estread_rc = _rc
if `estread_rc' {
    display as error "estread is required to restore the exploratory .ster files."
    exit 199
}
capture which esttab
local esttab_rc = _rc
if `esttab_rc' {
    display as error "esttab is required to render the exploratory tables."
    exit 199
}

local windows "m6_p6 m6_p5 m5_p5 m5_p6"
local rendered = 0

foreach treatment in area pop {
    local input_stem "main_did_downup_area_ac"
    local treatment_var "downup_ac"
    local treatment_label "Down \$>\$ Up Area"
    if "`treatment'" == "pop" {
        local input_stem "main_did_downup_pop_ac"
        local treatment_var "downup_ac_pop"
        local treatment_label "Down \$>\$ Up Population"
    }

    foreach window of local windows {
        local window_label "-6 to +6"
        if "`window'" == "m6_p5" {
            local window_label "-6 to +5"
        }
        if "`window'" == "m5_p5" {
            local window_label "-5 to +5"
        }
        if "`window'" == "m5_p6" {
            local window_label "-5 to +6"
        }

        local ster_file "${tables}/`input_stem'_`window'_rural_stacked.ster"
        local tex_file "${tables}/`input_stem'_`window'_rural.tex"
        confirm file "`ster_file'"
        display as text "Reading `ster_file'"

        est clear
        estread using "`ster_file'"

        esttab eq1 eq2 eq3 eq4 using ///
            "`tex_file'", ///
            replace cells(b(fmt(3) star) se(par fmt(3))) ///
            star(* 0.10 ** 0.05 *** 0.01) ///
            keep(`treatment_var') order(`treatment_var') ///
            varlabels(`treatment_var' "`treatment_label'") ///
            stats(N acq monthyearfe acfe acmonthfe gridfe ymean, ///
                  fmt(%12.0fc %12.0fc 0 0 0 0 3) ///
                  labels("Observations" "N Assembly Constituencies" ///
                         "Month-Year FE" "AC FE" ///
                         "AC \$\times\$ Month-Year FE" "Grid FE" ///
                         "Mean DV, treated pre-treatment")) ///
            mtitles("No FE" "Grid + Month-Year" ///
                    "Grid + AC + Month-Year" ///
                    "Grid + AC \$\times\$ Month-Year") ///
            collabels(none) nobaselevels ///
            prehead("{" ///
                    "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
                    "\begin{tabular}{l*{4}{c}}" ///
                    "\hline" ///
                    "&\multicolumn{4}{c}{Relative-month window: `window_label'} \\ \hline") ///
            postfoot("\hline" "\end{tabular}" "}")

        confirm file "`tex_file'"
        local ++rendered
        display as result "Generated `tex_file'"
    }
}

if `rendered' != 8 {
    display as error "Expected 8 exploratory tables; generated `rendered'."
    exit 459
}
display as result "ALL EXPLORATORY DID TABLES COMPLETED"

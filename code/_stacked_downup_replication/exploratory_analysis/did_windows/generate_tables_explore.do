********************************************************************************
* Render exploratory main-DiD tables for alternative relative-month windows.
*
* Inputs:  tables/exploratory_analysis/*.ster
* Outputs: tables/exploratory_analysis/*.tex
********************************************************************************

version 17
clear all
set more off

if "$code" == "" {
    if "`c(os)'" == "Windows" {
        global code "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication"
    }
    else {
        global code "/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication"
    }
}

global tables "${code}/../../tables/exploratory_analysis"
capture mkdir "${code}/../../tables"
capture mkdir "${tables}"

capture which estread
if _rc {
    display as error "estread is required to restore the exploratory .ster files."
    exit 199
}
capture which esttab
if _rc {
    display as error "esttab is required to render the exploratory tables."
    exit 199
}

local windows "m6_p6 m6_p5 m5_p5 m5_p6"

foreach treatment in area pop {
    if "`treatment'" == "area" {
        local input_stem "main_did_downup_area_ac"
        local treatment_var "downup_ac"
        local treatment_label "Down \$>\$ Up Area"
    }
    else {
        local input_stem "main_did_downup_pop_ac"
        local treatment_var "downup_ac_pop"
        local treatment_label "Down \$>\$ Up Population"
    }

    foreach window of local windows {
        if "`window'" == "m6_p6" local window_label "-6 to +6"
        if "`window'" == "m6_p5" local window_label "-6 to +5"
        if "`window'" == "m5_p5" local window_label "-5 to +5"
        if "`window'" == "m5_p6" local window_label "-5 to +6"

        est clear
        estread using "${tables}/`input_stem'_`window'_rural_stacked.ster"

        esttab eq1 eq2 eq3 eq4 using ///
            "${tables}/`input_stem'_`window'_rural.tex", ///
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
            mtitles("No FE" "AC + Month-Year" ///
                    "AC \$\times\$ Month-Year" ///
                    "Grid + AC \$\times\$ Month-Year") ///
            collabels(none) nobaselevels ///
            prehead("{" ///
                    "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
                    "\begin{tabular}{l*{4}{c}}" ///
                    "\hline" ///
                    "&\multicolumn{4}{c}{Relative-month window: `window_label'} \\ \hline") ///
            postfoot("\hline" "\end{tabular}" "}")

        display as result "Generated ${tables}/`input_stem'_`window'_rural.tex"
    }
}

display as result "ALL EXPLORATORY DID TABLES COMPLETED"

********************************************************************************
* _generate_all_tables_rural.do
* Generates all LaTeX tables from .ster files - RURAL GRIDS ONLY
* Run this AFTER analysis do-files have produced .ster files
********************************************************************************

********************************************************************************
* Setup
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    global location "dbox"
    global sample ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"

    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }
}

global tables "${root}/tex/paper/tables"

********************************************************************************
* Helper: strip trailing zeros from one or more e()-stored stats.
* Reads each stat as a string (works for both estadd-scalar and estadd-local
* storage), runs "%9.3f" string formatting, then strips trailing zeros and a
* trailing bare ".". Result is stored as estadd local under the same name so
* esttab fmt(%s) renders it as-is. Stat names that are missing in a model are
* skipped silently.
********************************************************************************

capture program drop _strip_zeros_stats
program define _strip_zeros_stats
    syntax , Models(string) Stats(string)
    foreach m of local models {
        capture estimates restore `m'
        if _rc continue
        foreach s of local stats {
            local raw "`e(`s')'"
            if "`raw'" == "" continue
            * Treat as a number when possible: this normalizes scalar e()
            * storage and string-encoded numbers ("160.300") into a single
            * "%9.3f" representation before stripping trailing zeros.
            local rnum = real("`raw'")
            if !missing(`rnum') {
                local raw = strtrim(string(`rnum', "%9.3f"))
            }
            else {
                local raw = strtrim("`raw'")
            }
            local cleaned = regexr(regexr("`raw'", "0+$", ""), "\.$", "")
            * Write to a sibling macro <stat>_clean so we never collide with
            * an existing scalar e(<stat>). esttab stats() lists reference
            * the *_clean name for display.
            estadd local `s'_clean "`cleaned'"
        }
        estimates store `m'
    }
end

********************************************************************************
* 1. Main DiD Table (_main_1_did)
********************************************************************************

estread using "${tables}/main_did_downup_area_ac${sample}_rural.ster"
_strip_zeros_stats, models(eq1 eq2 eq3 eq4) stats(ymean)

esttab eq1 eq2 eq3 eq4 using "${tables}/main_did_downup_area_ac${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac) ///
    order(downup_ac) ///
    varlabels(downup_ac "Down \$>\$ Up") ///
    stats(N acq monthyearfe acfe acmonthfe gridfe ymean_clean, ///
          fmt(%12.0fc %12.0fc %s %s %s %s %s) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "Month-Year FE" "AC FE" "AC \$\times\$ Month-Year FE" "Grid FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{4}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)}         &\multicolumn{1}{c}{(4)}         \\" ///
            "            & \multicolumn{4}{c}{Number of Fires (in 1,000 units)} \\ \hline") ///
    posthead("") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Generated: main_did_downup_area_ac_rural.tex"

********************************************************************************
* 2. Bureaucrat-Politician DiD (_main_3_bureau_polisc_did)
********************************************************************************

estread using "${tables}/_main_3_bureau_polisc_did${sample}_rural.ster"
_strip_zeros_stats, models(eq1 eq2 eq3 eq4 eq5) stats(ymean ymean2)

esttab eq1 eq2 eq3 eq4 eq5 using "${tables}/_main_3_bureau_polisc_did${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac downup_dummy downup_interaction) ///
    order( downup_dummy downup_ac downup_interaction) ///
    varlabels(downup_ac "Down\$>\$ Up Politician" ///
              downup_dummy "Down\$>\$ Up Bureaucrat" ///
              downup_interaction "Down\$>\$ Up Pol. \$\times\$ Down\$>\$ Up Bur.") ///
    stats(N nacs ndists monthyearfe acfe  acmonthfe distmonthfe gridfe ymean2_clean, ///
          fmt(%12.0fc %12.0fc %12.0fc %s %s %s %s %s %s) ///
          labels("Observations" "N Assembly Constituencies" "N Districts" ///
                 "Month-Year FE" "AC FE" "AC \$\times\$ Month-Year FE" "District \$\times\$ Month-Year FE" "Grid FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{5}{c}}" ///
            "\hline" ///
            " & (1) & (2) & (3) & (4) & (5) \\" ///
            " & \multicolumn{5}{c}{Number of Fires (in 1,000 units)} \\ \hline") ///
    posthead("") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Generated: _main_3_bureau_polisc_did_rural.tex"

********************************************************************************
* 3. Protest DiD with Downup (_main_4_protest_5km_fe12_did_downup)
********************************************************************************
est clear
estread using "${tables}/_main_4_protest_5km_fe12_did_downup${sample}_rural.ster"
_strip_zeros_stats, models(evreg1 evreg2 evreg3 evreg4 evreg5 evreg6) stats(ymean ymean2 ymean3)

esttab evreg1 evreg2 evreg3 evreg4 evreg5 evreg6 ///
    using "${tables}/_main_4_protest_5km_fe12_did_downup${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(1.post_#1.treat ///
          1.moderator ///
          1.post_#1.moderator ///
          1.treat#1.moderator ///
          1.post_#1.treat#1.moderator) ///
    order(1.post_#1.treat ///
          1.moderator ///
          1.post_#1.moderator ///
          1.treat#1.moderator ///
          1.post_#1.treat#1.moderator) ///
    varlabels(1.post_#1.treat "Post \$\times\$ Protest" ///
              1.moderator "Down \$>\$ Up" ///
              1.post_#1.moderator "Post \$\times\$ Down \$>\$ Up" ///
              1.treat#1.moderator "Protest \$\times\$ Down \$>\$ Up" ///
              1.post_#1.treat#1.moderator "Post \$\times\$ Protest \$\times\$ Down \$>\$ Up") ///
    stats(      N    acq gridfe time electionfe provtrendfe ymean_clean ymean2_clean, ///
          fmt(%12.0fc  %s    %s %s    %s         %s          %s          %s) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "Grid FE" "Relative Time FE" "Legislature FE" "Province Trend FE" ///
                 "Mean DV" "Mean DV2 (Down\$>\$Up=1)")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{6}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)}         &\multicolumn{1}{c}{(4)}         &\multicolumn{1}{c}{(5)}         &\multicolumn{1}{c}{(6)}         \\" ///
            "            & \multicolumn{6}{c}{Number of Fires (in 1,000 units)} \\ \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Generated: _main_4_protest_5km_fe12_did_downup_rural.tex"

********************************************************************************
* 4. Politician Char DiD with Downup (_main_5_polischar_fe12_did_downup_inter)
********************************************************************************
est clear
estread using "${tables}/_main_5_polischar_fe12_did_downup_inter${sample}_rural.ster"
_strip_zeros_stats, models(evreg1 evreg2 evreg3 evreg4 evreg5 evreg6) stats(ymean ymean2 ymean3)

esttab evreg1 evreg2 evreg3 evreg4 evreg5 evreg6 ///
    using "${tables}/_main_5_polischar_fe12_did_downup_inter${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(1.post_#1.treat ///
         1.post_#1.treat#1.moderator ///
         1.moderator ///
         1.post_#1.moderator ///
         1.treat#1.moderator ///
         1.post_#1.treat#1.moderator) ///
    order(1.post_#1.treat ///
          1.moderator ///
          1.post_#1.moderator ///
          1.treat#1.moderator ///
          1.post_#1.treat#1.moderator) ///
    varlabels(1.post_#1.treat "Post \$\times\$ Agriculturalist" ///
              1.post_#1.treat#1.moderator "Post \$\times\$ Agriculturalist" ///
              1.moderator "Down \$>\$ Up" ///
              1.post_#1.moderator "Post \$\times\$ Down \$>\$ Up" ///
              1.treat#1.moderator "Agriculturalist \$\times\$ Down \$>\$ Up" ///
              1.post_#1.treat#1.moderator "Post \$\times\$ Agric. \$\times\$ Down \$>\$ Up") ///
    stats(      N        acq     gridfe time electionfe provtrendfe ymean_clean ymean2_clean, ///
          fmt( %12.0fc %12.0fc   %s     %s   %s         %s          %s          %s) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "Grid FE" "Relative Time FE" "Legislature FE" ///
                 "Province Linear Time Trend FE" ///
                 "Mean DV" "Mean DV (Down \$>\$ Up=1)")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{6}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)}         &\multicolumn{1}{c}{(4)}         &\multicolumn{1}{c}{(5)}         &\multicolumn{1}{c}{(6)}         \\" ///
            "            & \multicolumn{6}{c}{Number of Fires (in 1,000 units)} \\ \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Generated: _main_5_polischar_fe12_did_downup_inter_rural.tex"

********************************************************************************
* 5. Treatment Definition Robustness (_app_6_main_did_treat_definition)
********************************************************************************
est clear
estread using "${tables}/_app_6_main_did_treat_definition${sample}_rural.ster"
_strip_zeros_stats, models(eq1 eq2 eq3 eq4 eq5) stats(ymean)

esttab eq1 eq2 eq3 eq4 eq5 ///
    using "${tables}/_app_6_main_did_treat_definition${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(4) star) se(par fmt(4))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac downup_ac_pop downup_1sd down_percent downup_diff_percent) ///
    order(downup_ac downup_ac_pop downup_1sd down_percent downup_diff_percent) ///
    varlabels(downup_ac "Down\$>\$Up" ///
              downup_ac_pop "Down\$>\$Up Population" ///
              downup_1sd "Down\$>\$Up by 1std" ///
              down_percent "Downwind over total area" ///
              downup_diff_percent "Down-Up Percent") ///
    stats(N acq gridfe acmonthfe ymean_clean, ///
          fmt(%12.0fc %s %s %s %12.3fc) ///
          labels("Observations" "N Assembly Constituencies" "Grid FE" "Assembly \$\times\$ Month-Year FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("\begin{tabular}{lccccc}" ///
            "\hline" ///
            "& (1) & (2) & (3) & (4) & (5)\\" ///
            "& \multicolumn{5}{c}{Number of Fires (in 1,000 units) }\\" ///
            "\hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}")

display "Generated: _app_6_main_did_treat_definition_rural.tex"

********************************************************************************
* 6. Alternative DVs (_app_7_main_did_downup_area_ac_dv)
********************************************************************************

estread using "${tables}/_app_7_main_did_downup_area_ac_dv${sample}_rural.ster"
_strip_zeros_stats, models(eq1 eq2 eq3) stats(ymean)

esttab eq1 eq2 eq3 ///
    using "${tables}/_app_7_main_did_downup_area_ac_dv${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(4) star) se(par fmt(4))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac) ///
    varlabels(downup_ac "Down \$>\$ Up") ///
    stats(N acq gridfe acmonthfe ymean_clean, ///
          fmt(%12.0fc %s %s %s %s) ///
          labels("Observations" "N Assembly Constituencies" "Grid FE" "Assembly \$\times\$ Month-Year FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("\begin{tabular}{lccc}" ///
            "\tabularnewline \hline" ///
            "& (1) & (2) & (3)\\" ///
            "& Any Fire & Log (N) Fires & Mean Brightness\\" ///
            "\hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}")

display "Generated: _app_7_main_did_downup_area_ac_dv_rural.tex"

********************************************************************************
* 7. DiD by Year (_app_8_main_did_by_year)
********************************************************************************

estread using "${tables}/_app_8_main_did_by_year${sample}_rural.ster"
_strip_zeros_stats, models(eq1 eq2 eq3 eq4 eq5 eq6 eq7 eq8 eq9 eq10) stats(ymean)

esttab eq1 eq2 eq3 eq4 eq5 eq6 eq7 eq8 eq9 eq10 ///
    using "${tables}/_app_8_main_did_by_year${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac) ///
    varlabels(downup_ac "Down\$>\$Up") ///
    stats(N acq gridfe acmonthfe ymean_clean, ///
          fmt(%12.0fc %s %s %s %s) ///
          labels("Observations" "N Assembly Constituencies" "Grid FE" "Assembly \$\times\$ Month-Year FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("\begin{tabular}{lcccccccccc} \hline" ///
            " & (1) & (2) & (3) & (4) & (5) & (6) & (7) & (8) & (9) & (10) \\" ///
            " & \multicolumn{10}{c}{Number of Fires (in 1,000 units)}\\" ///
            " & 2012/2013 & 2013/2014 & 2014/2015 & 2015/2016 & 2016/2017 & 2017/2018 & 2018/2019 & 2019/2020 & 2020/2021 & 2021/2022 \\ \hline") ///
    posthead("") ///
    postfoot("\hline" "\end{tabular}")

display "Generated: _app_8_main_did_by_year_rural.tex"

********************************************************************************
* 8. DiD by State (_app_9_main_did_by_state)
********************************************************************************

estread using "${tables}/_app_9_main_did_by_state${sample}_rural.ster"
_strip_zeros_stats, models(eq1 eq2 eq3 eq4) stats(ymean)

esttab eq1 eq2 eq3 eq4 ///
    using "${tables}/_app_9_main_did_by_state${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac) ///
    varlabels(downup_ac "Down\$>\$Up") ///
    stats(N acq gridfe acmonthfe ymean_clean, ///
          fmt(%12.0fc %s %s %s %s) ///
          labels("Observations" "N Assembly Constituencies" "Grid FE" "Assembly \$\times\$ Month-Year FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("\begin{tabular}{lcccc} \hline" ///
            " & (1) & (2) & (3) & (4) \\" ///
            " & \multicolumn{4}{c}{Number of Fires (in 1,000 units)}\\" ///
            " & Bihar & Haryana & Punjab & Uttar Pradesh \\ \hline") ///
    posthead("") ///
    postfoot("\hline" "\end{tabular}")

display "Generated: _app_9_main_did_by_state_rural.tex"

********************************************************************************
* 9. Rice Moderators (_app_10_did_rice_moderators)
********************************************************************************
est clear
estread using "${tables}/_app_10_did_rice_moderators${sample}_rural.ster"
_strip_zeros_stats, models(eq1 eq2 eq3) stats(ymean ymean2 ymean3)

esttab eq1 eq2 eq3 ///
    using "${tables}/_app_10_did_rice_moderators${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(1.downup_ac ///
         1.downup_ac#1.rice_area_aclvl_ahigh ///
         1.downup_ac#1.rice_harvarea_aclvl_ahigh ///
         1.downup_ac#1.rice_prod_aclvl_ahigh) ///
    order(1.downup_ac ///
          1.downup_ac#1.rice_area_aclvl_ahigh ///
          1.downup_ac#1.rice_harvarea_aclvl_ahigh ///
          1.downup_ac#1.rice_prod_aclvl_ahigh) ///
    varlabels(1.downup_ac "Down\$>\$up AC" ///
              1.downup_ac#1.rice_area_aclvl_ahigh "Down\$>\$up AC \$\times\$ Above Median Rice Area" ///
              1.downup_ac#1.rice_harvarea_aclvl_ahigh "Down\$>\$up AC \$\times\$ Above Median Harvested Rice Area" ///
              1.downup_ac#1.rice_prod_aclvl_ahigh "Down\$>\$up AC \$\times\$ Above Median Rice Production") ///
    stats(N acq gridfe acmonthfe ymean_clean ymean2_clean ymean3_clean, ///
          fmt(%12.0fc %12.0fc %s %s %s %s %s) ///
          labels("Observations" "N Assembly Constituencies" "Grid FE" ///
                 "AC \$\times\$ Month-Year FE" "Mean DV" "Mean DV2" "Mean DV3")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("\begin{tabular}{lccc}" ///
            "      \hline" ///
            "       & \multicolumn{3}{c}{Number of Fires (in 1,000 units) - Rural Grids}\\" ///
            "                                                              & (1)            & (2)            & (3)\\\\  " ///
            "      \midrule") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}")

display "Generated: _app_10_did_rice_moderators_rural.tex"

********************************************************************************
* 10. Placebo Pop 13km (_app_11_placebo_pop_13km)
********************************************************************************
est dir
estread using "${tables}/_app_11_placebo_pop_13km${sample}_rural.ster"
_strip_zeros_stats, models(eq1 eq2 eq3) stats(ymean)

esttab eq1 eq2 eq3 ///
    using "${tables}/_app_11_placebo_pop_13km${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(4) star) se(par fmt(4))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_pop_13km) ///
    varlabels(downup_pop_13km "Down\$>\$Up (Placebo)") ///
    stats(N acq gridfe acmonthfe ymean_clean, ///
          fmt(%12.0fc %s %s %s %s) ///
          labels("Observations" "N Assembly Constituencies" "Grid FE" ///
                 "Assembly \$\times\$ Month-Year FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("\begin{tabular}{lccc} \hline" ///
            "       & (1) & (2) & (3) \\" ///
            "       & \multicolumn{3}{c}{Number of Fires (in 1,000 units) - Rural Grids}\\" ///
            "    & Full Sample           &  Treated for Politicians             & Control for Politicians \\\\  \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}")

display "Generated: _app_11_placebo_pop_13km_rural.tex"

********************************************************************************
* 11. Protest 5km FE DiD (_app_12_protest_5km_fe_did)
********************************************************************************
est clear
estread using "${tables}/_app_12_protest_5km_fe_did${sample}_rural.ster"
_strip_zeros_stats, models(evreg1 evreg2 evreg3) stats(ymean)

esttab evreg1 evreg2 evreg3 ///
    using "${tables}/_app_12_protest_5km_fe_did${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(1.post_#1.treat) ///
    order(1.post_#1.treat) ///
    varlabels(1.post_#1.treat "Post \$\times\$ Protest") ///
    stats(		N 		acq 	gridfe time electionfe provtrendfe ymean_clean, ///
          fmt(%12.0fc %12.0fc 	%s     %s   %s         %s          %s) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "Grid  \$\times\$ Cohort FE" "Relative Time FE" "Legislature  \$\times\$ Cohort FE" "Province  \$\times\$ Cohort Trend FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{3}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)}         \\" ///
            "            & \multicolumn{3}{c}{Number of Fires (in 1,000 units) } \\ \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Generated: _app_12_protest_5km_fe_did_rural.tex"

********************************************************************************
* 12. Protest Rice Mods (_app_13_protest_5km_fe12_did_ricemods)
********************************************************************************
est clear
estread using "${tables}/_app_13_protest_5km_fe12_did_ricemods${sample}_rural.ster"
_strip_zeros_stats, models(eq1 eq2 eq3) stats(ymean ymean2 ymean3)

esttab eq1 eq2 eq3 using "${tables}/_app_13_protest_5km_fe12_did_ricemods${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(1.post_#1.treat ///
         1.post_#1.treat#1.rice_area_aclvl_ahigh ///
         1.post_#1.treat#1.rice_harvarea_aclvl_ahigh ///
         1.post_#1.treat#1.rice_prod_aclvl_ahigh) ///
    order(1.post_#1.treat ///
          1.post_#1.treat#1.rice_area_aclvl_ahigh ///
          1.post_#1.treat#1.rice_harvarea_aclvl_ahigh ///
          1.post_#1.treat#1.rice_prod_aclvl_ahigh) ///
    varlabels(1.post_#1.treat "Post \$\times\$ Protest" ///
              1.post_#1.treat#1.rice_area_aclvl_ahigh "Post \$\times\$ Protest \$\times\$ Rice Areas" ///
              1.post_#1.treat#1.rice_harvarea_aclvl_ahigh "Post \$\times\$ Protest \$\times\$ Harvested Rice Area" ///
              1.post_#1.treat#1.rice_prod_aclvl_ahigh "Post \$\times\$ Protest \$\times\$ Rice Production") ///
    stats(N acq gridfe time electionfe provtrendfe ymean_clean ymean2_clean ymean3_clean, ///
          fmt(%12.0fc %12.0fc %s %s %s %s %s %s %s) ///
          labels("Observations" "N Assembly Constituencies" "Grid  \$\times\$ Cohort FE" "Relative Time FE" "Legislature  \$\times\$ Cohort FE" "Province  \$\times\$ Cohort Trend FE" "Mean DV" "Mean DV2" "Mean DV3")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{3}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)}         \\\\" ///
            "            &\multicolumn{3}{c}{Number of Fires (in 1,000 units) } \\\\ \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Generated: _app_13_protest_5km_fe12_did_ricemods_rural.tex"

********************************************************************************
* 13. Politician Rice Mods (_app_14_polischar_fe12_did_ricemods)
********************************************************************************
est clear
estread using "${tables}/_app_14_polischar_fe12_did_ricemods${sample}_rural.ster"
_strip_zeros_stats, models(evreg1 evreg2 evreg3 evreg4) stats(ymean ymean2 ymean3)

esttab evreg1 evreg2 evreg3 evreg4 ///
    using "${tables}/_app_14_polischar_fe12_did_ricemods${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(1.post_#1.treat ///
         1.post_#1.treat#1.rice_area_aclvl_ahigh ///
         1.post_#1.treat#1.rice_harvarea_aclvl_ahigh ///
         1.post_#1.treat#1.rice_prod_aclvl_ahigh) ///
    order(1.post_#1.treat ///
          1.post_#1.treat#1.rice_area_aclvl_ahigh ///
          1.post_#1.treat#1.rice_harvarea_aclvl_ahigh ///
          1.post_#1.treat#1.rice_prod_aclvl_ahigh) ///
    varlabels(1.post_#1.treat "Post \$\times\$ Agriculturalist" ///
              1.post_#1.treat#1.rice_area_aclvl_ahigh "Post \$\times\$ Agriculturalist \$\times\$ Rice Areas" ///
              1.post_#1.treat#1.rice_harvarea_aclvl_ahigh "Post \$\times\$ Agriculturalist \$\times\$ Harvested Rice Area" ///
              1.post_#1.treat#1.rice_prod_aclvl_ahigh "Post \$\times\$ Agriculturalist \$\times\$ Rice Production") ///
    stats(N acq gridfe time electionfe provtrendfe ymean_clean ymean2_clean ymean3_clean, ///
          fmt(%12.0fc %12.0fc %s %s %s %s %s %s %s) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "Grid  \$\times\$ Cohort FE" "Relative Time FE" "Legislature  \$\times\$ Cohort FE" "Province  \$\times\$ Cohort Trend FE" ///
                 "Mean DV" "Mean DV2" "Mean DV3")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{4}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)} &\multicolumn{1}{c}{(4)}         \\" ///
            "            & \multicolumn{4}{c}{Number of Fires (in 1,000 units)} \\ \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Generated: _app_14_polischar_fe12_did_ricemods_rural.tex"

********************************************************************************
* 14. Politician FE DiD (_app_15_polischar_fe12_did)
********************************************************************************
est clear
estread using "${tables}/_app_15_polischar_fe12_did${sample}_rural.ster"
_strip_zeros_stats, models(evreg1 evreg2 evreg3) stats(ymean)

esttab evreg1 evreg2 evreg3 ///
    using "${tables}/_app_15_polischar_fe12_did${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(1.post_#1.treat) ///
    order(1.post_#1.treat) ///
    varlabels(1.post_#1.treat "Post \$\times\$ Agriculturalist") ///
    stats(N acq gridfe time electionfe provtrendfe ymean_clean, ///
          fmt(%12.0fc %12.0fc %s %s %s %s %s) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "Grid \$\times\$ Cohort FE" "Relative Time FE" "Legislature  \$\times\$ Cohort FE" "Province  \$\times\$ Cohort Trend FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{3}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)}         \\" ///
            "            & \multicolumn{3}{c}{Number of Fires (in 1,000 units) } \\ \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Generated: _app_15_polischar_fe12_did_rural.tex"



********************************************************************************
* 20. Main DiD Table (_main_1_did)
********************************************************************************

estread using "${tables}/_app_20_did_downwind_hm_${sample}_rural.ster"
_strip_zeros_stats, models(eq1 eq2 eq3 eq4) stats(ymean)
_strip_zeros_stats, models(eq1 eq2 eq3 eq4) stats(ymean2)


esttab eq1 eq2 eq3 eq4 using "${tables}/_app_20_did_downwind_hm${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(1.downup_ac 1.downup_ac#1.rice_prod_aclvl_ahigh ) ///
    order(1.downup_ac 1.downup_ac#1.rice_prod_aclvl_ahigh) ///
    varlabels(1.downup_ac "Down \$>\$ Up" 1.downup_ac#1.rice_prod_aclvl_ahigh "Down \$>\$ Up \$\times\$ Rice Production" ) ///
    stats(N acq monthyearfe acfe acmonthfe gridfe ymean_clean ymean2_clean, ///
          fmt(%12.0fc %12.0fc %s %s %s %s %s %s) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "Month-Year FE" "AC FE" "AC \$\times\$ Month-Year FE" "Grid FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{4}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)}         &\multicolumn{1}{c}{(4)}         \\" ///
            "            & \multicolumn{4}{c}{Number of Fires (in 1,000 units)} \\ \hline") ///
    posthead("") ///
    postfoot("\hline" "\end{tabular}" "}")




********************************************************************************
display "All rural tables generated successfully."
********************************************************************************

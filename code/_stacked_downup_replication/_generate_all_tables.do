********************************************************************************
* _generate_all_tables.do  (acpop variant)
* Generates LaTeX tables from .ster files - RURAL GRIDS, downup_ac_pop
* Run this AFTER analysis do-files have produced .ster files.
*
* NOTE: the stacked analyses (main_1, main_3, app_7, app_8, app_9, app_10,
* app_20) now read the "_rural_stacked.ster" files those do-files write.
* The analyses not yet converted to the stacked design (main_4, main_5,
* app_14, app_15) still read their "_rural_acpop.ster" files.
* The .tex output filenames are unchanged (_rural_acpop.tex) so downstream
* \input's keep resolving.
*
* Also writes a single side-by-side comparison document:
*   ${tables}/_comparison_downup_ac_vs_acpop.tex
* which \input's BOTH the original (_rural.tex) and the new (_rural_acpop.tex)
* tables so they can be eyeballed in one PDF.
*
* This dofile is intended to run LOCALLY (location="dbox") - it reads ster
* files and writes tex. The analysis dofiles handle the cluster work.
********************************************************************************

********************************************************************************
* Setup
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    global location "shell"
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
            local rnum = real("`raw'")
            if !missing(`rnum') {
                local raw = strtrim(string(`rnum', "%9.3f"))
            }
            else {
                local raw = strtrim("`raw'")
            }
            local cleaned = regexr(regexr("`raw'", "0+$", ""), "\.$", "")
            estadd local `s'_clean "`cleaned'"
        }
        estimates store `m'
    }
end

********************************************************************************
* 1. Main DiD Table (_main_1_did)
********************************************************************************
est clear
estread using "${tables}/main_did_downup_area_ac_rural_stacked.ster"
_strip_zeros_stats, models(eq1 eq2 eq3 eq4) stats(ymean)

esttab eq1 eq2 eq3 eq4 using "${tables}/main_did_downup_area_ac${sample}_rural_acpop.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac_pop) ///
    order(downup_ac_pop) ///
    varlabels(downup_ac_pop "Down \$>\$ Up Population") ///
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

display "Generated: main_did_downup_area_ac_rural_acpop.tex"

********************************************************************************
* 2. Bureaucrat-Politician DiD (_main_3_bureau_polisc_did)
********************************************************************************
est clear
estread using "${tables}/_main_3_bureau_polisc_did_rural_stacked.ster"
_strip_zeros_stats, models(eq1 eq2 eq3 eq4 eq5) stats(ymean ymean2)

esttab eq1 eq2 eq3 eq4 eq5 using "${tables}/_main_3_bureau_polisc_did${sample}_rural_acpop.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac_pop downup_dummy downup_interaction) ///
    order( downup_dummy downup_ac_pop downup_interaction) ///
    varlabels(downup_ac_pop "Down\$>\$ Up Politician (Pop)" ///
              downup_dummy "Down\$>\$ Up Bureaucrat" ///
              downup_interaction "Down\$>\$ Up Pol. (Pop) \$\times\$ Down\$>\$ Up Bur.") ///
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

display "Generated: _main_3_bureau_polisc_did_rural_acpop.tex"

********************************************************************************
* 3. Protest DiD with Downup (_main_4_protest_5km_fe12_did_downup)
********************************************************************************
est clear
estread using "${tables}/_main_4_protest_5km_fe12_did_downup${sample}_rural_acpop.ster"
_strip_zeros_stats, models(evreg1 evreg2 evreg3 evreg4 evreg5 evreg6) stats(ymean ymean2 ymean3)

esttab evreg1 evreg2 evreg3 evreg4 evreg5 evreg6 ///
    using "${tables}/_main_4_protest_5km_fe12_did_downup${sample}_rural_acpop.tex", ///
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
              1.moderator "Down \$>\$ Up (Pop)" ///
              1.post_#1.moderator "Post \$\times\$ Down \$>\$ Up (Pop)" ///
              1.treat#1.moderator "Protest \$\times\$ Down \$>\$ Up (Pop)" ///
              1.post_#1.treat#1.moderator "Post \$\times\$ Protest \$\times\$ Down \$>\$ Up (Pop)") ///
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

display "Generated: _main_4_protest_5km_fe12_did_downup_rural_acpop.tex"

********************************************************************************
* 4. Politician Char DiD with Downup (_main_5_polischar_fe12_did_downup_inter)
********************************************************************************
est clear
estread using "${tables}/_main_5_polischar_fe12_did_downup_inter${sample}_rural_acpop.ster"
_strip_zeros_stats, models(evreg1 evreg2 evreg3 evreg4 evreg5 evreg6) stats(ymean ymean2 ymean3)

esttab evreg1 evreg2 evreg3 evreg4 evreg5 evreg6 ///
    using "${tables}/_main_5_polischar_fe12_did_downup_inter${sample}_rural_acpop.tex", ///
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
              1.moderator "Down \$>\$ Up (Pop)" ///
              1.post_#1.moderator "Post \$\times\$ Down \$>\$ Up (Pop)" ///
              1.treat#1.moderator "Agriculturalist \$\times\$ Down \$>\$ Up (Pop)" ///
              1.post_#1.treat#1.moderator "Post \$\times\$ Agric. \$\times\$ Down \$>\$ Up (Pop)") ///
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

display "Generated: _main_5_polischar_fe12_did_downup_inter_rural_acpop.tex"

********************************************************************************
* 5. Alternative DVs (_app_7_main_did_downup_area_ac_dv)
********************************************************************************
est clear
estread using "${tables}/_app_7_main_did_downup_area_ac_dv_rural_stacked.ster"
_strip_zeros_stats, models(eq1 eq2 eq3) stats(ymean)

esttab eq1 eq2 eq3 ///
    using "${tables}/_app_7_main_did_downup_area_ac_dv${sample}_rural_acpop.tex", ///
    replace ///
    cells(b(fmt(4) star) se(par fmt(4))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac_pop) ///
    varlabels(downup_ac_pop "Down \$>\$ Up (Pop)") ///
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

display "Generated: _app_7_main_did_downup_area_ac_dv_rural_acpop.tex"

********************************************************************************
* 6. DiD by Year (_app_8_main_did_by_year)
********************************************************************************
est clear
estread using "${tables}/_app_8_main_did_by_year_rural_stacked.ster"
_strip_zeros_stats, models(eq1 eq2 eq3 eq4 eq5 eq6 eq7 eq8 eq9 eq10) stats(ymean)

esttab eq1 eq2 eq3 eq4 eq5 eq6 eq7 eq8 eq9 eq10 ///
    using "${tables}/_app_8_main_did_by_year${sample}_rural_acpop.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac_pop) ///
    varlabels(downup_ac_pop "Down\$>\$Up (Pop)") ///
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

display "Generated: _app_8_main_did_by_year_rural_acpop.tex"

********************************************************************************
* 7. DiD by State (_app_9_main_did_by_state)
********************************************************************************
est clear
estread using "${tables}/_app_9_main_did_by_state_rural_stacked.ster"
_strip_zeros_stats, models(eq1 eq2 eq3 eq4) stats(ymean)

esttab eq1 eq2 eq3 eq4 ///
    using "${tables}/_app_9_main_did_by_state${sample}_rural_acpop.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac_pop) ///
    varlabels(downup_ac_pop "Down\$>\$Up (Pop)") ///
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

display "Generated: _app_9_main_did_by_state_rural_acpop.tex"

********************************************************************************
* 8. Rice Moderators (_app_10_did_rice_moderators)
********************************************************************************
est clear
estread using "${tables}/_app_10_did_rice_moderators_rural_stacked.ster"
_strip_zeros_stats, models(eq1 eq2 eq3) stats(ymean ymean2 ymean3)

esttab eq1 eq2 eq3 ///
    using "${tables}/_app_10_did_rice_moderators${sample}_rural_acpop.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(1.downup_ac_pop ///
         1.downup_ac_pop#1.rice_area_aclvl_ahigh ///
         1.downup_ac_pop#1.rice_harvarea_aclvl_ahigh ///
         1.downup_ac_pop#1.rice_prod_aclvl_ahigh) ///
    order(1.downup_ac_pop ///
          1.downup_ac_pop#1.rice_area_aclvl_ahigh ///
          1.downup_ac_pop#1.rice_harvarea_aclvl_ahigh ///
          1.downup_ac_pop#1.rice_prod_aclvl_ahigh) ///
    varlabels(1.downup_ac_pop "Down\$>\$up AC (Pop)" ///
              1.downup_ac_pop#1.rice_area_aclvl_ahigh "Down\$>\$up AC (Pop) \$\times\$ Above Median Rice Area" ///
              1.downup_ac_pop#1.rice_harvarea_aclvl_ahigh "Down\$>\$up AC (Pop) \$\times\$ Above Median Harvested Rice Area" ///
              1.downup_ac_pop#1.rice_prod_aclvl_ahigh "Down\$>\$up AC (Pop) \$\times\$ Above Median Rice Production") ///
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

display "Generated: _app_10_did_rice_moderators_rural_acpop.tex"

********************************************************************************
* 9. Politician Rice Mods (_app_14_polischar_fe12_did_ricemods)
********************************************************************************
est clear
estread using "${tables}/_app_14_polischar_fe12_did_ricemods${sample}_rural_acpop.ster"
_strip_zeros_stats, models(evreg1 evreg2 evreg3 evreg4) stats(ymean ymean2 ymean3)

esttab evreg1 evreg2 evreg3 evreg4 ///
    using "${tables}/_app_14_polischar_fe12_did_ricemods${sample}_rural_acpop.tex", ///
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

display "Generated: _app_14_polischar_fe12_did_ricemods_rural_acpop.tex"

********************************************************************************
* 10. Politician FE DiD (_app_15_polischar_fe12_did)
********************************************************************************
est clear
estread using "${tables}/_app_15_polischar_fe12_did${sample}_rural_acpop.ster"
_strip_zeros_stats, models(evreg1 evreg2 evreg3) stats(ymean)

esttab evreg1 evreg2 evreg3 ///
    using "${tables}/_app_15_polischar_fe12_did${sample}_rural_acpop.tex", ///
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

display "Generated: _app_15_polischar_fe12_did_rural_acpop.tex"

********************************************************************************
* 11. Downwind Heterogeneity (_app_20_did_downwind_hm)
********************************************************************************
est clear
estread using "${tables}/_app_20_did_downwind_hm_rural_stacked.ster"
_strip_zeros_stats, models(eq1 eq2 eq3 eq4) stats(ymean)
_strip_zeros_stats, models(eq1 eq2 eq3 eq4) stats(ymean2)

esttab eq1 eq2 eq3 eq4 using "${tables}/_app_20_did_downwind_hm${sample}_rural_acpop.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(1.downup_ac_pop 1.downup_ac_pop#1.rice_prod_aclvl_ahigh ) ///
    order(1.downup_ac_pop 1.downup_ac_pop#1.rice_prod_aclvl_ahigh) ///
    varlabels(1.downup_ac_pop "Down \$>\$ Up (Pop)" 1.downup_ac_pop#1.rice_prod_aclvl_ahigh "Down \$>\$ Up (Pop) \$\times\$ Rice Production" ) ///
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

display "Generated: _app_20_did_downwind_hm_rural_acpop.tex"

********************************************************************************
* Side-by-side comparison document
* Writes ${tables}/_comparison_downup_ac_vs_acpop.tex
* Each section \input's the original (_rural.tex) and the new (_rural_acpop.tex)
* so the two can be eyeballed in a single PDF.
********************************************************************************

tempname cmp
file open `cmp' using "${tables}/_comparison_downup_ac_vs_acpop${sample}.tex", write replace

file write `cmp' "\documentclass[10pt]{article}" _n
file write `cmp' "\usepackage[margin=0.6in]{geometry}" _n
file write `cmp' "\usepackage{booktabs}" _n
file write `cmp' "\usepackage{array}" _n
file write `cmp' "\usepackage{multirow}" _n
file write `cmp' "\usepackage{xcolor}" _n
file write `cmp' "\usepackage{colortbl}" _n
file write `cmp' "\usepackage{tabularx}" _n
file write `cmp' "\usepackage{graphicx}" _n
file write `cmp' "\usepackage{adjustbox}" _n
file write `cmp' "\usepackage{amsmath}" _n
file write `cmp' "\usepackage{amssymb}" _n
file write `cmp' "\usepackage{titlesec}" _n
file write `cmp' "\providecommand{\sym}[1]{\ifmmode^{#1}\else\(^{#1}\)\fi}" _n
file write `cmp' "\titleformat{\section}{\normalfont\Large\bfseries\color{blue!60!black}}{\thesection}{1em}{}" _n
file write `cmp' "\newcommand{\OLD}[1]{\begin{center}\colorbox{red!8}{\parbox{0.97\linewidth}{\textbf{\textcolor{red!60!black}{ORIGINAL (downup\_ac):}}\par\vspace{0.4em}\centering\begin{adjustbox}{max width=\linewidth}#1\end{adjustbox}}}\end{center}}" _n
file write `cmp' "\newcommand{\NEW}[1]{\begin{center}\colorbox{green!8}{\parbox{0.97\linewidth}{\textbf{\textcolor{green!50!black}{NEW (downup\_ac\_pop):}}\par\vspace{0.4em}\centering\begin{adjustbox}{max width=\linewidth}#1\end{adjustbox}}}\end{center}}" _n
file write `cmp' "\begin{document}" _n
file write `cmp' "\begin{center}{\Huge\bfseries Rural Replication Comparison}\\[0.4em]" _n
file write `cmp' "{\large Treatment: \texttt{downup\_ac} vs \texttt{downup\_ac\_pop}}\\[0.4em]" _n
file write `cmp' "{\normalsize Generated \today}\end{center}" _n
file write `cmp' "\vspace{1em}" _n
file write `cmp' "\noindent Each section shows the original specification (red, treatment = \texttt{downup\_ac}) above the new specification (green, treatment = \texttt{downup\_ac\_pop}). Both tex files are produced by the \texttt{\_generate\_all\_tables} dofiles in \texttt{code/\_replication\_rural} and \texttt{code/\_replication\_rural\_acpop}.\par" _n
file write `cmp' "\newpage" _n

* Emit a comparison section: title (already TeX-escaped), old tex stem, new tex stem
capture program drop _cmpsection
program define _cmpsection
    args fh title old new
    file write `fh' "\section{`title'}" _n
    file write `fh' "\noindent\textbf{Original file:} \texttt{`old'}\par" _n
    file write `fh' "\OLD{\IfFileExists{`old'}{\input{`old'}}{\textit{(missing: `old')}}}" _n
    file write `fh' "\vspace{0.4em}" _n
    file write `fh' "\noindent\textbf{New file:} \texttt{`new'}\par" _n
    file write `fh' "\NEW{\IfFileExists{`new'}{\input{`new'}}{\textit{(missing: `new')}}}" _n
    file write `fh' "\clearpage" _n
end

_cmpsection `cmp' "Main DiD (\_main\_1\_did)" ///
    "main_did_downup_area_ac${sample}_rural.tex" ///
    "main_did_downup_area_ac${sample}_rural_acpop.tex"

_cmpsection `cmp' "Bureaucrat $\times$ Politician DiD (\_main\_3\_bureau\_polisc\_did)" ///
    "_main_3_bureau_polisc_did${sample}_rural.tex" ///
    "_main_3_bureau_polisc_did${sample}_rural_acpop.tex"

_cmpsection `cmp' "Protest DiD with Down$>$Up (\_main\_4\_protest\_5km\_fe12\_did\_downup)" ///
    "_main_4_protest_5km_fe12_did_downup${sample}_rural.tex" ///
    "_main_4_protest_5km_fe12_did_downup${sample}_rural_acpop.tex"

_cmpsection `cmp' "Politician Char DiD with Down$>$Up (\_main\_5\_polischar\_fe12\_did\_downup\_inter)" ///
    "_main_5_polischar_fe12_did_downup_inter${sample}_rural.tex" ///
    "_main_5_polischar_fe12_did_downup_inter${sample}_rural_acpop.tex"

_cmpsection `cmp' "Alternative DVs (\_app\_7\_main\_did\_downup\_area\_ac\_dv)" ///
    "_app_7_main_did_downup_area_ac_dv${sample}_rural.tex" ///
    "_app_7_main_did_downup_area_ac_dv${sample}_rural_acpop.tex"

_cmpsection `cmp' "DiD by Year (\_app\_8\_main\_did\_by\_year)" ///
    "_app_8_main_did_by_year${sample}_rural.tex" ///
    "_app_8_main_did_by_year${sample}_rural_acpop.tex"

_cmpsection `cmp' "DiD by State (\_app\_9\_main\_did\_by\_state)" ///
    "_app_9_main_did_by_state${sample}_rural.tex" ///
    "_app_9_main_did_by_state${sample}_rural_acpop.tex"

_cmpsection `cmp' "Rice Moderators (\_app\_10\_did\_rice\_moderators)" ///
    "_app_10_did_rice_moderators${sample}_rural.tex" ///
    "_app_10_did_rice_moderators${sample}_rural_acpop.tex"

_cmpsection `cmp' "Politician Rice Mods (\_app\_14\_polischar\_fe12\_did\_ricemods)" ///
    "_app_14_polischar_fe12_did_ricemods${sample}_rural.tex" ///
    "_app_14_polischar_fe12_did_ricemods${sample}_rural_acpop.tex"

_cmpsection `cmp' "Politician FE DiD (\_app\_15\_polischar\_fe12\_did)" ///
    "_app_15_polischar_fe12_did${sample}_rural.tex" ///
    "_app_15_polischar_fe12_did${sample}_rural_acpop.tex"

_cmpsection `cmp' "Downwind Heterogeneity (\_app\_20\_did\_downwind\_hm)" ///
    "_app_20_did_downwind_hm${sample}_rural.tex" ///
    "_app_20_did_downwind_hm${sample}_rural_acpop.tex"

file write `cmp' "\end{document}" _n
file close `cmp'

display "Comparison document: ${tables}/_comparison_downup_ac_vs_acpop${sample}.tex"
display "Compile with: pdflatex ${tables}/_comparison_downup_ac_vs_acpop${sample}.tex"

********************************************************************************
display "All rural-acpop tables generated successfully."
********************************************************************************

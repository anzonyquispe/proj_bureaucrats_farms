********************************************************************************
* One-off helper: regenerates all sections whose ster files are present.
* Sections 3 and 4 (_main_4, _main_5) require ster files that have not yet
* arrived from the cluster — they will pick up the same formatting
* automatically once those ster files land.
********************************************************************************

clear all
set more off

global location "dbox"
global sample ""
global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
global root "$dbox"
global tables "${root}/tex/paper/tables"

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

* ----- Section 5: _app_6_main_did_treat_definition -----
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
          fmt(%12.0fc %s %s %s %s) ///
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

* ----- Section 6: _app_7_main_did_downup_area_ac_dv -----
est clear
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

* ----- Section 7: _app_8_main_did_by_year -----
est clear
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

* ----- Section 8: _app_9_main_did_by_state -----
est clear
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
            " & \multicolumn{4}{c}{Number of Fires (x 1,000 units)}\\" ///
            " & Bihar & Haryana & Punjab & Uttar Pradesh \\ \hline") ///
    posthead("") ///
    postfoot("\hline" "\end{tabular}")

* ----- Section 9: _app_10_did_rice_moderators -----
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
            "       & \multicolumn{3}{c}{Number of Fires (x 1,000 units) - Rural Grids}\\" ///
            "                                                              & (1)            & (2)            & (3)\\\\  " ///
            "      \midrule") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}")

* ----- Section 10: _app_11_placebo_pop_13km -----
est clear
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
            "       & \multicolumn{3}{c}{Number of Fires (x 1,000 units) - Rural Grids}\\" ///
            "    & Full Sample           &  Treated for Politicians             & Control for Politicians \\\\  \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}")

* ----- Section 11: _app_12_protest_5km_fe_did -----
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
    stats(N acq gridfe time electionfe provtrendfe ymean_clean, ///
          fmt(%12.0fc %12.0fc %s %s %s %s %s) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "Grid FE" "Relative Time FE" "Legislature FE" "Province Trend FE" "Mean DV")) ///
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

* ----- Section 12: _app_13_protest_5km_fe12_did_ricemods -----
est clear
estread using "${tables}/_app_13_protest_5km_fe12_did_ricemods${sample}_rural.ster"
_strip_zeros_stats, models(eq1 eq2 eq3) stats(ymean ymean2 ymean3)
esttab eq1 eq2 eq3 ///
    using "${tables}/_app_13_protest_5km_fe12_did_ricemods${sample}_rural.tex", ///
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
          labels("Observations" "N Assembly Constituencies" "Grid FE" "Relative Time FE" "Legislature FE" "Province Trend FE" "Mean DV" "Mean DV2" "Mean DV3")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{3}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)}         \\\\" ///
            "            &\multicolumn{3}{c}{Number of Fires (x 1,000 units) - Rural Grids} \\\\ \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}" "}")

* ----- Section 13: _app_14_polischar_fe12_did_ricemods -----
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
                 "Grid FE" "Relative Time FE" "Legislature FE" "Province Trend FE" ///
                 "Mean DV" "Mean DV2" "Mean DV3")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{4}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)} &\multicolumn{1}{c}{(4)}         \\" ///
            "            & \multicolumn{4}{c}{Number of Fires (x 1,000 units) - Rural Grids} \\ \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}" "}")

* ----- Section 14: _app_15_polischar_fe12_did -----
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
                 "Grid FE" "Relative Time FE" "Legislature FE" "Province Trend FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{3}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)}         \\" ///
            "            & \multicolumn{3}{c}{Number of Fires (x 1,000 units) - Rural Grids} \\ \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Done regenerating sections 5-14"

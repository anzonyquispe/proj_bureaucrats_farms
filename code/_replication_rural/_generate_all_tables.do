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
* 1. Main DiD Table (_main_1_did)
********************************************************************************

estread using "${tables}/main_did_downup_area_ac${sample}_rural.ster"

esttab eq1 eq2 eq3 eq4 using "${tables}/main_did_downup_area_ac${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac) ///
    order(downup_ac) ///
    varlabels(downup_ac "Down \$>\$ Up") ///
    stats(N acq ymean monthyearfe acfe acmonthfe gridfe, ///
          fmt(%12.0fc %12.0fc %12.3fc %s %s %s %s) ///
          labels("Observations" "Assembly" "Mean DV" ///
                 "Month Year FE" "AC FE" "AC x Month FE" "Grid FE")) ///
    nomtitles ///
    collabels(none) ///
    nobaselevels ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{4}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)}         &\multicolumn{1}{c}{(4)}         \\" ///
            "            & \multicolumn{4}{c}{Number of Fires (x 1,000 units) - Rural Grids} \\ \hline") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Generated: main_did_downup_area_ac_rural.tex"

********************************************************************************
* 2. Bureaucrat-Politician DiD (_main_3_bureau_polisc_did)
********************************************************************************

estread using "${tables}/_main_3_bureau_polisc_did${sample}_rural.ster"

esttab eq1 eq2 eq3 eq4 eq5 using "${tables}/_main_3_bureau_polisc_did${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac downup_dummy downup_interaction) ///
    order( downup_dummy downup_ac downup_interaction) ///
    varlabels(downup_ac "Down\$>\$ Up Politician" ///
              downup_dummy "Down\$>\$ Up Bureaucrat" ///
              downup_interaction "Down\$>\$ Up Pol. \$\times\$ Down\$>\$ Up Bur.") ///
    stats(N           monthyearfe acfe acmonthfe gridfe ymean 	ymean2, ///
          fmt(%12.0fc %s 			%s %s 			%s %12.3fc  %12.3fc) ///
          labels("Observations" "Month year fe" "AC fe" "AC x Month fe" "Grid fe" "Mean DV" "Mean DV2")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("{\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{5}{c}}" ///
            "\hline" ///
            " & (1) & (2) & (3) & (4) & (5) \\\\" ///
            " & \multicolumn{5}{c}{N Fires (in 1,000 units) - Rural Grids} \\\\ \hline") ///
    posthead("") ///
    prefoot(" & & & & & \\\\ \hline") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Generated: _main_3_bureau_polisc_did_rural.tex"

********************************************************************************
* 3. Protest DiD with Downup (_main_4_protest_5km_fe12_did_downup)
********************************************************************************
est clear
estread using "${tables}/_main_4_protest_5km_fe12_did_downup${sample}_rural.ster"

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
    stats(      N    acq  ymean ymean2 		ymean3	 gridfe  time   electionfe provtrendfe, ///
          fmt(%12.0fc  %s    %s %12.3fc    	%12.3fc		%s   %s     %s.          %s) ///
          labels("Observations" "Assembly" "Mean DV" "Mean DV2" "Mean DV3" ///
                 "Grid FE" "Time FE" "Election FE" "Province Trend FE")) ///
    nomtitles nonumbers ///
    mgroups("", pattern(0 0 0 0 0 0)) ///
    collabels(none) ///
    nobaselevels ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{6}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)}         &\multicolumn{1}{c}{(4)}         &\multicolumn{1}{c}{(5)}         &\multicolumn{1}{c}{(6)}         \\" ///
            "            & \multicolumn{6}{c}{Number of Fires (x 1,000 units) - Rural Grids} \\ \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Generated: _main_4_protest_5km_fe12_did_downup_rural.tex"

********************************************************************************
* 4. Politician Char DiD with Downup (_main_5_polischar_fe12_did_downup_inter)
********************************************************************************
est clear
estread using "${tables}/_main_5_polischar_fe12_did_downup_inter${sample}_rural.ster"

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
    stats(      N        acq     ymean   ymean2  ymean3  gridfe time govyearfe provtrendfe, ///
          fmt( %12.0fc %12.0fc   %12.3fc   %12.3fc	   %s	  %s    %s       %s          %s) ///
          labels("Observations" "Assembly" "Mean DV" "Mean DV2" "Mean DV3" ///
                 "Grid FE" "Time FE" "Election FE" "Province Trend FE")) ///
    nomtitles nonumbers ///
    mgroups("", pattern(0 0 0 0 0 0)) ///
    collabels(none) ///
    nobaselevels ///
    prehead("{" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\begin{tabular}{l*{6}{c}}" ///
            "\hline" ///
            "            &\multicolumn{1}{c}{(1)}         &\multicolumn{1}{c}{(2)}         &\multicolumn{1}{c}{(3)}         &\multicolumn{1}{c}{(4)}         &\multicolumn{1}{c}{(5)}         &\multicolumn{1}{c}{(6)}         \\" ///
            "            & \multicolumn{6}{c}{Number of Fires (x 1,000 units) - Rural Grids} \\ \hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}" "}")

display "Generated: _main_5_polischar_fe12_did_downup_inter_rural.tex"

********************************************************************************
* 5. Treatment Definition Robustness (_app_6_main_did_treat_definition)
********************************************************************************
est clear
estread using "${tables}/_app_6_main_did_treat_definition${sample}_rural.ster"

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
    stats(N acq gridfe acmonthfe ymean, ///
          fmt(%12.0fc %s %s %s %s) ///
          labels("Observations" "Assembly" "Grid FE" "Assembly \$\times\$ MonthYear FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("\begin{tabular}{lccccc}" ///
            "\hline" ///
            "& (1) & (2) & (3) & (4) & (5)\\" ///
            "& \multicolumn{5}{c}{Number of Fires (x 1,000 units) - Rural Grids}\\" ///
            "\hline") ///
    posthead("") ///
    prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}")

display "Generated: _app_6_main_did_treat_definition_rural.tex"

********************************************************************************
* 6. Alternative DVs (_app_7_main_did_downup_area_ac_dv)
********************************************************************************

estread using "${tables}/_app_7_main_did_downup_area_ac_dv${sample}_rural.ster"

esttab eq1 eq2 eq3 ///
    using "${tables}/_app_7_main_did_downup_area_ac_dv${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(4) star) se(par fmt(4))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac) ///
    varlabels(downup_ac "Down \$>\$ Up") ///
    stats(N acq gridfe acmonthfe ymean, ///
          fmt(%12.0fc %s %s %s %s) ///
          labels("Observations" "Assembly" "Grid FE" "Assembly \$\times\$ MonthYear FE" "Mean DV")) ///
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

esttab eq1 eq2 eq3 eq4 eq5 eq6 eq7 eq8 eq9 eq10 ///
    using "${tables}/_app_8_main_did_by_year${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac) ///
    varlabels(downup_ac "Down\$>\$Up") ///
    stats(N acq gridfe acmonthfe ymean, ///
          fmt(%12.0fc %s %s %s %s) ///
          labels("Observations" "Assembly" "Grid FE" "Assembly x MonthYear FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("\begin{tabular}{lcccccccccc} \hline" ///
            " & (1) & (2) & (3) & (4) & (5) & (6) & (7) & (8) & (9) & (10) \\" ///
            " & \multicolumn{10}{c}{Number of Fires (x 1,000 units) - Rural Grids}\\" ///
            " & 2012/2013 & 2013/2014 & 2014/2015 & 2015/2016 & 2016/2017 & 2017/2018 & 2018/2019 & 2019/2020 & 2020/2021 & 2021/2022 \\ \hline") ///
    posthead("") ///
    prefoot(" &  &  &  &  &  &  &  &  &  &  \\ \hline") ///
    postfoot("\hline" "\end{tabular}")

display "Generated: _app_8_main_did_by_year_rural.tex"

********************************************************************************
* 8. DiD by State (_app_9_main_did_by_state)
********************************************************************************

estread using "${tables}/_app_9_main_did_by_state${sample}_rural.ster"

esttab eq1 eq2 eq3 eq4 ///
    using "${tables}/_app_9_main_did_by_state${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac) ///
    varlabels(downup_ac "Down\$>\$Up") ///
    stats(N acq gridfe acmonthfe ymean, ///
          fmt(%12.0fc %s %s %s %s) ///
          labels("Observations" "Number of Assembly" "Grid FE" "Assembly $\$\times\$$ MonthYear FE" "Mean DV")) ///
    nomtitles nonumbers ///
    collabels(none) ///
    nobaselevels ///
    prehead("\begin{tabular}{lcccc} \hline" ///
            " & (1) & (2) & (3) & (4) \\" ///
            " & \multicolumn{4}{c}{Number of Fires (x 1,000 units) - Rural Grids}\\" ///
            " & Bihar & Haryana & Punjab & Uttar Pradesh \\ \hline") ///
    posthead("") ///
    prefoot(" &  &  &  &  \\ \hline") ///
    postfoot("\hline" "\end{tabular}")

display "Generated: _app_9_main_did_by_state_rural.tex"

********************************************************************************
* 9. Rice Moderators (_app_10_did_rice_moderators)
********************************************************************************
est clear
estread using "${tables}/_app_10_did_rice_moderators${sample}_rural.ster"

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
    stats(N acq gridfe acmonthfe ymean ymean2 ymean3, ///
          fmt(%12.0fc %12.0fc %s %s  %s %s) ///
          labels("Observations" "Number of Assembly" "Grid FE" ///
                 "AC \$\times\$ MonthYear FE" "Mean DV" "Mean DV2" "Mean DV3")) ///
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

display "Generated: _app_10_did_rice_moderators_rural.tex"

********************************************************************************
* 10. Placebo Pop 13km (_app_11_placebo_pop_13km)
********************************************************************************
est dir
estread using "${tables}/_app_11_placebo_pop_13km${sample}_rural.ster"

esttab eq1 eq2 eq3 ///
    using "${tables}/_app_11_placebo_pop_13km${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(4) star) se(par fmt(4))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_pop_13km) ///
    varlabels(downup_pop_13km "Down\$>\$Up (Placebo)") ///
    stats(N acq gridfe acmonthfe ymean, ///
          fmt(%12.0fc %s %s %s %s) ///
          labels("Observations" "Assembly" "Grid FE" ///
                 "Assembly \$\times\$ MonthYear FE" "Mean DV")) ///
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

display "Generated: _app_11_placebo_pop_13km_rural.tex"

********************************************************************************
* 11. Protest 5km FE DiD (_app_12_protest_5km_fe_did)
********************************************************************************
est clear
estread using "${tables}/_app_12_protest_5km_fe_did${sample}_rural.ster"

esttab evreg1 evreg2 evreg3 ///
    using "${tables}/_app_12_protest_5km_fe_did${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(1.post_#1.treat) ///
    order(1.post_#1.treat) ///
    varlabels(1.post_#1.treat "Post \$\times\$ Protest") ///
    stats(		N 		acq 	ymean 		gridfe time electionfe provtrendfe, ///
          fmt(%12.0fc %12.0fc 	%12.3fc 	%s 		%s 		%s 		%s) ///
          labels("Observations" "Assembly" "Mean DV" ///
                 "Grid FE" "Time FE" "Election FE" "Province Trend FE")) ///
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

display "Generated: _app_12_protest_5km_fe_did_rural.tex"

********************************************************************************
* 12. Protest Rice Mods (_app_13_protest_5km_fe12_did_ricemods)
********************************************************************************
est clear
estread using "${tables}/_app_13_protest_5km_fe12_did_ricemods${sample}_rural.ster"

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
    stats(N acq gridfe time electionfe provtrendfe ymean ymean2 ymean3, ///
          fmt(%12.0fc %12.0fc %s %s %s %s %12.3fc %12.3fc %12.3fc) ///
          labels("Observations" "Number of Assembly" "Grid FE" "Time FE" "Election FE" "Province Trend" "Mean DV" "Mean DV2" "Mean DV3")) ///
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

display "Generated: _app_13_protest_5km_fe12_did_ricemods_rural.tex"

********************************************************************************
* 13. Politician Rice Mods (_app_14_polischar_fe12_did_ricemods)
********************************************************************************
est clear
estread using "${tables}/_app_14_polischar_fe12_did_ricemods${sample}_rural.ster"

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
    stats(        N   acq         ymean 	ymean2 	ymean3 gridfe time electionfe provtrendfe, ///
          fmt(%12.0fc   %12.3fc   %s  		%s    	%s     %s  		%s    %s         %s) ///
          labels("Observations" "Number of Assembly" "Mean DV" "Mean DV2" "Mean DV3" ///
                 "Grid FE" "Time FE" "Elections FE" "Province Trend FE")) ///
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

display "Generated: _app_14_polischar_fe12_did_ricemods_rural.tex"

********************************************************************************
* 14. Politician FE DiD (_app_15_polischar_fe12_did)
********************************************************************************
est clear
estread using "${tables}/_app_15_polischar_fe12_did${sample}_rural.ster"

esttab evreg1 evreg2 evreg3 ///
    using "${tables}/_app_15_polischar_fe12_did${sample}_rural.tex", ///
    replace ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(1.post_#1.treat) ///
    order(1.post_#1.treat) ///
    varlabels(1.post_#1.treat "Post \$\times\$ Agriculturalist") ///
    stats(        N   acq         ymean   gridfe time electionfe provtrendfe, ///
          fmt(%12.0fc   %12.3fc   %12.3fc     %s  %s    %s            %s) ///
          labels("Observations" "Number of Assembly" "Mean DV" ///
                 "Grid FE" "Time FE" "Elections FE" "Province Trend FE")) ///
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

display "Generated: _app_15_polischar_fe12_did_rural.tex"

********************************************************************************
display "All rural tables generated successfully."
********************************************************************************

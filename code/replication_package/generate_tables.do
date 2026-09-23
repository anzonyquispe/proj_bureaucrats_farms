********************************************************************************
* Single table renderer for every reproducible table actively input by main.tex
********************************************************************************

if "$root" == "" do "config.do"

capture program drop rp_render
program define rp_render
    syntax, STER(string) MODELS(string) OUT(string) [KEEP(string)]

    est clear
    capture noisily estread using `"`ster'"'
    local read_rc = _rc
    if `read_rc' {
        display as error "Required estimates not found: `ster'"
        exit `read_rc'
    }

    if `"`keep'"' == "" {
        esttab `models' using `"`out'"', replace ///
            cells(b(fmt(3) star) se(par fmt(3))) ///
            star(* 0.10 ** 0.05 *** 0.01) ///
            stats(N acq ymean ymean2 ymean3, ///
                fmt(%12.0fc %12.0fc 3 3 3) ///
                labels("Observations" "N Assembly Constituencies" ///
                       "Mean DV" "Mean DV, moderator=1" "Mean DV, moderator=0")) ///
            nomtitles nonumbers collabels(none) nobaselevels
    }
    else {
        esttab `models' using `"`out'"', replace ///
            cells(b(fmt(3) star) se(par fmt(3))) ///
            star(* 0.10 ** 0.05 *** 0.01) ///
            keep(`keep') ///
            stats(N acq ymean ymean2 ymean3, ///
                fmt(%12.0fc %12.0fc 3 3 3) ///
                labels("Observations" "N Assembly Constituencies" ///
                       "Mean DV" "Mean DV, moderator=1" "Mean DV, moderator=0")) ///
            nomtitles nonumbers collabels(none) nobaselevels
    }
    display "Generated: `out'"
end

* Main DiD.
rp_render, ster("${tables}/main_did_downup_area_ac${sample}_rural.ster") ///
    models("eq1 eq2 eq3 eq4") ///
    out("${tables}/main_did_downup_area_ac${sample}_rural.tex") ///
    keep("downup_ac")

rp_render, ster("${tables}/main_did_downup_area_ac${sample}_rural_acpop_stacked.ster") ///
    models("eq1 eq2 eq3 eq4") ///
    out("${tables}/main_did_downup_area_ac${sample}_rural_acpop.tex") ///
    keep("downup_ac")

* Bureaucrat x politician DiD.
rp_render, ster("${tables}/_main_3_bureau_polisc_did${sample}_rural.ster") ///
    models("eq1 eq2 eq3 eq4 eq5") ///
    out("${tables}/_main_3_bureau_polisc_did${sample}_rural.tex") ///
    keep("downup_dummy downup_ac downup_interaction")

rp_render, ster("${tables}/_main_3_bureau_polisc_did${sample}_rural_acpop_stacked.ster") ///
    models("eq1 eq2 eq3 eq4 eq5") ///
    out("${tables}/_main_3_bureau_polisc_did${sample}_rural_acpop.tex") ///
    keep("downup_dummy downup_ac_pop downup_interaction")

* Treatment definitions.
rp_render, ster("${tables}/_app_6_main_did_treat_definition${sample}_rural.ster") ///
    models("eq1 eq2 eq3 eq4 eq5") ///
    out("${tables}/_app_6_main_did_treat_definition${sample}_rural.tex") ///
    keep("downup_ac downup_ac_pop downup_1sd down_percent downup_diff_percent")

rp_render, ster("${tables}/_app_6_main_did_treat_definition${sample}_rural_acpop.ster") ///
    models("eq1 eq2 eq3 eq4 eq5") ///
    out("${tables}/_app_6_main_did_treat_definition${sample}_rural_acpop.tex") ///
    keep("downup_ac_pop downup_ac downup_1sd_pop down_percent_pop downup_diff_percent_pop")

* Alternative dependent variables.
rp_render, ster("${tables}/_app_7_main_did_downup_area_ac_dv${sample}_rural.ster") ///
    models("eq1 eq2 eq3") ///
    out("${tables}/_app_7_main_did_downup_area_ac_dv${sample}_rural.tex") ///
    keep("downup_ac")

rp_render, ster("${tables}/_app_7_main_did_downup_area_ac_dv${sample}_rural_acpop_stacked.ster") ///
    models("eq1 eq2 eq3") ///
    out("${tables}/_app_7_main_did_downup_area_ac_dv${sample}_rural_acpop.tex") ///
    keep("downup_ac_pop")

* Heterogeneity by year and state.
rp_render, ster("${tables}/_app_8_main_did_by_year${sample}_rural.ster") ///
    models("eq1 eq2 eq3 eq4 eq5 eq6 eq7 eq8 eq9 eq10") ///
    out("${tables}/_app_8_main_did_by_year${sample}_rural.tex") keep("downup_ac")

rp_render, ster("${tables}/_app_8_main_did_by_year${sample}_rural_acpop_stacked.ster") ///
    models("eq1 eq2 eq3 eq4 eq5 eq6 eq7 eq8 eq9 eq10") ///
    out("${tables}/_app_8_main_did_by_year${sample}_rural_acpop.tex") keep("downup_ac_pop")

rp_render, ster("${tables}/_app_9_main_did_by_state${sample}_rural.ster") ///
    models("eq1 eq2 eq3 eq4") ///
    out("${tables}/_app_9_main_did_by_state${sample}_rural.tex") keep("downup_ac")

rp_render, ster("${tables}/_app_9_main_did_by_state${sample}_rural_acpop_stacked.ster") ///
    models("eq1 eq2 eq3 eq4") ///
    out("${tables}/_app_9_main_did_by_state${sample}_rural_acpop.tex") keep("downup_ac_pop")

* Placebo and protest DiD.
rp_render, ster("${tables}/_app_11_placebo_pop_13km${sample}_rural.ster") ///
    models("eq1 eq2 eq3") ///
    out("${tables}/_app_11_placebo_pop_13km${sample}_rural.tex") keep("downup_pop_13km")

rp_render, ster("${tables}/_app_12_protest_5km_fe_did${sample}_rural.ster") ///
    models("evreg1 evreg2 evreg3") ///
    out("${tables}/_app_12_protest_5km_fe_did${sample}_rural.tex") keep("*post_*treat*")

* Downwind interactions. The population version intentionally writes the
* exact `_new` filename currently input by main.tex.
rp_render, ster("${tables}/_main_4_protest_5km_fe12_did_downup${sample}_rural.ster") ///
    models("evreg1 evreg2 evreg3 evreg4 evreg5 evreg6") ///
    out("${tables}/_main_4_protest_5km_fe12_did_downup${sample}_rural.tex") ///
    keep("*post_*treat*")

rp_render, ster("${tables}/_main_4_protest_5km_fe12_did_downup${sample}_rural_acpop.ster") ///
    models("evreg1 evreg2 evreg3 evreg4 evreg5 evreg6") ///
    out("${tables}/_main_4_protest_5km_fe12_did_downup${sample}_rural_acpop_new.tex") ///
    keep("*post_*treat*")

rp_render, ster("${tables}/_main_5_polischar_fe12_did_downup_inter${sample}_rural.ster") ///
    models("evreg1 evreg2 evreg3 evreg4 evreg5 evreg6") ///
    out("${tables}/_main_5_polischar_fe12_did_downup_inter${sample}_rural.tex") ///
    keep("*post_*treat*")

rp_render, ster("${tables}/_main_5_polischar_fe12_did_downup_inter${sample}_rural_acpop.ster") ///
    models("evreg1 evreg2 evreg3 evreg4 evreg5 evreg6") ///
    out("${tables}/_main_5_polischar_fe12_did_downup_inter${sample}_rural_acpop.tex") ///
    keep("*post_*treat*")

* Descriptive tables use the clean Python implementation, but this dofile is
* the single public entry point for generating all tables.
shell $python "${code}/python/generate_descriptive_tables.py" ///
    --root "${root}" --sample "${sample}" --rural-var "${is_rural_var}"

********************************************************************************

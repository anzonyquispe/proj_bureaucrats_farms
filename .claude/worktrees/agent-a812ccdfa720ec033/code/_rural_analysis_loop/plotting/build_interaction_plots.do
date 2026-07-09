*-------------------------------------------------------------------------------
* build_full_interaction_plots.do
* For _app_18 (protest DiD x downup_ac) and _app_19 (polischar DiD x downup_ac),
* call interaction_graph on every stored evreg estimate for BOTH rural variants
* (area, farzad) and rename the raw `_<N>.png` outputs into the canonical
* `<app>_<type>_did_downup_fe<N>_<variant>.png` scheme expected by the
* full-report LaTeX.
*
* Naming assumption: the cluster sbatch files for app18/app19 use
* FE_LIST = "1 2 ... 32" (sequential), so slot N == fe N.
*
* Required globals (set by run_full_report.sh):
*   $plot_dir : plotting/ folder
*   $fig_dir  : output PNG directory
*   $tables   : directory holding the .ster files
*   $fe_all   : full FE numlist as a string, e.g. "1 2 ... 32"
*-------------------------------------------------------------------------------

clear all
set more off

foreach g in plot_dir fig_dir tables fe_all {
    if "${`g'}" == "" {
        display as error "build_full_interaction_plots: missing global \${`g'}"
        exit 198
    }
}

qui do "${plot_dir}/tools/interaction_graph.ado"
qui do "${plot_dir}/tools/estload_csv.ado"

local nfe : word count ${fe_all}
local est_numlist "1/`nfe'"

local variants area farzad

foreach v of local variants {

    *-- _app_19 polischar interaction -----------------------------------------
    local ster19 "${tables}/_app_19_polischar_did_downup_inter_plot_rural_`v'.ster"
    capture confirm file "`ster19'"
    if _rc {
        display as error "MISSING: `ster19'"
    }
    else {
        display _n "Interaction plots -- polischar (_app_19, `v')"
        est clear
        local tmp_prefix_19 "${fig_dir}/_tmp_app19_`v'"
        interaction_graph using "`ster19'",  ///
            estimates(`est_numlist')          ///
            output("`tmp_prefix_19'")         ///
            type(politician)                  ///
            modvar(downup_ac)                 ///
            yrange(-20 10)

        * Rename tmp outputs -> canonical names (slot N == fe N)
        forvalues k = 1/`nfe' {
            local fe : word `k' of ${fe_all}
            local src "`tmp_prefix_19'_`k'.png"
            local dst "${fig_dir}/app19_polischar_did_downup_fe`fe'_`v'.png"
            capture confirm file "`src'"
            if !_rc {
                shell mv "`src'" "`dst'"
            }
        }
    }

    *-- _app_18 protest interaction -------------------------------------------
    local ster18 "${tables}/_app_18_protest_5km_did_downup_plot_rural_`v'.ster"
    capture confirm file "`ster18'"
    if _rc {
        display as error "MISSING: `ster18'"
    }
    else {
        display _n "Interaction plots -- protest (_app_18, `v')"
        est clear
        local tmp_prefix_18 "${fig_dir}/_tmp_app18_`v'"
        interaction_graph using "`ster18'",  ///
            estimates(`est_numlist')          ///
            output("`tmp_prefix_18'")         ///
            type(protest)                     ///
            modvar(downup_ac)

        forvalues k = 1/`nfe' {
            local fe : word `k' of ${fe_all}
            local src "`tmp_prefix_18'_`k'.png"
            local dst "${fig_dir}/app18_protest_did_downup_fe`fe'_`v'.png"
            capture confirm file "`src'"
            if !_rc {
                shell mv "`src'" "`dst'"
            }
        }
    }
}

display _n "Full interaction plots complete."

*-------------------------------------------------------------------------------
* build_interaction_plots.do
* For _app_18 and _app_19 .ster files, call interaction_graph on every stored
* evreg estimate and export one PNG per (file, spec).
*
* Required globals (set by orchestrator):
*   $plot_dir      : absolute path to this plotting/ folder
*   $fig_dir       : output directory for PNGs
*   $ster_app18    : path to _app_18 .ster
*   $ster_app19    : path to _app_19 .ster
*   $fe_labels     : space-separated FE indices (e.g. "1 8 16 24 32")
*                    evreg1..evregN correspond to these FE indices in order
*-------------------------------------------------------------------------------

clear all
set more off

foreach g in plot_dir fig_dir ster_app18 ster_app19 fe_labels {
    if "${`g'}" == "" {
        display as error "build_interaction_plots: missing global \${`g'}"
        exit 198
    }
}

qui do "${plot_dir}/tools/interaction_graph.ado"
qui do "${plot_dir}/tools/estload_csv.ado"

* Build a name-style numlist 1..N from the number of FE labels
local nfe : word count ${fe_labels}
local est_numlist "1/`nfe'"

*-------------------------------------------------------------------------------
* _app_18 — protest DiD triple-interaction with downup_ac
*-------------------------------------------------------------------------------

display _n "Interaction plots — protest (_app_18)"
est clear
local prefix_18 "${fig_dir}/app18_protest_did_downup"
interaction_graph using "${ster_app18}",       ///
    estimates(`est_numlist')                   ///
    output("`prefix_18'")                      ///
    type(protest)                              ///
    modvar(downup_ac)

*-------------------------------------------------------------------------------
* _app_19 — polischar DiD triple-interaction with downup_ac
*-------------------------------------------------------------------------------

display _n "Interaction plots — polischar (_app_19)"
est clear
local prefix_19 "${fig_dir}/app19_polischar_did_downup"
interaction_graph using "${ster_app19}",       ///
    estimates(`est_numlist')                   ///
    output("`prefix_19'")                      ///
    type(politician)                           ///
    modvar(downup_ac)                          ///
    yrange(-20 10)

display _n "Interaction plots complete."

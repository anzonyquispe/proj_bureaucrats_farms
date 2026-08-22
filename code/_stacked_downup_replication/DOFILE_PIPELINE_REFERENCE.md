# Production dofile and output reference

This inventory covers the `.do` files located directly in
`code/_stacked_downup_replication`. Files under `exploratory_analysis/` are
deliberate robustness exercises and are not production specifications.

## Sample contract

All regressions using a stacked dataset are estimated on the same sample used
by the corresponding event study. The restriction is imposed immediately after
loading and standardizing the event-time variable, before estimation.

| Stack family | Input | Required production sample |
|---|---|---|
| Main downup area | `combined_dt.csv` | `relative_monthyear` in `[-5, 6]` |
| Main downup population | `combined_dt_pop.csv` | `relative_monthyear` in `[-5, 6]` |
| 13 km placebo | `stacked_downup_13kmpl.csv` | `relative_monthyear` in `[-5, 6]` |
| Neighbour | `stacked_downup_neigh.csv` | `relative_monthyear` in `[-5, 6]` |
| Politician characteristics | `politicians_characteristics_byprov.csv` | `relative_year_bin` in `[-5, 4]` |
| Protest | `stacked_data_protest5km_election_sameterm.csv` | `relative_year_bin` in `[-4, 1]`, same election term, and both pre/post observations |

The `0_master_dataset.csv` descriptive table is not a stacked regression and
therefore does not receive an event-time restriction.

## Main analysis dofiles

| Dofile | What it estimates or generates | Main output |
|---|---|---|
| `_main_1_did.do` | Four-specification stacked DiD. The caller runs it for `downup_ac` with `combined_dt.csv` and for `downup_ac_pop` with `combined_dt_pop.csv`. | `tables/main_did_downup_area_ac*_stacked.ster` and `tables/main_did_downup_pop_ac*_stacked.ster` |
| `_main_2_stacked_event_study_5pre_area.do` | Main area-based monthly event study for periods `-5` to `+6`, with actual period `0` omitted. | `tables/_main_2_stacked_event_study_5pre_area*.ster` and `.csv` |
| `_main_2_stacked_event_study_5pre.do` | Main population-based monthly event study for periods `-5` to `+6`, with actual period `0` omitted. | `tables/_main_2_stacked_event_study_5pre*.ster` and `.csv` |
| `_main_3_bureau_polisc_did.do` | Joint bureaucrat/politician downwind-treatment DiD specifications using the population stack. | `tables/_main_3_bureau_polisc_did*_rural_stacked*.ster` |
| `_main_4_protest_5km_fe12_did_downup.do` | Protest-post DiD and its interaction with either area- or population-based downwind status, using the election-term-cleaned protest stack. | `tables/_main_4_protest_5km_fe12_did_downup*_rural*.ster` |
| `_main_5_polischar_fe12_did_downup_inter.do` | Politician-characteristic post-treatment DiD interacted with area- or population-based downwind status, using the by-province stack and final cohort-ID FE. | `tables/_main_5_polischar_fe12_did_downup_inter*_rural*.ster` |
| `_main_6_neighbour.do` | Neighbour-border regression on the neighbour stack. | `tables/main_figure4_neighbour*_rural*.ster` |
| `_main_6_neighbour_plot.do` | Loads the neighbour estimate and draws the neighbour coefficient figure. | `figures/neighbor_output.pdf` |

`_main_1_did_area.do` is the legacy, hard-coded predecessor of
`_main_1_did.do`. It is retained for reproducibility but is not called by the
production master or cluster submission script.

## Appendix and robustness dofiles

| Dofile | What it estimates or generates | Main output |
|---|---|---|
| `_app_6_main_did_treat_definition.do` | Robustness to alternative population/downwind treatment definitions. | `tables/_app_6_main_did_treat_definition*_rural_acpop*.ster` |
| `_app_7_main_did_downup_area_ac_dv.do` | Alternative outcomes: any fire, log fires, and mean brightness. | `tables/_app_7_main_did_downup_area_ac_dv*_rural_stacked*.ster` |
| `_app_8_main_did_by_year.do` | Main DiD split by agricultural year. | `tables/_app_8_main_did_by_year*_rural_stacked*.ster` |
| `_app_9_main_did_by_state.do` | Main DiD split by state/province. | `tables/_app_9_main_did_by_state*_rural_stacked*.ster` |
| `_app_10_did_rice_moderators.do` | Downwind-treatment heterogeneity by rice area, harvested rice area, and rice production. | `tables/_app_10_did_rice_moderators_rural_stacked.ster` |
| `_app_11_placebo_pop_13km.do` | Population-based 13 km placebo DiD. | `tables/_app_11_placebo_pop_13km*_rural*.ster` |
| `_app_12_protest_5km_fe_did.do` | Baseline protest DiD under three FE specifications, without substantive moderator heterogeneity. | `tables/_app_12_protest_5km_fe_did*_rural.ster` |
| `_app_13_protest_5km_fe12_did_ricemods.do` | Protest DiD heterogeneity by the three rice moderators. | `tables/_app_13_protest_5km_fe12_did_ricemods*_rural.ster` |
| `_app_14_polischar_fe12_did_ricemods.do` | Politician DiD baseline plus three rice-moderator specifications under the final cohort-ID FE. | `tables/_app_14_polischar_fe12_did_ricemods*_rural_stacked.ster` |
| `_app_15_polischar_fe12_did.do` | Politician DiD across three FE robustness variants, all preserving grid-by-cohort-ID and event-year-by-cohort-ID FE. | `tables/_app_15_polischar_fe12_did*_rural_stacked.ster` |
| `_app_16_polischar_fe12_evst_all.do` | Politician event study using the by-province stack. Produces area and population variants; the historical `_controls_both` suffix denotes the unchanged full input composition. | `tables/_app_16_polischar_fe12_evst_all_rural_controls_both*.ster` and `.csv` |
| `_app_17_5km_fe12_evst_all.do` | Protest event studies for never-treated, pooled, and not-yet-treated control definitions, for area and population downwind measures. | `tables/_app_17_5km_fe12_evst_all_rural_controls_{never,both,notyet}*.ster` and `.csv` |
| `_app_18_protest_5km_fe12_did_downup_plot.do` | Stores the protest post-treatment interaction estimates consumed by the interaction graph routine. | `tables/_app_18_protest_5km_fe12_did_downup_plot*_rural*.ster` |
| `_app_19_polischar_fe12_did_downup_inter_plot.do` | Stores the politician post-treatment interaction estimates consumed by the interaction graph routine. | `tables/_app_19_polischar_fe12_did_downup_inter_plot*_rural*.ster` |
| `_app_20_did_downwind_hm.do` | Population-downwind DiD restricted to harvest-month/rice heterogeneity variants. | `tables/_app_20_did_downwind_hm_rural_stacked.ster` |
| `_app_21_5km_allfe_same_term.do` | Legacy 32-FE protest event-study sweep on the cleaned same-term sample. | `tex/paper/tables/_app_21_5km_allfe_same_term*.csv` |

Appendix files 10, 12–15, 20, and 21 are available but are not currently
submitted by `sbatch/submit_all.sh`. They must be launched explicitly if their
tables are required.

## Descriptive and post-processing dofiles

| Dofile | Purpose | Output |
|---|---|---|
| `app_main_descriptive.do` | Descriptive statistics from the unstacked master dataset. | `tables/descriptives_main*.tex` |
| `app_5km_descriptive.do` | Descriptive statistics for the final same-term protest event sample. | `tables/_protest_stacked_descriptive*.tex` |
| `app_polischar_descriptive.do` | Descriptive statistics for the final politician by-province event sample. | `tables/_politicians_stacked_descriptive*.tex` |
| `_export_event_study_csv.do` | Reloads synchronized event-study `.ster` files and exports plot-ready CSVs. | Event-study `.csv` files in `tables/` |
| `_generate_all_tables.do` | Reloads `.ster` files and renders the main and appendix LaTeX regression tables. | `.tex` files in `tables/` |
| `_generate_interaction_plots.do` | Loads the stored interaction estimates and calls `interaction_graph.ado`. | Interaction PDFs in `figures/` |
| `_run_local_ster_postprocessing.do` | Local wrapper that runs event-study CSV export and LaTeX table generation. | The combined CSV/TEX outputs above |

## Orchestration

| Dofile | Purpose |
|---|---|
| `_master_replication.do` | Sequential Stata fallback that runs the active production dofiles in order. Cluster work should normally use `sbatch/submit_all.sh`, which launches the same active estimation families as separate jobs. |

The active cluster pipeline additionally invokes Python and R scripts for maps,
descriptive figures, and event-study plotting. Those are not `.do` files and
are therefore outside this inventory.

## Exploratory analyses

All alternative windows, FE sweeps, control-group experiments, and cohort-event
time robustness checks live under `exploratory_analysis/`. Their window choices
are intentionally encoded inside those scripts and do not define the production
sample. Nothing in that directory is called by `_master_replication.do` or
`sbatch/submit_all.sh`.

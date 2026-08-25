# Main stacked replication pipeline

This document describes the production files submitted by
`sbatch/run_main_replication.sh`. Files under `exploratory_analysis/` are not
part of the production pipeline.

## Launchers

- `sbatch/run_main_replication.sh`: single cluster entry point. Its two
  arguments select `full|sample` data and `all|rice_high` observations.
- `sbatch/submit_all.sh`: scheduler implementation used by the entry point. It
  submits independent estimation jobs, uses three cores for protest jobs and
  one core for other Stata regressions, and writes permanent `.stata.log`
  files through `sbatch/run_dofile.sbatch`.
- `run_main_postprocessing.ps1`: single Windows entry point after synchronizing
  the cluster-generated `tables/` files. It exports event-study CSVs, generates
  LaTeX tables, and plots the four production event studies. Table generation
  and the four R plot processes run concurrently after CSV export.

Cluster event-study dofiles write `.ster` files only. CSV conversion is owned
exclusively by the Windows post-processing stage.

## Execution matrix

From the cluster repository root, use exactly one of:

```bash
bash code/_stacked_downup_replication/sbatch/run_main_replication.sh sample all
bash code/_stacked_downup_replication/sbatch/run_main_replication.sh sample rice_high
bash code/_stacked_downup_replication/sbatch/run_main_replication.sh full all
bash code/_stacked_downup_replication/sbatch/run_main_replication.sh full rice_high
```

After synchronizing `tables/` to Windows, run the matching mode, for example:

```powershell
& "C:\Users\eunic\OneDrive\Documents\GitHub\proj_bureaucrats_farms\code\_stacked_downup_replication\run_main_postprocessing.ps1" `
  -DataSize sample -AnalysisSubsample all -MaxCores 10
```

`sbatch`/`qsub` cannot run locally on Windows. The shell launcher submits the
cluster jobs; the PowerShell launcher performs local post-processing. Permanent
cluster logs are `logs/<job-name>_<job-id>.stata.log` or `.python.log`; scheduler
`.out`/`.err` files are suppressed.

## Shared production rules

1. Every regression begins with a stacked dataset. Where a variable absent
   from a stack must be attached from `0_master_dataset`, the stack remains the
   master side of a row-preserving merge and complete matching is asserted.
2. Main down/up regressions use relative months `-5` through `+6`. Politician
   regressions use relative years `-5` through `+4`. Protest regressions use
   relative years `-4` through `+4` and plots display `-4` through `+1`.
3. All included fixed effects are cohort-specific. Some main-DiD columns
   intentionally have no fixed effects or fewer fixed effects; any grid, time,
   AC-time, province-time, or relative-time FE that is included is interacted
   with the relevant cohort identifier.
4. Multi-specification DiD tables are anchored to `e(sample)` from the richest
   interacted specification. Event-study baseline and moderator estimates are
   also anchored to the richest moderator specification. Disjoint by-year,
   by-state, and placebo subsamples have one specification per column and do
   not share a meaningful cross-column `e(sample)`.
5. Every production analysis, including descriptives, calls
   `_apply_analysis_subsample.do` before its first regression. It is inert for
   `all` and retains `rice_prod_aclvl_ahigh == 1` for `rice_high`.
6. `_sample` inputs and `_rice_high` outputs have distinct filenames and cannot
   overwrite full-sample results.
7. Mode-invariant design and source-data figures run only in `full all` mode;
   sample and rice-high tests cannot overwrite them.

## Production dofiles

| Dofile | Stacked input | Purpose and production specification |
|---|---|---|
| `_main_1_did.do` | `combined_dt.csv` or `combined_dt_pop.csv` | Four main DiD columns. Richest anchor is grid×cohort plus AC×month-year×cohort. Main population treatment is `downup_ac_pop`. |
| `_main_2_stacked_event_study_5pre.do` | `combined_dt_pop.csv` | Main population event study, months `-5…+6`, period `0` omitted. Baseline and rice moderator share the richest-model sample. |
| `_main_2_stacked_event_study_5pre_area.do` | `combined_dt.csv` | Main area event study on the same window and FE structure; produces original, rotated, original HonestDiD, and rotated HonestDiD figures. |
| `_main_3_bureau_polisc_did.do` | `combined_dt_pop.csv` | Bureaucrat × politician table. Attaches `downup_dummy` from master without changing stack rows. Richest district×month-year×cohort model anchors all columns. |
| `_main_4_protest_5km_fe12_did_downup.do` | `stacked_data_protest5km_election_sameterm.csv` | Protest regular and down/up-interacted DiDs. Uses pooled controls, event years `-4…+4`, relative-year×cohort FE, and richest FE3 sample. Submitted for area and population treatments. |
| `_main_5_polischar_fe12_did_downup_inter.do` | `politicians_characteristics_byprov.csv` | Politician regular and down/up-interacted DiDs, years `-5…+4`. Richest FE3 sample anchors all columns. Submitted for area and population treatments. |
| `_main_6_neighbour.do` | `stacked_downup_neigh.csv` | Neighbour-border estimate with grid×cohort and AC-pair×month×year×cohort FE. |
| `_main_6_neighbour_plot.do` | neighbour `.ster` | Generates the neighbour PDF; no regression data are loaded. |
| `_app_6_main_did_treat_definition.do` | `combined_dt_pop.csv` | Seven treatment-definition regressions. Missing treatment measures are attached from master row-preservingly. All equations use grid×cohort and AC×month-year×cohort FE and the first richest-model sample. |
| `_app_7_main_did_downup_area_ac_dv.do` | `combined_dt_pop.csv` | Alternative dependent variables on a common richest-FE observation sample. |
| `_app_8_main_did_by_year.do` | `combined_dt_pop.csv` | Separate agricultural-year estimates; every column uses cohort-interacted richest FE. |
| `_app_9_main_did_by_state.do` | `combined_dt_pop.csv` | Separate province estimates; every column uses cohort-interacted richest FE. |
| `_app_11_placebo_pop_13km.do` | `stacked_downup_13kmpl.csv` | Full/treated/control 13-km placebo columns. Uses grid×cohort and AC×month-year×cohort FE. |
| `_app_16_polischar_fe12_evst_all.do` | `politicians_characteristics_byprov.csv` | Selected politician FE03 event study: grid×cohort, province-cohort trend, and event-year×cohort. Production plots use pooled (`both`) controls and baseline estimate. |
| `_app_17_5km_fe12_evst_all.do` | `stacked_data_protest5km_election_sameterm.csv` | Selected protest FE3 event study over `-4…+4`; production plot shows `-4…+1`. Baseline and rice estimates share the richest sample, but only baseline is a production figure. |
| `_app_18_protest_5km_fe12_did_downup_plot.do` | protest same-term stack | One selected protest DiD interaction estimate used by `interaction_graph.ado`. |
| `_app_19_polischar_fe12_did_downup_inter_plot.do` | politician by-province stack | One selected politician DiD interaction estimate used by `interaction_graph.ado`. |
| `app_main_descriptive.do` | `combined_dt_pop.csv` | Main population descriptive table on the richest main-DiD `e(sample)`. |
| `app_5km_descriptive.do` | protest same-term stack | Protest descriptive table on the richest interacted protest `e(sample)`. |
| `app_polischar_descriptive.do` | politician by-province stack | Politician descriptive table on the richest interacted politician `e(sample)`. |
| `_generate_interaction_plots.do` | four interaction `.ster` files | Produces area/population protest and politician interaction figures. |
| `_generate_all_tables.do` | production `.ster` files | Local LaTeX table generation. Legacy tables are skipped by the production-only bridge. |
| `_export_event_study_csv.do` | production event-study `.ster` files | Local `.ster` to CSV export, filtered exactly by sample and rice-high suffix. |

## Production event-study figures

`plotting_event_studies.R` produces only these main baseline figures through
`run_main_postprocessing.ps1`:

1. `downup_ac` area main event study;
2. `downup_ac_pop` population main event study;
3. politician FE03 event study;
4. protest FE3 event study.

Each receives original, detrended/rotated, original HonestDiD, and rotated
HonestDiD figures. HonestDiD is enabled by default. With `-MaxCores 10`, the
Windows launcher divides nine HonestDiD workers across the four R processes and
reserves one core for concurrent Stata table generation.

## Files intentionally outside production

`_main_1_did_area.do`, `_app_10_*`, `_app_12_*` through `_app_15_*`,
`_app_20_*`, `_app_21_*`, and every dofile below `exploratory_analysis/` are
legacy or exploratory and are not submitted by the production launcher.
`_master_replication.do` is only a sequential fallback; the scheduler pipeline
uses the independent jobs above.

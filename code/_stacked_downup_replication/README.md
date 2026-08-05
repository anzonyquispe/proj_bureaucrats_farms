# Stacked down/up replication workflow

This directory is the analysis-side consumer of the datasets built in
`code/_replication_package/data_generation`.

## Dataset-to-analysis map

| Generated dataset | Treatment / key variable | Analysis dofile(s) |
|---|---|---|
| `combined_dt.csv` | `downup_ac` | `_main_1_did.do`, `_main_2_stacked_event_study_5pre_area.do` |
| `combined_dt_pop.csv` | `downup_ac_pop` | `_main_1_did.do`, `_main_2_stacked_event_study_5pre.do` |
| `politicians_characteristics.csv` | `self_profession_nomiss`, `control_type` | `_main_5_polischar_fe12_did_downup_inter.do`, `_app_16_polischar_fe12_evst_all.do` |
| `stacked_data_protest5km.csv` | `protest5km`, `control_type` | `_main_4_protest_5km_fe12_did_downup.do`, `_app_17_5km_fe12_evst_all.do` |
| `stacked_downup_13kmpl.csv` | `downup_13kmpl` | `_app_11_placebo_pop_13km.do` |

All analyses merge both rural classifiers and filter using `$is_rural_var`.
Input and output filenames also respect `$sample`; the estimate filenames
respect `$ster_suffix`.

The replication sample retains grids that intersect more than one assembly
constituency; the former `grids_with_more_1_ac.dta` exclusion is intentionally
commented out. Whenever the dependent variable is the number of fires, each
dofile rebuilds `countk = count * 1000` and estimates the regression using
`countk`, not raw `count`.

## Entry points

1. Run `_master_replication.do` to estimate the new stacked specifications and
   render available LaTeX tables.
2. Run `plotting_event_studies.R --root /path/to/project --sample ""` to render
   event-study, detrended/rotated, HonestDiD, and rotated-HonestDiD figures.
3. On the cluster, `qsub -V sbatch/_master_replication.sbatch` runs both steps in
   sequence. Its environment overrides are `REPLICATION_ROOT`,
   `REPLICATION_CODE`, `LOCATION`, `SAMPLE`, `IS_RURAL_VAR`, `FE_LIST`, and
   `STER_SUFFIX`.

`_generate_all_tables.do` is deliberately the only `.ster`-to-LaTeX entry
point. It reports missing legacy `.ster` files and continues rendering the
results that are available.

## Control definitions for protest and politician event studies

The baseline filenames retain the paper's treated-plus-never-treated sample.
Additional estimate and figure families use `_controls_both` for never plus
not-yet controls and `_controls_notyet` for not-yet controls alone. See
`OUTPUT_GAPS.md` for exact naming and the audit of active `main.tex` outputs.

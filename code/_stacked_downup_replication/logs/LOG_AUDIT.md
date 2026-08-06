# Replication log audit — 2026-08-06

Only the latest scheduler attempt for each job is retained in this folder.
Superseded attempts, empty `.po*` files, and duplicated `stata_work` copies
were removed.

## Event-study results

All six event-study estimation jobs reached `estwrite` and saved their `.ster`
files. They then failed with Stata `r(198)` because `estsave_csv` was called
with `evreg*`, which that program does not accept. The estimates do not need to
be rerun solely to recover the CSV files; `_export_event_study_csv.do` restores
the saved estimates and exports explicit estimate-name lists.

## Other failures in the latest run

- Seven estimation jobs ended with `r(693)` because an existing `.ster` file
  could not be replaced: `alternative_dv`, `bureau_polisc`, `did_by_state`,
  `did_by_year`, `main_did_area`, `main_did_pop`, and `treatment_defs`.
- `generate_tables` ended with `r(120)` (`invalid %format`).
- `neighbour_plot` ended with `r(111)` because the `plotplainblind` scheme was
  unavailable in that Stata installation.
- `design_maps` could not find `Constituencies_Boundaries_Post_2008.shp`.
- `protest_figures` attempted a pandas merge without an explicit/common key.
- `event_plots` stopped at the first missing newly generated event-study CSV.
- The final strict audit therefore reported 5 code gaps, 32 missing generated
  outputs, and 4 missing static assets.

## Successful latest jobs

The latest descriptive tables, descriptive figures, interaction estimates and
plots, neighbour estimate, 13 km placebo estimate, politician/protest DiD
estimates, and politician/protest interaction estimates completed.

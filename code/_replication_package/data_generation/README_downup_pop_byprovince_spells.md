# Exploratory downup population stacks by province

Run `build_downup_pop_byprovince_spells.sbatch` using `qsub`. This is a separate
exploratory builder and is not called by the production pipeline.

Input: `0_master_dataset.parquet` in the standard intermediate directory.
Treatment: `downup_ac_pop`. All original master columns are retained.
By default the retained history ends in August 2022, without any relative-time
restriction. `--end-year` and `--end-month` can explicitly change that cutoff.
No rural, rice-production, or outcome-completeness filters are applied here.

## Membership

`cohort` is switching calendar month (`year * 12 + month`). `cohort_id` identifies
the pair `(normalized province, cohort)`; use **cohort_id** in all downstream
stack fixed effects, clustering, and unit-stack keys. IDs are deterministic for
a fixed input universe, but can change if new province/date pairs are added.

Treated grids must have an observed consecutive 0-to-1 transition. Their full
membership spans the entire immediately preceding zero spell and the entire
following one spell. The next zero month is excluded. Repeated switches produce
separate memberships in different cohorts. Missing dates and missing treatment
values break spells; no history is bridged across a gap.

A control grid must be observed untreated in the cohort month. Retain its entire
continuous zero spell containing that month, including all available pre and
subsequent untreated months. Stop before its next one month. Past treated spells
do not disqualify an otherwise eligible control. Neither full post-period
coverage nor a strictly positive post observation is required. Both groups must
belong to the cohort's province. Histories are not truncated to the pooled
treated-grid minimum/maximum dates.

The full stack retains cohorts without controls for transparency; these are
flagged in the cohort summary. They should not be treated as having within-cohort
treated-control support. The window summaries also flag missing pre/strict-post
support. These summaries are diagnostics, not implicit sample filters.

## Outputs in the intermediate directory

- `combined_dt_pop_byprov.db`: panel, spells, events, cohorts, interval
  memberships, cohort summaries, and queryable stacked views.
- `combined_dt_pop_byprov_full.csv`: complete retained spells.
- `combined_dt_pop_byprov_m6_p6.csv`: relative months -6 through +6.
- `combined_dt_pop_byprov_m5_p5.csv`: relative months -5 through +5.
- `combined_dt_pop_byprov_m5_p6.csv`: relative months -5 through +6.
- `combined_dt_pop_byprov_cohorts.csv`: province/date and full-stack counts.
- `combined_dt_pop_byprov_m6_p6_cohorts.csv`, `..._m5_p5_cohorts.csv`, and
  `..._m5_p6_cohorts.csv`: window support/count diagnostics.

The three window datasets are row restrictions only. No minimum number of
months, balanced-window requirement, or random subsampling is imposed.
In the database query `final_stack`, `window_m6_p6`, `window_m5_p5`, or
`window_m5_p6`. Expanded stacks are views over interval memberships and the panel
to avoid storing four large copies in the database. CSV exports are streamed.

The builder refuses to overwrite existing outputs. Use a new `--output-dir`
for a repeat experiment. The scheduler log is
`logs/data_generation/build_downup_pop_byprovince_spells.log` under this code
directory. The job requests 10 cores and gives DuckDB a 90GB memory limit, with
disk spill available. Standard analysis and fire-season scripts are unchanged.

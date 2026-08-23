# Final analysis specifications

This file records the production choices selected after the exploratory
analyses. Alternative specifications remain under `exploratory_analysis/`.

## Universal stacked-sample rule

Every production regression or descriptive dofile that reads a stacked
dataset applies the corresponding final event-study window before estimation.
This includes DiD tables, heterogeneity tests, placebo tests, interaction
models, and descriptive outputs—not only the event-study regressions.

- Main downup, 13 km placebo, and neighbour stacks:
  `relative_monthyear` from `-5` through `+6`.
- Politician by-province stack: `relative_year_bin` from `-5` through `+4`.
- Election-term-cleaned protest stack: the full election-term support after
  dropping `relative_year_bin == -5`, requiring both pre- and post-switch
  observations in every grid-cohort.

See `DOFILE_PIPELINE_REFERENCE.md` for the script-by-script inventory.

## Downwind/upwind main analysis

- Area treatment: `combined_dt.csv` and `downup_ac`.
- Population treatment: `combined_dt_pop.csv` and `downup_ac_pop`.
- Both DiD and event-study regressions use the stacked datasets.
- Final relative-month window: `-5` through `+6`.
- Event-study reference period: actual relative month `0`.
- The same window is imposed by `_main_1_did.do` and both
  `_main_2_stacked_event_study_5pre*.do` files.

## Politician-characteristics analysis

- Input: `politicians_characteristics_byprov.csv`.
- Cohort variable: `cohort_id`, the unique province-election cohort.
- Control composition: unchanged full composition supplied by the by-province
  stack (historical output suffix `_controls_both`).
- Analysis window: event years `-5` through `+4`, omitting year `-1`.
- Final absorbed effects:
  - grid x `cohort_id`;
  - event year x `cohort_id`.
- Clustering: AC x election year x `cohort_id`.

## Protest analysis

- Input: `stacked_data_protest5km_election_sameterm.csv`.
- Cohort variable: `cohort_id`, which distinguishes the protest switching month
  and the election term containing that switch.
- Every row must satisfy
  `cohort_term_start <= monthyear <= cohort_analysis_max` and
  `cohort_term_start <= cohort`.
- `cohort`, `cohort_election_year`, `cohort_term_start`, and
  `cohort_analysis_max` must be constant within `cohort_id`.
- Every retained grid x `cohort_id` unit must contain at least one pre-switch
  and one post-switch observation. Production scripts report and remove units
  that fail this condition, then assert it on the estimation sample.
- Event time is measured from the protest date. Relative year -5 is removed,
  all other same-government-term periods are retained, and year -1 is the
  omitted reference.
- The treated, never-treated, and not-yet-treated observations are retained in
  one pooled estimation sample; production code does not iterate over control
  definitions.
- The event study reports the selected FE3 from the reference dofile and also
  absorbs event-year x `cohort_id` effects.
- The canonical protest event study is unmoderated, matching the RA's model.

## Interaction figures

- Control-post and treated-post estimates share the exact same horizontal
  coordinate because both refer to the same post period.
- The plotted p-value is the p-value for the post treated-control contrast and
  is displayed to three decimal places.
- The underlying `lincom` estimands and confidence intervals are unchanged.

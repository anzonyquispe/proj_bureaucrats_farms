# Population event studies omitting period 0

These exploratory specifications reproduce the `downup_ac_pop` event-study
family over relative months -6 through +5, but use relative month 0 as the
reference category. The existing period--1-normalized results are unchanged.

| Job | Fixed effects | Weather controls | Clustering | Output stem |
|---|---|---|---|---|
| Main | grid x cohort; AC x month-year x cohort | Yes | grid x cohort; AC x cohort x month-year | `stacked_event_study_pop_5pre_omit0` |
| Grid/month-year baseline | grid x cohort; month-year x cohort | Yes | grid x cohort; AC x cohort x month-year | `stacked_event_study_pop_5pre_grid_monthyear_fe_omit0` |
| No controls | grid x cohort; month-year x cohort | No | grid x cohort; AC x cohort x month-year | `stacked_event_study_pop_5pre_grid_monthyear_fe_nocontrols_omit0` |
| Modified clustering | grid x cohort; month-year x cohort | Yes | grid; month-year | `stacked_event_study_pop_5pre_grid_monthyear_fe_gridmonth_cluster_omit0` |
| No controls + modified clustering | grid x cohort; month-year x cohort | No | grid; month-year | `stacked_event_study_pop_5pre_grid_monthyear_fe_nocontrols_gridmonth_cluster_omit0` |

Each job writes `.ster`, `.csv`, and `_scalars.csv` files to the repository
`tables` directory through `estsave_csv`.

Submit all five jobs on the cluster with:

```bash
cd /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/event_study/omit_period_0/sbatch
bash submit_all_omit0.sh
```

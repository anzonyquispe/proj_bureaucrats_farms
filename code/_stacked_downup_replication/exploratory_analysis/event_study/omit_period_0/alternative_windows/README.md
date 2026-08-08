# Alternative event windows with period 0 omitted

These population-weighted event studies retain the same sample, treatment,
moderators, fixed effects, controls, and clustering alternatives as the
existing omit-period-0 family. Only the retained event window changes.

| Code | Retained periods | Estimated coefficients | Omitted period | Plotted points |
|---|---|---:|---:|---:|
| `m6_p6` | -6 through +6 | 12 | 0 | 13 |
| `m5_p6` | -5 through +6 | 11 | 0 | 12 |

For each window, five specifications are generated:

1. Main grid-by-cohort and AC-by-month-year-by-cohort fixed effects.
2. Grid-by-cohort and month-year-by-cohort fixed effects.
3. Specification 2 without weather controls.
4. Specification 2 clustered by grid and month-year.
5. Specification 4 without weather controls.

Submit all ten jobs on the cluster:

```bash
cd /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/event_study/omit_period_0/alternative_windows/sbatch
bash submit_all_alternative_windows.sh
```

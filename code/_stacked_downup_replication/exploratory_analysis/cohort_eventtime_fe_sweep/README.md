# Cohort-specific event-time FE sweep

This exploratory analysis adds a cohort-specific relative-year fixed effect to
each of the existing 32 FE specifications:

- Politicians by province: `relative_year_bin_aux#cohort_id`, window `-5,...,4`,
  unchanged treated/control composition.
- Protest: `relative_year_bin_aux#cohort`, window `-8,...,1`, treated and
  never-treated observations only.

Both the event study and the `post x treat x downup_ac_pop` DiD interaction use
the same window. Each estimation process imports and prepares its large dataset
once and never uses `preserve`/`restore`. CSV export and plotting occur only
after every assigned regression has written its STER file.

From the cluster repository root:

```bash
bash code/_stacked_downup_replication/exploratory_analysis/cohort_eventtime_fe_sweep/submit_all_cohort_eventtime_fe_sweeps.sh
```

The launcher submits one one-core politician job and five five-core protest
jobs, for a maximum simultaneous allocation of 26 cores.


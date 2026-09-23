# Exploratory DiD windows

This directory reruns the main stacked DiD for four relative-month windows:
`[-6, 6]`, `[-6, 5]`, `[-5, 5]`, and `[-5, 6]`.

Both treatment definitions are estimated:

- area: `combined_dt.csv` with `downup_ac`
- population: `combined_dt_pop.csv` with `downup_ac_pop`

From the cluster repository root, submit all eight regressions and the dependent
table-rendering job with:

```bash
bash code/_stacked_downup_replication/exploratory_analysis/did_windows/sbatch/submit_all_did_windows.sh
```

Estimates and LaTeX tables are written to `tables/exploratory_analysis/`.

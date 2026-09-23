# Above-median rice-production exploratory analysis

This analysis reruns the active estimation pipeline after retaining only rows
with `rice_prod_aclvl_ahigh == 1`. The main analysis remains unchanged whenever
`$analysis_subsample` is empty. Exploratory `.ster` outputs carry `_ricehigh`
after any existing `_stacked` or `_acpop` suffix.

First rebuild the neighbour stack and its sample so the canonical master rice
flag is present:

```bash
qsub code/_stacked_downup_replication/exploratory_analysis/rice_high_subsample/rebuild_neighbour_rice_and_sample.sbatch
```

After that job completes, the launcher defaults to `_sample` inputs:

```bash
bash code/_stacked_downup_replication/exploratory_analysis/rice_high_subsample/submit_rice_high_estimations.sh
```

After validating every sample job, submit the complete datasets explicitly:

```bash
SAMPLE=none bash code/_stacked_downup_replication/exploratory_analysis/rice_high_subsample/submit_rice_high_estimations.sh
```

Protest jobs receive three cores; every other dofile receives one. Plotting,
event-study CSV export, and LaTeX table rendering remain local.

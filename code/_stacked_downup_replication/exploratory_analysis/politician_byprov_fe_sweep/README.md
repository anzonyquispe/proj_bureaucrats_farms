# Politician by-province fixed-effect sweep

This exploratory module uses only the cluster input
`politicians_characteristics_byprov.csv`. It estimates politician event studies
over years `-5,...,4`, omits year `-1`, retains the weather controls, and
clusters by AC-election-year-cohort.

The unique stacked cohort is `cohort_id`, which identifies a
province-election pair. The calendar switching-month variable `cohort` is kept
only as descriptive timing information because Punjab and Uttar Pradesh share
the April 2017 and April 2022 switch months. Every cohort-specific FE and
clustering identifier is therefore constructed with `cohort_id`.

The input dataset's control group is left untouched. There is no filtering or
subdivision by `control_type`. Each of the 32 independent one-core jobs uses the
full eligible rural sample and estimates:

- the baseline event study using a zero-valued `moderator` stub; and
- the DiD interaction `post x treat x downup_ac_pop`, following
  `_app_19_polischar_fe12_did_downup_inter_plot.do`.

The old event-time interaction with `downup_ac_pop` is not part of this report.

The Stata script uses one common complete-case sample for all FE ingredients so
the 32 specifications remain comparable.

## Replace all results with 32 independent cluster jobs

From the repository root on CRC:

```bash
bash code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep/sbatch/submit_all_politician_byprov_fe.sh
```

The launcher submits 32 separately named one-core jobs in a single command.
Each job removes only its own old FE outputs, estimates the event study and DiD
interaction, verifies the replacement files, and writes a stable Stata log.
A held validation job checks all 32 specifications after they finish and
regenerates the original and rotated baseline event-study figures using the
canonical `plotting_event_studies.R` format.

If the launcher reports an older conflicting by-province job, inspect it first.
To replace only the listed conflicting jobs, run:

```bash
CANCEL_CONFLICTING_JOB=1 bash code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep/sbatch/submit_all_politician_byprov_fe.sh
```

To resubmit only FE 7:

```bash
qsub -N polbp_fe07 \
  -v FE_ID=7,REPLACE_RESULTS=1,REPLICATION_REPO=/users/aquisper/proj_bureaucrats_farms \
  code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep/sbatch/run_politician_byprov_fe.sbatch
```

Outputs are saved in:

```text
tables/exploratory_analysis/politician_byprov_fe_sweep/
```

Each FE produces separate event-study and DiD-interaction `.ster`, coefficient
`.csv`, and scalar `_scalars.csv` files. It also generates the DiD interaction
plot with the established `interaction_graph.ado` format. Logs are kept inside
this module's `logs/` directory.

## Plot locally

After copying the corrected outputs to the local tables folder, generate the
baseline event-study panels with the repository's original plotting format:

```powershell
& "C:\Program Files\R\R-4.5.0\bin\Rscript.exe" `
  "code\_stacked_downup_replication\plotting_event_studies.R" `
  --root (Get-Location).Path `
  --output-root (Get-Location).Path `
  --families politician_sweep `
  --skip-honest
```

Regenerate any missing DiD interaction figures in local Stata with:

```stata
do "code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep/generate_politician_byprov_did_interaction_plots.do"
```

Then rebuild the report source:

```powershell
& "C:\Program Files\R\R-4.5.0\bin\Rscript.exe" `
  "code\_stacked_downup_replication\exploratory_analysis\politician_byprov_fe_sweep\build_politician_byprov_fe_sweep_report.R" `
  --root (Get-Location).Path
```

The report places the original and rotated baseline event studies above the
corresponding DiD interaction plot. If a corrected DiD figure is absent, it
shows an explicit missing-result panel instead of substituting the obsolete
event-time interaction. Rotated pre/post averages use the rotated coefficient
vector and transformed covariance matrix.

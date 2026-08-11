# Politician by-province fixed-effect sweep

This exploratory module uses only the cluster input
`politicians_characteristics_byprov.csv`. It estimates politician event studies
over years `-5,...,4`, omits year `-1`, retains the weather controls, and
clusters by AC-election-year-cohort.

The input dataset's control group is left untouched. There is no filtering or
subdivision by `control_type`. Each of the 32 independent one-core jobs uses the
full eligible rural sample and estimates:

- the baseline event study using a zero-valued `moderator` stub; and
- the interaction event study using `downup_ac_pop`.

The Stata script uses one common complete-case sample for all FE ingredients so
the 32 specifications remain comparable.

## Submit all 32 cluster jobs

From the repository root on CRC:

```bash
bash code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep/sbatch/submit_all_politician_byprov_fe.sh
```

To resubmit only FE 7:

```bash
qsub -N polbp_fe07 \
  -v FE_ID=7,REPLICATION_REPO=/users/aquisper/proj_bureaucrats_farms \
  code/_stacked_downup_replication/exploratory_analysis/politician_byprov_fe_sweep/sbatch/run_politician_byprov_fe.sbatch
```

Outputs are saved in:

```text
tables/exploratory_analysis/politician_byprov_fe_sweep/
```

Each FE produces one `.ster`, one coefficient `.csv`, and one scalar
`_scalars.csv` file. Logs are kept inside this module's `logs/` directory.

## Plot locally

After copying the CSV outputs to the local tables folder, either source
`plot_politician_byprov_fe_sweep.R` in RStudio or run:

```powershell
& "code\_stacked_downup_replication\exploratory_analysis\politician_byprov_fe_sweep\run_local_plots.ps1"
```

This creates original and detrended baseline/interaction plots and a
politician-only two-column LaTeX atlas. Protest analysis is intentionally not
included in this stage.


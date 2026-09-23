# Original politician dataset: controls and FE sweep

This exploratory module uses the original cluster input:

```text
/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate/politicians_characteristics.csv
```

It does not modify `_app_19_polischar_fe12_did_downup_inter_plot.do` or
`plotting_event_studies.R`. Their regression and visual conventions are
reproduced in separate exploratory scripts.

## Design

The combined exploratory launcher uses three one-core politician jobs:

```text
32 FE specifications run sequentially inside each control-definition job
```

Control definitions reproduce `_app_16_polischar_fe12_evst_all.do`:

- `never`: treated observations plus `control_type == 1`;
- `both`: treated observations plus both control types; and
- `notyet`: treated observations plus `control_type == 2`, the project's
  legacy partial-zero-spell group.

Each FE estimates both:

1. A baseline event study for relative years `-5,...,4`, omitting `-1`.
2. The `_app_19` DiD interaction `post x treat x downup_ac_pop`.

The dependent post-processing job generates original and rotated event-study
figures, one non-rotated DiD interaction figure per specification, and three
PDF reports.

## Submit politician and protest analyses together

On CRC:

```bash
cd /users/aquisper/proj_bureaucrats_farms
git checkout replication_data
git pull origin replication_data

bash code/_stacked_downup_replication/exploratory_analysis/submit_politician_and_protest_original_controls.sh
```

The command initially submits nine estimation jobs:

- three one-core politician jobs, one per control definition; and
- six five-core protest jobs, split at FE 15/16 within each control definition.

The politician jobs each run FE 1 through 32 sequentially. Together, the nine
estimation jobs request 33 cores. Dependent plotting/reporting jobs are submitted
at the same time but remain held until their regressions finish.

The previous 96-task array runner remains available for targeted legacy use.
Its task mapping is:

```text
1-32   never-treated controls, FE 1-32
33-64  both control types, FE 1-32
65-96  legacy not-yet controls, FE 1-32
```

Monitor with:

```bash
qstat -u "$USER"
```

## Expected PDFs

```text
output/pdf/politician_original_controls_never_report.pdf
output/pdf/politician_original_controls_both_report.pdf
output/pdf/politician_original_controls_notyet_report.pdf
```

Each report contains all 32 FE specifications. Every FE has:

- the original event-study figure;
- the pretrend-rotated event-study figure;
- exactly one non-rotated DiD interaction figure; and
- the event-study coefficient and confidence-interval table.

## Resubmit one failed task

For example, FE 7 with never-treated controls:

```bash
qsub -N pol_orig_never_fe07 \
  -v FE_ID=7,CONTROL_SAMPLE=never,REPLICATION_REPO=/users/aquisper/proj_bureaucrats_farms \
  code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep/sbatch/run_politician_original_controls_fe.sbatch
```

After resubmitting a failed task, submit only post-processing with:

```bash
qsub -v REPLICATION_REPO=/users/aquisper/proj_bureaucrats_farms \
  code/_stacked_downup_replication/exploratory_analysis/politician_original_controls_fe_sweep/sbatch/postprocess_politician_original_controls.sbatch
```

## Local post-processing fallback

If `pdflatex` is unavailable on the cluster, copy the tables and figures to the
local repository and run:

```powershell
& "C:\Program Files\R\R-4.5.0\bin\Rscript.exe" `
  "code\_stacked_downup_replication\exploratory_analysis\politician_original_controls_fe_sweep\plot_politician_original_controls_fe_sweep.R" `
  --root (Get-Location).Path `
  --output-root (Get-Location).Path

& "C:\Program Files\R\R-4.5.0\bin\Rscript.exe" `
  "code\_stacked_downup_replication\exploratory_analysis\politician_original_controls_fe_sweep\build_politician_original_controls_reports.R" `
  --root (Get-Location).Path
```

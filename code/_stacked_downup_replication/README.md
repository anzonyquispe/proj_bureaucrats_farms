# Stacked down/up replication package

This directory is the analysis-side consumer of the datasets built by
`code/_replication_package/data_generation`. Its cluster launcher submits each
result-generating Stata dofile as an independent scheduler job, then submits the
single table builder and the plot jobs with explicit dependencies.

## Cluster paths and one-command launch

The defaults already match the project cluster:

```text
data/output root: /groups/sgulzar/sa_fires/proj_bureaucrats_farms
code root:        /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication
tables output:    /users/aquisper/proj_bureaucrats_farms/tables
figures output:   /users/aquisper/proj_bureaucrats_farms/figures
```

From the login node:

```bash
cd /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication
bash sbatch/submit_all.sh
```

`submit_all.sh` auto-detects Slurm (`sbatch`) or SGE (`qsub`). It does not use a
Stata array: every dofile/variant receives its own job ID and log. The table,
event-plot, interaction-plot, neighbour-plot, and final-audit jobs wait for the
estimates they consume. The final audit uses `afterany`, so it still inventories
missing outputs if an upstream job fails.

Jobs that read `stacked_data_protest5km.csv` request 10 CPUs. This includes its
descriptive table, DiD, event-study, and interaction-estimate jobs. Every other
job requests one CPU, including all jobs based on `politicians_characteristics`,
`combined_dt`, or `combined_dt_pop`, plus table and plot generation. The Stata
processor setting and common BLAS/OpenMP thread limits follow the scheduler
allocation; R and Python post-processing remain single-threaded. On SGE, only
the protest-stack jobs request the `smp` parallel environment.

The old `sbatch/_master_replication.sbatch` name is retained only as a
compatibility dispatcher to `submit_all.sh`.

## Inputs used by active results

| Dataset | Main use |
|---|---|
| `0_master_dataset.csv` | Main descriptives and legacy variables attached to stacks |
| `combined_dt.csv` | Area-weighted down/up DiD and event study |
| `combined_dt_pop.csv` | Population-weighted down/up analyses |
| `politicians_characteristics.csv` | Politician-characteristic DiD/event study |
| `stacked_data_protest5km.csv` | Protest DiD/event study |
| `stacked_downup_13kmpl.csv` | 13 km placebo |
| `stacked_downup_neigh.csv` | Neighbour-border figure |

The last file is produced by the unique-pair neighbour stack builder and must
already be present in `data_output/intermediate`. Rural classification, rice
moderators, population totals, and map shapefiles are also read from the shared
project input/intermediate trees.

All active analysis dofiles merge the single `is_rural` variable from
`ghs_grid_classification_2000.dta` and retain observations with `is_rural == 1`.
The former `grids_with_more_1_ac.dta` exclusion is commented out. Fire-count
regressions rebuild `countk = count * 1000` and use `countk`, not raw `count`.

## Parameters and resubmitting one dofile

The launcher accepts environment overrides:

```bash
SAMPLE=_sample EVENT_FE_LIST=1 \
  bash sbatch/submit_all.sh
```

The exact root overrides are `REPLICATION_ROOT`, `REPLICATION_CODE`, and
`REPOSITORY_ROOT`. The first is the shared data root; the last is the Git
checkout that receives all generated tables and figures.
`STATA_BIN`, `RSCRIPT_BIN`, and `PYTHON_BIN` can select non-default executables.
SGE submissions use `-V`, so these executable overrides reach the jobs.

To submit one Stata dofile manually on Slurm:

```bash
sbatch sbatch/run_dofile.sbatch \
  _main_1_did.do \
  /groups/sgulzar/sa_fires/proj_bureaucrats_farms \
  /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication \
  shell none is_rural 1/4 _stacked downup_ac combined_dt main_did_downup_area_ac
```

Use the same arguments after `qsub -V sbatch/run_dofile.sbatch` on SGE. The
argument bridge sets the five standard globals (`location`, `sample`,
`is_rural_var`, `fe_list`, and `ster_suffix`) before running exactly one dofile.

Stata parameters are passed through environment variables, not appended to the
Stata command. This prevents automatic log filenames containing the code path
and every parameter. Each Stata job now saves its full log as
`logs/<job_name>_<job_id>.stata.log` and mirrors that log to the scheduler's
`.out`, `.o<jobid>`, or SGE parallel-environment `.po<jobid>` stream after
Stata exits. The temporary `logs/stata_work` copy is removed after the
permanent log has been preserved.

To copy all previously generated outputs into the repository and submit the
failed `.ster` producers plus the revised main event studies as independent,
parallel SGE jobs, run the launcher from the code directory:

```bash
bash sbatch/submit_recovery_jobs.sh
```

Do not submit this launcher itself with `qsub`. It calls `qsub` on nine
separate, fixed-stage files named `recover_01_...sbatch` through
`recover_09_...sbatch`. These cluster jobs only generate `.ster` estimates.

After copying or synchronizing all `.ster` files into the repository-level
`tables` folder, run the CSV and LaTeX post-processing locally in Stata:

```stata
do "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms/code/_stacked_downup_replication/_run_local_ster_postprocessing.do"
```

Then generate the event-study figures locally from PowerShell:

```powershell
& "C:\Users\eunic\OneDrive\Documents\GitHub\proj_bureaucrats_farms\code\_stacked_downup_replication\run_local_event_plots.ps1"
```

The plotting runner generates every figure supported by the CSV files present
locally. The production protest event study expects one pooled-control CSV;
alternative control definitions remain confined to `exploratory_analysis/`.

## Table and event-plot structure

`_generate_all_tables.do` is the only `.ster`-to-LaTeX table entry point. Its
active table reads are not wrapped in `capture`, so a missing/corrupt `.ster`
or model name fails the job instead of silently retaining an old table.

`plotting_event_studies.R` is the only event-study/HonestDiD plotting entry
point. The production protest section renders FE1-FE5 from the single pooled
sample, with one baseline plot and one `rice_prod_aclvl_ahigh` interaction plot
for each FE. Politician control-sample robustness naming is unchanged.

## Software expected on compute nodes

Stata needs the project commands already used by the original package,
including `reghdfejl`, `estout`/`esttab`, and their dependencies. R needs
`data.table`, `ggplot2`, and `HonestDiD`.

The Python map/description jobs use the existing geospatial conda environment
at `/groups/sgulzar/india_forest_land/downup_geo`. The launcher calls its Python
executable directly and adds its `bin`, PROJ, and GDAL locations to the job
environment. Override `PYTHON_ENV` or `PYTHON_BIN` only if that environment is
moved. Its packages should cover `python/requirements.txt`; they can be checked
with:

```bash
/groups/sgulzar/india_forest_land/downup_geo/bin/python -c \
  "import geopandas, matplotlib, numpy, pandas, pyarrow, scipy; print('OK')"
```

## Active `main.tex` coverage audit

`python/audit_main_outputs.py` parses only active LaTeX. It excludes percent
comments, `comment` environments, `\iffalse` blocks, and everything after the
first active `\end{document}`. The current audit finds 52 unique active table
or figure references:

- 43 map to generators in this directory;
- 4 are supplied static assets (`cnn.png`, the farmer-protest photograph,
  `myneta_example2.png`, and the compressed rice-grid PDF);
- 5 active tables have no located generating code.

Those five unresolved tables are:

```text
tables/action_final5
tables/action_final6
tables/action_final7
tables/action_final8
tables/action_final_additional_disha
```

Their references are at `main.tex` lines 587, 603, 619, 635, and 2031. No
corresponding dofile/R/Python generator was found in this directory, in
`code/_replication_rural_acpop`, or in the repository history inspected during
the audit. They appear to be the DISHA/eCourts/electoral-action tables. The
strict final audit therefore exits nonzero until their original analysis code
and inputs are added; it does not create placeholders or count them as covered.

See `OUTPUT_GAPS.md` for the concise report and `output_manifest.csv` for every
active reference, its exact `main.tex` line, and its generator.

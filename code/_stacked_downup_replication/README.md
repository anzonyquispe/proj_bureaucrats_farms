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

All active analysis dofiles merge both rural classifiers and filter with
`$is_rural_var`. The former `grids_with_more_1_ac.dta` exclusion is commented
out. Fire-count regressions rebuild `countk = count * 1000` and use `countk`,
not raw `count`.

## Parameters and resubmitting one dofile

The launcher accepts environment overrides:

```bash
SAMPLE=_sample RURAL_VAR=is_rural_farzad EVENT_FE_LIST=1 \
  bash sbatch/submit_all.sh
```

The exact root overrides are `REPLICATION_ROOT` and `REPLICATION_CODE`.
`STATA_BIN`, `RSCRIPT_BIN`, and `PYTHON_BIN` can select non-default executables.
SGE submissions use `-V`, so these executable overrides reach the jobs.

To submit one Stata dofile manually on Slurm:

```bash
sbatch sbatch/run_dofile.sbatch \
  _main_1_did.do \
  /groups/sgulzar/sa_fires/proj_bureaucrats_farms \
  /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication \
  shell none is_rural_area 1/4 _stacked downup_ac combined_dt main_did_downup_area_ac
```

Use the same arguments after `qsub -V sbatch/run_dofile.sbatch` on SGE. The
argument bridge sets the five standard globals (`location`, `sample`,
`is_rural_var`, `fe_list`, and `ster_suffix`) before running exactly one dofile.

Stata parameters are passed through environment variables, not appended to the
Stata command. This prevents automatic log filenames containing the code path
and every parameter. Each Stata job now saves its full log as
`logs/<job_name>_<job_id>.stata.log` and mirrors that log to the scheduler's
`.out`, `.o<jobid>`, or SGE parallel-environment `.po<jobid>` stream after
Stata exits. The isolated automatic log remains under
`logs/stata_work/<job_name>_<job_id>/_run_dofile.log` for diagnosis.

## Table and event-plot structure

`_generate_all_tables.do` is the only `.ster`-to-LaTeX table entry point. Its
active table reads are not wrapped in `capture`, so a missing/corrupt `.ster`
or model name fails the job instead of silently retaining an old table.

`plotting_event_studies.R` is the only event-study/HonestDiD plotting entry
point. For politician and protest event studies it renders:

- baseline filenames: treated plus never-treated controls;
- `_controls_both`: treated plus never- and not-yet-treated controls;
- `_controls_notyet`: treated plus not-yet-treated controls only.

Both area- and population-weighted moderator families are generated. The
population-weighted baseline filenames remain the ones referenced by
`main.tex`.

## Software expected on compute nodes

Stata needs the project commands already used by the original package,
including `reghdfejl`, `estout`/`esttab`, and their dependencies. R needs
`data.table`, `ggplot2`, and `HonestDiD`.

The Python map/description jobs need the packages in
`python/requirements.txt`. If the cluster Python module does not provide them,
create a persistent virtual environment once and expose it to the launcher:

```bash
module load python
python3 -m venv /users/aquisper/proj_bureaucrats_farms/.venv_replication
/users/aquisper/proj_bureaucrats_farms/.venv_replication/bin/pip install \
  -r python/requirements.txt
PYTHON_BIN=/users/aquisper/proj_bureaucrats_farms/.venv_replication/bin/python \
  bash sbatch/submit_all.sh
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

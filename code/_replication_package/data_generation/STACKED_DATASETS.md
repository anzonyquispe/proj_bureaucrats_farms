# Stacked dataset pipeline

`build_all_stacked_datasets_duckdb.py` is the public entry point. It reads
`0_master_dataset.parquet`, validates the required schema before writing any
output, and runs every registered treatment specification by default.

The master sample excludes the entire history of any `unique_small_grid_id`
that has a missing raw or calculation wind direction in any month. Every
stacked output therefore inherits the same wind-complete grid sample.

## Standard outputs

| Treatment | CSV | DuckDB work database |
| --- | --- | --- |
| `downup_ac` | `combined_dt.csv` | `combined_dt.db` |
| `downup_ac_pop` | `combined_dt_pop.csv` | `combined_dt_pop.db` |
| `self_profession_nomiss` | `politicians_characteristics.csv` | `politicians_characteristics.db` |
| `protest5km` | `stacked_data_protest5km.csv` | `stacked_data_protest5km.db` |
| `downup_13kmpl` | `stacked_downup_13kmpl.csv` | `stacked_downup_13kmpl.db` |

The wrapper uses the full time span in the master dataset. A cutoff is applied
only when `--cutoff-year` is explicitly supplied.

## Output schema

Every standard output keeps these source columns:

```text
unique_small_grid_id province distr_id ac_uq_id count mean_brightness month year monthyear
downup_ac downup_ac_pop av_wind_speed wind_direction
rice_prod_aclvl_ahigh election_year yeargov
```

The active source-treatment column is added automatically when it is not
already in that list. The engine then appends:

```text
treat post cohort relative_monthyear
```

`treat` is the stacked treated/control group indicator. `post` equals one when
`monthyear >= cohort`. `relative_monthyear` equals `monthyear - cohort`.

The `self_profession_nomiss` and `protest5km` specifications additionally
append:

```text
relative_year control_type
```

`relative_year = floor(relative_monthyear / 12)`, so event months -12 through
-1 are event year -1 and months 0 through 11 are event year 0. `control_type`
is constant within each grid-cohort stack and is coded as:

```text
0 = treated cohort grid
1 = control observed untreated throughout the retained cohort window
2 = not-yet-treated control observed untreated for only part of that window
```

For Stata, keep treated grids plus only never-treated controls with:

```stata
keep if treat == 1 | control_type == 1
```

Keep treated grids plus only not-yet-treated controls with:

```stata
keep if treat == 1 | control_type == 2
```

No filter is required to use both control groups.

## Commands

Run all specifications:

```bash
python build_all_stacked_datasets_duckdb.py --overwrite
```

Run one or several:

```bash
python build_all_stacked_datasets_duckdb.py \
    --spec downup_ac \
    --spec self_profession_nomiss \
    --overwrite
```

Inspect the configured mappings without reading the master dataset:

```bash
python build_all_stacked_datasets_duckdb.py --list-specs
```

Validate the input and print the planned engine arguments without writing:

```bash
python build_all_stacked_datasets_duckdb.py --dry-run
```

On the cluster, submit `build_stacked_datasets.sbatch`. It runs all five
standard treatments and the province-election politician stack by default.
Set a comma-separated standard subset with, for example,
`STACK_SPECS=downup_ac,downup_ac_pop`. It rebuilds the work databases and
outputs by default because its input master has just been regenerated. Set
`STACK_OVERWRITE=0` only to resume an interrupted run against the unchanged
master Parquet. Set `BUILD_BYPROV=0` only when the alternative politician
stack should be skipped.

To rebuild only the politician-profession and protest stacks with the
year-level/control fields:

```bash
STACK_SPECS='self_profession_nomiss,protest5km' STACK_OVERWRITE=1 \
    qsub -V build_stacked_datasets.sbatch
```

To build the master first and then all five stacked datasets in one cluster
job, submit the combined shell script from the data-generation directory:

```bash
qsub build_master_and_stacked_datasets.sh
```

The shell uses `set -euo pipefail`, so the stacked stage will not start if the
master stage fails. All stages overwrite their existing outputs. By default,
it runs all five registered treatments, the province-election politician
stack, and the neighbour-border stack. The final stage reads
`0_ac_neighs_downup.csv` and writes `stacked_downup_neigh.csv`,
`stacked_downup_neigh.db`, and `stacked_downup_neigh_manifest.csv`.

The combined job suppresses SGE's default `.o<jobid>` and `.e<jobid>` files.
Its readable logs are written to
`code/_replication_package/data_generation/logs/data_generation/`:

```text
00_master_and_stacked_pipeline.log
01_master_dataset.log
02_standard_stacks.log
03_politicians_byprov.log
04_neighbour_stack.log
```

The `00` file is a short pipeline summary. Each numbered stage file contains
the detailed Python output. When a stage fails, the summary identifies the
failed stage and prints the last 80 lines from its detailed log.

The master job reads `9_rice_info_ac_lvl.parquet` and
`panel_data_election_year.parquet` by default. The stack job reads the resulting
`0_master_dataset.parquet` and generates all five standard CSVs.

## Politician stack by province and election

`build_politicians_characteristics_byprov.py` creates the alternative
`politicians_characteristics_byprov.csv` and
`politicians_characteristics_byprov.db`. It runs the
`self_profession_nomiss` clean-spell algorithm separately within each province,
so treated and control grids in a stack always share the same province and
election month.

The standard configuration generates these eight province-election cohorts:

```text
Haryana 2014-11
Bihar 2015-12
Punjab 2017-04
Uttar Pradesh 2017-04
Haryana 2019-11
Bihar 2020-12
Punjab 2022-04
Uttar Pradesh 2022-04
```

The November 2024 Haryana switch is not opened as a new cohort. The full master
time span, including 2023-2024, remains available as post-treatment observations
for earlier cohorts. The output retains the calendar switch in `cohort` and
adds `cohort_id`, `cohort_year`, `cohort_month`, and `cohort_province`.

Submit the dedicated cluster job with:

```bash
qsub build_politicians_characteristics_byprov.sbatch
```

The job overwrites the alternative output and writes a cohort audit file named
`politicians_characteristics_byprov_manifest.csv`.

The final DuckDB contains:

```text
politicians_characteristics_byprov           combined 8-cohort observations
politicians_characteristics_byprov_manifest  one audit row per cohort
final_stack                                  view of the combined observations
```

## Adding another treatment

Add one `StackSpecification` entry to `STACK_SPECIFICATIONS` in the public
wrapper:

```python
StackSpecification(
    treatment_col="new_binary_treatment",
    output_csv="new_stack.csv",
    database="new_stack.db",
    temp_directory="new_stack_duckdb_tmp",
    description="short description",
    extra_columns=("optional_required_column",),
)
```

The new treatment must be binary (`0`, `1`, or missing) and present in the
master dataset. Its source column is retained automatically. Any
`extra_columns` are also required and retained for that specification.

## Tests

From the repository root:

```bash
python -m unittest discover \
    -s code/_replication_package/data_generation/tests -v
```

The tests cover switch detection, treated and control clean spells, `treat`,
`post`, year-level bins, never-treated versus not-yet-treated control codes,
full post-2022 time coverage, required `yeargov`, every registered output, and
automatic treatment-column retention for new specifications.

The existing protest dofiles still reference `stacked_data_protest.csv`; their
filename migration is intentionally deferred.

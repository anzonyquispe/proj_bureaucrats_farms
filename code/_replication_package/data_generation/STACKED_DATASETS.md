# Stacked dataset pipeline

`build_stacked_downup_13kmpl_duckdb.py` is the public entry point. It reads
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
unique_small_grid_id province ac_uq_id count mean_brightness month year monthyear
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

## Commands

Run all specifications:

```bash
python build_stacked_downup_13kmpl_duckdb.py --overwrite
```

Run one or several:

```bash
python build_stacked_downup_13kmpl_duckdb.py \
    --spec downup_ac \
    --spec self_profession_nomiss \
    --overwrite
```

Inspect the configured mappings without reading the master dataset:

```bash
python build_stacked_downup_13kmpl_duckdb.py --list-specs
```

Validate the input and print the planned engine arguments without writing:

```bash
python build_stacked_downup_13kmpl_duckdb.py --dry-run
```

On the cluster, submit `build_stacked_datasets.sbatch`. It runs all treatments
by default. Set a comma-separated subset with, for example,
`STACK_SPECS=downup_ac,downup_ac_pop`. It rebuilds the work databases and
outputs by default because its input master has just been regenerated. Set
`STACK_OVERWRITE=0` only to resume an interrupted run against the unchanged
master Parquet.

To build the master first and release the stacked-data job only after it
succeeds, submit both jobs from the data-generation directory:

```bash
master_job=$(qsub -terse build_0_master_dataset.sbatch)
qsub -hold_jid "${master_job}" build_stacked_datasets.sbatch
```

The master job reads `9_rice_info_ac_lvl.parquet` and
`panel_data_election_year.parquet` by default. The stack job reads the resulting
`0_master_dataset.parquet` and generates all five standard CSVs.

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
`post`, full post-2022 time coverage, required `yeargov`, every registered
output, and automatic treatment-column retention for new specifications.

The existing protest dofiles still reference `stacked_data_protest.csv`; their
filename migration is intentionally deferred.

# Province-election-switch protest event study

This exploratory analysis uses
`stacked_data_protest5km_province_election_switch.csv`, constructed from
`0_master_dataset.parquet` by the data-generation script
`build_stacked_protest_province_election_switch.py`.

The cohort key is `province x election_year x switching month`. Every treated
grid in a cohort switches in that month. Controls share the province and
government term: `control_type = 1` identifies grids never treated in that term;
`control_type = 2` identifies later-treated grids, censored before their switch.
Every retained grid-cohort has an uninterrupted monthly history with at least
one pre- and one post-cohort observation. The sample ends in August 2022, or
earlier when the government term or a not-yet-treated control spell ends.

The event-study dofile estimates FE1-FE5, always adding
`relative_year_bin x cohort_id`. For each FE it saves a baseline model and a
model interacted with `rice_prod_aclvl_ahigh`.

Cluster order:

```bash
qsub code/_replication_package/data_generation/build_stacked_protest_province_election_switch.sbatch
```

After that job completes successfully:

```bash
qsub code/_stacked_downup_replication/exploratory_analysis/protest_province_election_switch/sbatch/run_protest_province_election_switch_event.sbatch
```

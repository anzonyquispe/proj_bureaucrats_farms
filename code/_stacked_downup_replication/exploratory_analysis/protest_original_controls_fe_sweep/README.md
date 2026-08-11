# Stacked protest: controls and FE sweep

This exploratory module uses:

```text
/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate/stacked_data_protest5km.csv
```

It estimates the 32 fixed-effect specifications for three control samples:

- `never`: treated rows and `control_type == 1`;
- `both`: treated rows and both control types;
- `notyet`: treated rows and legacy `control_type == 2` rows.

For every FE/control combination it produces the baseline protest event study
for relative years `-8,...,1` (omitting `-1`) and the DiD interaction
`post x treat x downup_ac_pop`.

The six estimation jobs are organized as follows:

```text
never:  FE 1/15 and FE 16/32
both:   FE 1/15 and FE 16/32
notyet: FE 1/15 and FE 16/32
```

Every protest job requests five cores. The combined launcher also submits three
one-core politician jobs, one per control sample, for a total of nine concurrent
estimation jobs and 33 requested cores.

## Submit politician and protest analyses together

```bash
cd /users/aquisper/proj_bureaucrats_farms
git checkout replication_data
git pull origin replication_data

bash code/_stacked_downup_replication/exploratory_analysis/submit_politician_and_protest_original_controls.sh
```

The launcher also submits dependent postprocessing jobs. Expected protest PDFs:

```text
output/pdf/protest_original_controls_never_report.pdf
output/pdf/protest_original_controls_both_report.pdf
output/pdf/protest_original_controls_notyet_report.pdf
```

The politician analysis reads
`data_output/intermediate/politicians_characteristics${sample}.csv` and creates
the corresponding three politician PDFs already documented in its module.

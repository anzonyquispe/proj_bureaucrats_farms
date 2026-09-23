# Exploratory analyses

This directory contains specifications that are still being evaluated and are
therefore excluded from the main replication-package submission scripts.

## Politician by-province FE sweep

The `politician_byprov_fe_sweep` directory contains the 32-specification
politician event-study sweep based only on
`politicians_characteristics_byprov.csv`. Each FE runs independently with one
core on the input dataset's unchanged control composition and produces both the
baseline and `downup_ac_pop` interaction event studies. Protest analysis is
deferred to a later stage.

## Grid/month-year event studies

The `event_study` directory contains the population and area event studies that
replace AC-by-month-year fixed effects with grid-by-cohort and
month-year-by-cohort fixed effects. The population variants currently cover:

| Variant | Weather controls | Clustering |
|---|---|---|
| Baseline grid/month-year FE | Yes | grid-by-cohort and AC-by-cohort-by-month-year |
| No controls | No | grid-by-cohort and AC-by-cohort-by-month-year |
| Grid/month-year clustering | Yes | grid and month-year |
| No controls + grid/month-year clustering | No | grid and month-year |

All use `downup_ac_pop`, event months -6 through +5, omit -1, and retain six
pretreatment coefficients.

The `event_study/omit_period_0` subdirectory contains a parallel five-model
population family that instead omits relative month 0. It includes the main
AC-by-month-year specification and every grid/month-year robustness listed
above, without modifying the period--1-normalized results.

## de Chaisemartin population analyses

The `dcdh_pop` directory is a population-only copy of the earlier
`code/dCDH_analysis` pipeline. It now reads the current
`data_output/intermediate/0_master_dataset.parquet`; the sample filters and
estimator settings are otherwise unchanged.

Common settings:

- outcome: `countk = count * 1000`
- treatment: `downup_ac_pop`
- group/time: `unique_small_grid_id` / `monthyear`
- controls: `av_wind_speed` and `wind_direction`
- cluster: `ac_uq_id`
- sample: rural grids, excluding `dpl_ac == 1`, through August 2022
- outputs: CSV estimates and PNG event-study plots

The six core specifications are:

| Reset rule | Effects | Placebos | Trend variants |
|---|---:|---:|---|
| No reset; original grid panel | 6 | 6 | none; nonparametric AC trend |
| Reset after six periods in a treatment spell | 6 | 6 | none; nonparametric AC trend |
| Fixed 12-month grid subgroups, without balancing first | 6 | 5 | none; nonparametric AC trend |

Each core specification was also tried separately for treatment switchers into
the treatment (`switchers = "in"`) and out of the treatment
(`switchers = "out"`). Thus the complete production matrix contains 18 runs:
three reset rules x two trend choices x three switcher samples (all, in, out).

On the cluster:

```bash
cd /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/exploratory_analysis/dcdh_pop/sbatch
bash submit_dcdh_pop_sequential.sh       # all 18 specifications
bash submit_dcdh_pop_sequential.sh core  # only the six core specifications
```

The dependency chain requests 60 `largemem` slots for each estimator and
prevents two dCDH jobs from running simultaneously. Each successful job writes
a job-ID sentinel; if a predecessor fails, later jobs leave the queue in order
but stop immediately instead of launching another high-memory estimator.

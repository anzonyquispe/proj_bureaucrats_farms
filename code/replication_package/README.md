# Bureaucrats and farms replication package

This folder consolidates the code that could be traced to **uncommented** table and figure references in `code/_report/main.tex`. References on `%`-commented lines and inside LaTeX `comment` environments are deliberately excluded.

When duplicate versions existed, `code/_stacked_downup_replication` was treated as authoritative. Area-based counterparts were retained from the rural replication folders only where no newer stacked/population version replaced them. The original folders are unchanged.

## Entry points

- `master.do` is the master Stata dofile. It runs every packaged analysis dofile and then the single table dofile and Stata post-estimation plots.
- `generate_tables.do` is the only public table-generation dofile. It renders all traced regression tables and calls the clean Python descriptive-table script.
- `plot_event_studies.R` is the single R entry point for all traced event-study and HonestDiD plots.
- `python/generate_design_maps.py`, `python/generate_descriptive_figures.py`, and `python/generate_protest_figures.py` are clean scripts extracted from the source notebooks. They remain Python, as requested.
- `output_manifest.csv` maps every unique active LaTeX reference to its generating code or audit status.
- `SOURCE_PROVENANCE.csv` records the original source chosen for every packaged analysis dofile.
- `CODE_NOT_FOUND.md` is the requested list of active outputs for which generating code was not located.

The package writes the filenames expected by `main.tex` under `${root}/tex/paper/tables` and `${root}/tex/paper/figures`. It does not overwrite or reorganize `code/_replication_package`.

## Configuration

The shared defaults live in `config.do`. The five analysis globals can be overridden before any analysis runs:

| Global | Default | Purpose |
| --- | --- | --- |
| `$location` | `shell` | Chooses the cluster or Dropbox root. |
| `$sample` | empty | Input/output sample suffix. |
| `$is_rural_var` | `is_rural_area` | Rural-classification variable. |
| `$fe_list` | `1/3` | Stata numlist of fixed-effect specifications. |
| `$ster_suffix` | empty | Estimate-file suffix. Set by `master.do` for each analysis family. |

Cluster defaults are:

```text
root = /groups/sgulzar/sa_fires/proj_bureaucrats_farms
code = /users/aquisper/proj_bureaucrats_farms/code/replication_package
```

Edit only `config.do` if those mounts differ. Run Stata entry points from the `replication_package` directory so `config.do` is discoverable.

## Required data

The scripts expect the existing shared-data layout, chiefly:

```text
${root}/data_output/intermediate/
  0_master_merge_data_gen[SUFFIX].csv
  combined_dt.dta
  combined_dt_pop.dta
  stacked_data_protest[SUFFIX].csv
  politicians_characteristics[SUFFIX].csv
  rice_moderators.dta
  ghs_grid_classification_2000.dta
  grids_with_more_1_ac.dta
  stacked_downup_neigh.csv
  1-grid-generation.shp (+ sidecars)
  _0_2_3_ACs_right_shapefile.shp (+ sidecars)
```

The map/protest scripts also use inputs in the surrounding `sa_fires/data/input` and `sa_fires/proj_downwind` trees. Pass `--shared-root` if `${root}/..` is not that shared root. Each script checks its inputs and raises a path-specific error instead of silently skipping an output.

## Software

- Stata 17 with `reghdfejl`, `unique`, `estout`/`esttab`, and the estimate read/write commands used by the original project.
- R with `data.table`, `doParallel`, `ggplot2`, and `HonestDiD`.
- Python 3.10+ with the packages in `requirements.txt`.

For Python:

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
```

## Running locally or as one cluster job

Stata-only pipeline:

```text
stata-mp -b do master.do
```

Event-study plots after Stata completes:

```bash
Rscript plot_event_studies.R --root /groups/sgulzar/sa_fires/proj_bureaucrats_farms
```

The full sequential cluster entry point is:

```bash
sbatch sbatch/master.sbatch
```

Environment variables `REPLICATION_CODE`, `REPLICATION_ROOT`, `STATA_BIN`, `RSCRIPT_BIN`, and `PYTHON_BIN` can override executable or path defaults.

## Running as a SLURM array

The scalable workflow assigns one analysis dofile to each array task and launches post-processing only after all analyses succeed:

```bash
bash sbatch/submit_all.sh
```

Useful array overrides are `LOCATION`, `SAMPLE` (use `none` for empty), `RURAL_VAR`, `FE_LIST` (table models), and `EVENT_FE_LIST` (default `1`, required by the active plot layout). Logs go to `logs/`.

## Audit scope and provenance notes

- The audit is reproducible with `python python/audit_outputs.py --tex ../_report/main.tex --package .`.
- The design-map script corrects two internally inconsistent notebook labels by explicitly selecting March (`month=3`) and October (`month=10`) 2013.
- Static photographs/illustrations, the bibliography, and the preamble referenced by `main.tex` were not present in the repository snapshot. They are identified separately in `CODE_NOT_FOUND.md`; the package does not fabricate replacements.
- Outputs in `CODE_NOT_FOUND.md` remain intentionally unmatched. Existing intermediate images or `.tex` fragments were not presented as reproducible when their producing commands could not be traced.

# Replication Tables — Workflow Instructions

This document explains how the rural replication tables flow from cluster
analysis to the Overleaf paper, where each artifact lives, and the design
decisions baked into the current pipeline.

## File locations

### Source code (this repository)

```
code/_replication_rural/
├── _master_replication.do            ← top-level orchestrator (cluster)
├── _main_1_did.do                    ← analysis: main DiD
├── _main_2_event_study.do            ← analysis: event study
├── _main_3_bureau_polisc_did.do      ← analysis: bureaucrat × politician DiD
├── _main_4_protest_5km_fe12_did_downup.do
├── _main_5_polischar_fe12_did_downup_inter.do
├── _app_6_…_app_15_….do              ← appendix analyses (sections 5–14)
├── _generate_all_tables.do           ← LOCAL: ster → tex renderer
├── estsave_csv.ado                   ← helper ado for CSV exports
├── reports/                          ← review/comparison artifacts
│   ├── table_comparison.tex          ← overleaf-vs-dropbox PDF source
│   ├── table_comparison.pdf          ← rendered comparison
│   └── regen_available.do            ← one-off helper (delete when done)
└── instructions.md                   ← this file
```

### Generated outputs (Dropbox, not in git)

| Type | Path |
|------|------|
| Cluster `.ster` files (analysis output) | `~/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms/tex/paper/tables/` |
| Local `.tex` files (table render) | same folder as above |

The dofile writes both `.ster` (from analysis runs) and `.tex` (from
`_generate_all_tables.do`) to the **same** Dropbox `tables/` folder.

### Overleaf paper folder

```
~/Library/CloudStorage/Dropbox/Aplicaciones/Overleaf/sa_fires_politicians/
├── main.tex                          ← uses \input{tables/...}
├── tables/                           ← target location for paper tables
│   ├── main_did_downup_area_ac_rural.tex
│   ├── _main_3_bureau_polisc_did_rural.tex
│   └── …
```

The `tables/` folder under Overleaf is **separate** from the Dropbox
`tex/paper/tables/` folder. To use freshly-rendered tables in the paper,
copy or sync the relevant `.tex` files from the Dropbox project folder
into the Overleaf `tables/` folder.

## How to update the report

### Full pipeline (cluster → paper)

1. **On the cluster** — run the analysis dofiles (they have
   `global location "shell"`):
   ```bash
   sbatch <whatever-array-script-you-use>     # or:
   stata -b do _master_replication.do
   ```
   Each analysis dofile writes a `.ster` file to
   `…/proj_bureaucrats_farms/tex/paper/tables/<name>${sample}_rural.ster`.

2. **Sync the `.ster` files to your Mac** via the Dropbox client (they
   land in `~/Library/CloudStorage/Dropbox/sa_fires/…/tables/`).

3. **Locally** — run the table generator (this dofile uses
   `global location "dbox"`):
   ```bash
   stata -b do code/_replication_rural/_generate_all_tables.do
   ```
   This reads each `.ster` and writes a corresponding `.tex` to the same
   Dropbox folder. **Run this on your Mac, not on the cluster.**

4. **Copy the rendered `.tex` files into the Overleaf project**:
   ```
   cp ~/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms/tex/paper/tables/*.tex \
      ~/Library/CloudStorage/Dropbox/Aplicaciones/Overleaf/sa_fires_politicians/tables/
   ```
   (Or whatever sync/copy mechanism you prefer. Be careful not to
   overwrite hand-edited Overleaf tables that aren't produced by the
   dofile — see the list below.)

5. **Compile `main.tex` in Overleaf.**

### Quick reload after re-rendering tables only

If only the table format changed (no new analysis runs), step 3 alone is
enough — the `.ster` files don't need to be regenerated. Then copy and
recompile.

### Verifying the output before paper compile

`reports/table_comparison.pdf` shows each Overleaf-target table on top of
the current dofile output for a side-by-side eyeball check. Rebuild it
with:

```bash
cd code/_replication_rural/reports
pdflatex -interaction=nonstopmode table_comparison.tex
```

Both inputs are `\input`'d directly via absolute paths, so a fresh
compile picks up whatever is currently in the two source folders.

## Tables produced by `_generate_all_tables.do`

| Section | Output `.tex`                                           | Source `.ster`                                          |
|--------:|---------------------------------------------------------|---------------------------------------------------------|
|   1     | `main_did_downup_area_ac_rural.tex`                     | `main_did_downup_area_ac_rural.ster`                    |
|   2     | `_main_3_bureau_polisc_did_rural.tex`                   | `_main_3_bureau_polisc_did_rural.ster`                  |
|   3     | `_main_4_protest_5km_fe12_did_downup_rural.tex`         | `_main_4_protest_5km_fe12_did_downup_rural.ster`        |
|   4     | `_main_5_polischar_fe12_did_downup_inter_rural.tex`     | `_main_5_polischar_fe12_did_downup_inter_rural.ster`    |
|   5     | `_app_6_main_did_treat_definition_rural.tex`            | `_app_6_main_did_treat_definition_rural.ster`           |
|   6     | `_app_7_main_did_downup_area_ac_dv_rural.tex`           | `_app_7_main_did_downup_area_ac_dv_rural.ster`          |
|   7     | `_app_8_main_did_by_year_rural.tex`                     | `_app_8_main_did_by_year_rural.ster`                    |
|   8     | `_app_9_main_did_by_state_rural.tex`                    | `_app_9_main_did_by_state_rural.ster`                   |
|   9     | `_app_10_did_rice_moderators_rural.tex`                 | `_app_10_did_rice_moderators_rural.ster`                |
|  10     | `_app_11_placebo_pop_13km_rural.tex`                    | `_app_11_placebo_pop_13km_rural.ster`                   |
|  11     | `_app_12_protest_5km_fe_did_rural.tex`                  | `_app_12_protest_5km_fe_did_rural.ster`                 |
|  12     | `_app_13_protest_5km_fe12_did_ricemods_rural.tex`       | `_app_13_protest_5km_fe12_did_ricemods_rural.ster`      |
|  13     | `_app_14_polischar_fe12_did_ricemods_rural.tex`         | `_app_14_polischar_fe12_did_ricemods_rural.ster`        |
|  14     | `_app_15_polischar_fe12_did_rural.tex`                  | `_app_15_polischar_fe12_did_rural.ster`                 |

### Tables in `main.tex` not produced by this dofile

These come from other pipelines (event-study plots, descriptive scripts,
hand-edited tables) — **the generator does not touch them**:

- `_1_placebo_pop_13km.tex` (note: similar name to `_app_11`, but
  different file; the `_app_11` output is **not** input by `main.tex`)
- `protest_2km.tex`, `protest_10km.tex`
- `_edit_pols_char_didtable.tex`
- `10_pr_cluster_2022_5kmtable.tex`
- `ac_rice.tex`, `ac_agriwork.tex`, `ac_myneta.tex`

If you re-render any of those, do it from their own pipeline.

## Strong decisions baked into this pipeline

These are non-obvious choices we settled during the cleanup session — change
them only with care.

### 1. `_generate_all_tables.do` runs LOCALLY (`dbox`), not on the cluster

```stata
global location "dbox"
global sample ""
```

Every other `_main_*.do` and `_app_*.do` in `_replication_rural/` uses
`global location "shell"` because they do the heavy lifting on the
cluster. `_generate_all_tables.do` is the one exception — it just reads
ster files and writes tex, so we run it locally on the Mac after the
cluster jobs finish. **Do not switch this file to `"shell"`.**

### 2. Trailing-zero stripping happens at render time, not in the analysis

The helper program `_strip_zeros_stats` (defined at the top of
`_generate_all_tables.do`) reads the `Mean DV*` value, formats it with
`%9.3f`, and strips trailing zeros via regex. Result: `160.300 → 160.3`,
`382.643 → 382.643` (unchanged), `160.000 → 160`.

The cleaned value is written to a sibling e()-macro named
`<stat>_clean` (e.g. `ymean_clean`) and the `esttab stats(...)` list
references the `_clean` name. **We never overwrite the original
`e(ymean)`** because going from `estadd scalar` → `estadd local` of the
same name triggers `e(<name>) already defined`.

This means the analysis dofiles (`_main_4.do`, `_main_5.do`, etc.) are
**unchanged** — the cluster doesn't need to re-run when we want a
formatting-only update.

### 3. Label consistency rules (apply across all 14 sections)

- `Election FE` / `Electoral Cycle FE` / `Elections FE` → **`Legislature FE`**
- All FE labels use uppercase **`FE`** (no `fe`)
- `Assembly` / `Number of Assembly` / `N Assembly Constituencies ` (with
  stray spaces) → **`N Assembly Constituencies`**
- Cross-product symbols always use LaTeX `$\times$` — **never the literal
  letter `x`**
- All 14 tables show **`N Assembly Constituencies`** in their stats footer
  (requires `acq` to be stored in the ster file — see exception below)
- `Time FE` → `Relative Time FE` for the protest / polischar event-study
  tables (sections 11, 12, 13, 14)

### 4. Known ster-file gap: `_main_3` is missing `e(acq)`

`_main_3_bureau_polisc_did.do` computes `local n_assemblies = r(N)` but
**never calls `estadd scalar acq = `n_assemblies'`**. So Section 2's
`N Assembly Constituencies` row renders empty even though the dofile
includes it in the stats list.

**To fix**: open `_main_3_bureau_polisc_did.do`, find each
`estimates store eq*`, and insert `estadd scalar acq = `n_assemblies'`
just before it. Then re-run `_main_3` on the cluster to regenerate the
ster file. After the new ster lands, `_generate_all_tables.do` will
populate the row automatically.

### 5. Manual edits to `_main_4_…_rural.tex` and `_main_5_…_rural.tex`
   are now obsolete

While the rural ster files for `_main_4` and `_main_5` were missing, we
hand-edited those two `.tex` outputs in Dropbox to apply the new
formatting. Now that the rural ster files have arrived, the dofile
overwrites those tex files on every run — and that is the correct
behavior. Don't reapply hand edits after a fresh run.

### 6. Posthead `""` is required to suppress an extra `\hline`

Sections that pre-build a custom column header in `prehead(...)` and use
`nomtitles nonumbers` need an explicit `posthead("")`, otherwise esttab
emits an extra `\hline` between the header row and the body. Sections 1,
3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14 all carry `posthead("")` for this
reason. Don't remove it.

## Helper artifacts (safe to delete)

- `reports/regen_available.do` — used during the rebuild to regenerate
  sections 5-14 against their existing ster files. Once the full
  pipeline runs end-to-end via `_generate_all_tables.do`, this helper is
  redundant.
- `reports/test_regex.do` — verification of the trailing-zero regex.
  Keep if you want a sanity test handy; otherwise delete.

`reports/table_comparison.tex` and `table_comparison.pdf` are the
evergreen comparison artifacts — keep those for ongoing review.
